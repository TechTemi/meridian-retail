"""
Basic smoke tests for auth-service.
Run with: pytest tests/test_auth.py
Requires a running Postgres reachable via the DB_* env vars.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fastapi.testclient import TestClient
from main import app

client = TestClient(app)


def test_healthz():
    resp = client.get("/healthz")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"


def test_signup_and_login_flow():
    email = "pytest-user@example.com"
    password = "correct-horse-battery-staple"

    # clean slate is assumed handled by test DB fixtures/CI setup
    signup_resp = client.post("/api/auth/signup", json={"email": email, "password": password})
    assert signup_resp.status_code in (200, 409)  # 409 if re-run against same DB

    login_resp = client.post("/api/auth/login", json={"email": email, "password": password})
    assert login_resp.status_code == 200
    assert "token" in login_resp.json()
