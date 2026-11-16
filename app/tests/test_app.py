import pytest

from app import create_app


@pytest.fixture
def client():
    return create_app().test_client()


def test_health_endpoints(client):
    assert client.get("/healthz").status_code == 200
    assert client.get("/readyz").status_code == 200


def test_index_shows_version(client):
    resp = client.get("/")
    assert resp.status_code == 200
    assert b"Version" in resp.data


def test_create_list_delete_task(client):
    resp = client.post("/api/tasks", json={"title": "learn devops"})
    assert resp.status_code == 201
    task_id = resp.get_json()["id"]

    titles = [t["title"] for t in client.get("/api/tasks").get_json()]
    assert "learn devops" in titles

    assert client.delete(f"/api/tasks/{task_id}").status_code == 204
    assert client.delete(f"/api/tasks/{task_id}").status_code == 404


def test_create_task_requires_title(client):
    assert client.post("/api/tasks", json={}).status_code == 400


def test_metrics_exposed(client):
    client.get("/api/tasks")
    body = client.get("/metrics").data
    assert b"http_requests_total" in body
    assert b"http_request_duration_seconds_bucket" in body
