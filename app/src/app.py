"""TaskApp - a tiny to-do REST API built to be observed.

Endpoints
  GET    /                 HTML page showing version + pod name (see rolling updates live)
  GET    /api/tasks        list tasks
  POST   /api/tasks        create task  {"title": "..."}
  DELETE /api/tasks/<id>   delete task
  GET    /api/slow         random latency (makes latency graphs interesting)
  GET    /healthz          liveness probe  (is the process alive?)
  GET    /readyz           readiness probe (can it take traffic?)
  GET    /metrics          Prometheus metrics

Config (12-factor: everything comes from environment variables)
  APP_VERSION   shown on the home page and in metrics (set by Helm from the image tag)
  ERROR_RATE    0.0-1.0, fraction of /api/* requests that fail with 500 (chaos testing)
  LOG_LEVEL     INFO / DEBUG / ...
"""

import json
import logging
import os
import random
import socket
import sys
import threading
import time

from flask import Flask, Response, g, jsonify, request
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    Counter,
    Gauge,
    Histogram,
    generate_latest,
)

APP_VERSION = os.getenv("APP_VERSION", "dev")
ERROR_RATE = float(os.getenv("ERROR_RATE", "0"))
HOSTNAME = socket.gethostname()  # in Kubernetes this is the pod name


# ---------------------------------------------------------------- logging ---
class JsonFormatter(logging.Formatter):
    """One JSON object per line: easy to ship to Loki/ELK and to grep."""

    def format(self, record):
        payload = {
            "ts": self.formatTime(record, "%Y-%m-%dT%H:%M:%S"),
            "level": record.levelname,
            "msg": record.getMessage(),
            "pod": HOSTNAME,
            "version": APP_VERSION,
        }
        payload.update(getattr(record, "extra_fields", {}))
        return json.dumps(payload)


handler = logging.StreamHandler(sys.stdout)  # containers log to stdout, never files
handler.setFormatter(JsonFormatter())
log = logging.getLogger("taskapp")
log.addHandler(handler)
log.setLevel(os.getenv("LOG_LEVEL", "INFO"))
log.propagate = False

# ---------------------------------------------------------------- metrics ---
# RED method: Rate, Errors, Duration -> the three graphs every service needs.
REQUESTS = Counter(
    "http_requests_total", "Total HTTP requests", ["method", "endpoint", "status"]
)
LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency",
    ["method", "endpoint"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5),
)
IN_PROGRESS = Gauge("http_requests_in_progress", "Requests currently being served")
TASKS = Gauge("taskapp_tasks", "Number of tasks currently stored")
APP_INFO = Gauge("taskapp_info", "Build info", ["version"])
APP_INFO.labels(version=APP_VERSION).set(1)

# ------------------------------------------------------------------ state ---
# In-memory store keeps the demo dependency-free. In real life: a database.
_tasks = {}
_next_id = 1
_lock = threading.Lock()


def create_app():
    app = Flask(__name__)

    @app.before_request
    def _start_timer():
        g.start = time.perf_counter()
        IN_PROGRESS.inc()

    @app.after_request
    def _record(response):
        # url_rule gives "/api/tasks/<int:task_id>" instead of "/api/tasks/42":
        # keeps metric label cardinality low (a classic Prometheus best practice).
        endpoint = request.url_rule.rule if request.url_rule else "unmatched"
        elapsed = time.perf_counter() - g.get("start", time.perf_counter())
        if endpoint != "/metrics":
            REQUESTS.labels(request.method, endpoint, response.status_code).inc()
            LATENCY.labels(request.method, endpoint).observe(elapsed)
            log.info(
                "request",
                extra={
                    "extra_fields": {
                        "method": request.method,
                        "path": request.path,
                        "status": response.status_code,
                        "duration_ms": round(elapsed * 1000, 2),
                    }
                },
            )
        return response

    @app.teardown_request
    def _done(_exc):
        IN_PROGRESS.dec()

    def _maybe_fail():
        """Chaos hook: fail a fraction of requests when ERROR_RATE > 0."""
        if ERROR_RATE > 0 and random.random() < ERROR_RATE:
            return jsonify(error="injected failure"), 500
        return None

    # ---------------------------------------------------------- routes ---
    @app.get("/")
    def index():
        return (
            "<html><body style='font-family:sans-serif;padding:2rem'>"
            "<h1>TaskApp v2 - shipped by a pipeline</h1>"
            f"<p>Version: <b>{APP_VERSION}</b></p>"
            f"<p>Served by pod: <b>{HOSTNAME}</b></p>"
            f"<p>Tasks stored: <b>{len(_tasks)}</b></p>"
            "<p><a href='/api/tasks'>/api/tasks</a> · "
            "<a href='/metrics'>/metrics</a></p>"
            "</body></html>"
        )

    @app.get("/api/tasks")
    def list_tasks():
        if (err := _maybe_fail()) is not None:
            return err
        with _lock:
            return jsonify(list(_tasks.values()))

    @app.post("/api/tasks")
    def create_task():
        global _next_id
        if (err := _maybe_fail()) is not None:
            return err
        data = request.get_json(silent=True) or {}
        title = str(data.get("title", "")).strip()
        if not title:
            return jsonify(error="'title' is required"), 400
        with _lock:
            task = {"id": _next_id, "title": title[:200], "done": False}
            _tasks[_next_id] = task
            _next_id += 1
            TASKS.set(len(_tasks))
        return jsonify(task), 201

    @app.delete("/api/tasks/<int:task_id>")
    def delete_task(task_id):
        if (err := _maybe_fail()) is not None:
            return err
        with _lock:
            if _tasks.pop(task_id, None) is None:
                return jsonify(error="not found"), 404
            TASKS.set(len(_tasks))
        return "", 204

    @app.get("/api/slow")
    def slow():
        if (err := _maybe_fail()) is not None:
            return err
        delay = random.choice([0.05, 0.1, 0.2, 0.4, 0.8, 1.5])
        time.sleep(delay)
        return jsonify(slept_seconds=delay)

    @app.get("/healthz")
    def healthz():
        return jsonify(status="ok")

    @app.get("/readyz")
    def readyz():
        # A real app would check its database / dependencies here.
        return jsonify(status="ready")

    @app.get("/metrics")
    def metrics():
        return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)

    return app


app = create_app()

if __name__ == "__main__":  # local dev only; production uses gunicorn
    app.run(host="0.0.0.0", port=8000, debug=False)
