"""Realistic traffic generator (Python stdlib only, no installs needed).

Simulates users: browse tasks, create tasks, delete tasks, hit a slow endpoint,
and occasionally request a page that does not exist.

  python3 loadgen.py --url http://localhost:8081 --rps 20
  python3 loadgen.py --url http://localhost:8081 --rps 100 --duration 60   # spike
"""

import argparse
import json
import random
import threading
import time
import urllib.error
import urllib.request
from collections import Counter

stats = Counter()
lock = threading.Lock()
created_ids = []


def call(method, url, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method,
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            payload = resp.read()
            code = resp.status
    except urllib.error.HTTPError as e:
        payload, code = b"", e.code
    except Exception:  # connection refused, timeout... (e.g. during a rollout)
        payload, code = b"", "conn_error"
    with lock:
        stats[code] += 1
    return code, payload


def one_user_action(base):
    r = random.random()
    if r < 0.50:
        call("GET", f"{base}/api/tasks")
    elif r < 0.70:
        code, payload = call("POST", f"{base}/api/tasks",
                             {"title": f"task-{random.randint(1, 10_000)}"})
        if code == 201:
            with lock:
                created_ids.append(json.loads(payload)["id"])
    elif r < 0.80:
        with lock:
            task_id = created_ids.pop(0) if created_ids else 999_999
        call("DELETE", f"{base}/api/tasks/{task_id}")
    elif r < 0.93:
        call("GET", f"{base}/api/slow")
    elif r < 0.98:
        call("GET", f"{base}/")
    else:
        call("GET", f"{base}/does-not-exist")  # realistic 404s


def reporter(interval=10):
    while True:
        time.sleep(interval)
        with lock:
            snapshot = dict(stats)
            stats.clear()
        total = sum(snapshot.values())
        print(f"[loadgen] last {interval}s: {total} requests "
              f"({total / interval:.1f} rps) -> {snapshot}", flush=True)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--url", default="http://localhost:8081")
    p.add_argument("--rps", type=float, default=10, help="target requests per second")
    p.add_argument("--duration", type=int, default=0, help="seconds, 0 = forever")
    args = p.parse_args()

    base = args.url.rstrip("/")
    print(f"[loadgen] sending ~{args.rps} rps to {base}", flush=True)
    threading.Thread(target=reporter, daemon=True).start()

    end = time.time() + args.duration if args.duration else float("inf")
    interval = 1.0 / args.rps
    while time.time() < end:
        threading.Thread(target=one_user_action, args=(base,), daemon=True).start()
        # small jitter so traffic looks organic, not perfectly regular
        time.sleep(interval * random.uniform(0.7, 1.3))


if __name__ == "__main__":
    main()
