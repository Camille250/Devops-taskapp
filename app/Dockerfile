# syntax=docker/dockerfile:1
# ---------------------------------------------------------------------------
# Multi-stage build:
#   base    -> shared Python + runtime deps
#   test    -> adds dev deps, runs lint + unit tests (CI builds this target)
#   runtime -> small final image, non-root, no compilers, no tests
# ---------------------------------------------------------------------------
FROM python:3.13-slim AS base
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /app
# Copy requirements first so this layer is cached until deps change.
COPY requirements.txt .
RUN pip install -r requirements.txt

FROM base AS test
COPY requirements-dev.txt ruff.toml ./
RUN pip install -r requirements-dev.txt
COPY src ./src
COPY tests ./tests
RUN ruff check src tests && pytest -q tests

FROM base AS runtime
ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION}
LABEL org.opencontainers.image.title="taskapp" \
      org.opencontainers.image.version="${APP_VERSION}"
# Never run as root inside a container.
RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin appuser
COPY --chown=appuser:appuser src ./src
USER 10001
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=3s CMD python -c "import urllib.request;urllib.request.urlopen('http://localhost:8000/healthz')"
# 1 worker + threads keeps prometheus_client metrics in a single process.
CMD ["gunicorn", "--chdir", "src", "--bind", "0.0.0.0:8000", "--workers", "1", "--threads", "8", "--access-logfile", "-", "app:app"]
