"""Regression tests for the Phase-0 security fixes (audit findings C1-C6)."""
import hashlib
import hmac
import json

import pytest
from fastapi.testclient import TestClient

from app.core.config import Settings
from app.core.rate_limit import hit, reset_rate_limits
from app.integrations.payment_gateway import MockPaymentGateway, RazorpayGateway

PROD_ENV = {
    "ENVIRONMENT": "production",
    "SECRET_KEY": "x" * 48,
    "ENCRYPTION_KEY": "Yb0o1CkX8f2QO3m4hQ0u8dK1m3o7wJ9eR5tU2vP6nLs=",
    "DATABASE_URL": "postgresql://u:p@db.internal:5432/pg",
    "CORS_ORIGINS": "https://admin.example.com",
    "EMAIL_PROVIDER": "SMTP",
    "SMTP_USERNAME": "a@example.com",
    "SMTP_PASSWORD": "pw",
    "SMTP_FROM_EMAIL": "a@example.com",
    "ADMIN_REGISTRATION_SUPER_KEY": "KEY-123",
}


def prod(monkeypatch, **overrides):
    for k, v in {**PROD_ENV, **overrides}.items():
        monkeypatch.setenv(k, v)
    return Settings(_env_file=None)


# ---- C1 / C3: payment signatures -------------------------------------------
def test_razorpay_rejects_demo_webhook_signatures():
    gw = RazorpayGateway("key", "secret")
    for forged in ("demo_sig", "demo_sig_anything", "valid_mock_signature"):
        assert gw.verify_webhook_signature(b"{}", forged, "whsec") is False
        assert gw.verify_payment_signature("order_1", "pay_1", forged) is False


def test_razorpay_accepts_only_correct_hmac():
    gw = RazorpayGateway("key", "secret")
    body = b'{"event":"payment.captured"}'
    good = hmac.new(b"whsec", body, hashlib.sha256).hexdigest()
    assert gw.verify_webhook_signature(body, good, "whsec") is True
    assert gw.verify_webhook_signature(body, good[:-1] + "0", "whsec") is False


def test_forged_webhook_rejected_over_http(client: TestClient, monkeypatch):
    from app.core.config import settings

    monkeypatch.setattr(settings, "PAYMENT_GATEWAY_PROVIDER", "RAZORPAY")
    monkeypatch.setattr(settings, "RAZORPAY_KEY_ID", "key")
    monkeypatch.setattr(settings, "RAZORPAY_KEY_SECRET", "secret")
    monkeypatch.setattr(settings, "RAZORPAY_WEBHOOK_SECRET", "whsec")
    resp = client.post(
        "/api/v1/payments/webhook/razorpay",
        content=json.dumps({"event": "payment.captured"}),
        headers={"X-Razorpay-Signature": "demo_sig_forged", "Content-Type": "application/json"},
    )
    assert resp.status_code in (400, 401, 403)


def test_mock_gateway_refused_in_production(monkeypatch):
    from app.core.config import settings
    from app.integrations.payment_gateway import get_payment_gateway

    monkeypatch.setattr(settings, "ENVIRONMENT", "production")
    monkeypatch.setattr(settings, "PAYMENT_GATEWAY_PROVIDER", "AUTO")
    monkeypatch.setattr(settings, "RAZORPAY_KEY_ID", "")
    with pytest.raises(ValueError):
        get_payment_gateway()
    monkeypatch.setattr(settings, "PAYMENT_GATEWAY_PROVIDER", "MOCK")
    with pytest.raises(ValueError):
        get_payment_gateway()


def test_mock_gateway_still_works_for_tests():
    gw = MockPaymentGateway()
    assert gw.verify_webhook_signature(b"{}", "demo_sig", "s") is True


# ---- C2: demo_token --------------------------------------------------------
def test_demo_token_never_authenticates(client: TestClient):
    for token in ("demo_token", "demo_token_9876543210"):
        resp = client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {token}"})
        assert resp.status_code == 401


# ---- C4 / C5: config fail-closed -------------------------------------------
def test_production_config_valid(monkeypatch):
    assert prod(monkeypatch).is_production is True


@pytest.mark.parametrize(
    "override",
    [
        {"SECRET_KEY": "short"},
        {"SECRET_KEY": ""},
        {"CORS_ORIGINS": "*"},
        {"CORS_ORIGINS": ""},
        {"DEBUG": "true"},
        {"EMAIL_PROVIDER": "MOCK"},
        {"PAYMENT_GATEWAY_PROVIDER": "MOCK"},
        {"DATABASE_URL": "postgresql://u:p@localhost/pg"},
        {"ENCRYPTION_KEY": "not-a-fernet-key"},
        {"ENCRYPTION_KEY": ""},
        {"ADMIN_REGISTRATION_SUPER_KEY": ""},
        {"SMTP_PASSWORD": ""},
    ],
)
def test_production_refuses_insecure_config(monkeypatch, override):
    with pytest.raises(Exception, match="insecure production configuration|validation error"):
        prod(monkeypatch, **override)


def test_unset_environment_defaults_to_production(monkeypatch):
    monkeypatch.delenv("ENVIRONMENT", raising=False)
    with pytest.raises(Exception):
        Settings(_env_file=None)


def test_cors_does_not_reflect_unknown_origin(client: TestClient):
    resp = client.get("/api/v1/health/live", headers={"Origin": "https://evil.example"})
    assert "access-control-allow-origin" not in {k.lower() for k in resp.headers}
    pre = client.options(
        "/api/v1/auth/login",
        headers={"Origin": "https://evil.example", "Access-Control-Request-Method": "POST"},
    )
    assert "access-control-allow-origin" not in {k.lower() for k in pre.headers}


def test_cors_allows_configured_origin(client: TestClient):
    resp = client.get("/api/v1/health/live", headers={"Origin": "http://localhost:5173"})
    assert resp.headers.get("access-control-allow-origin") == "http://localhost:5173"


def test_security_headers_and_request_id(client: TestClient):
    resp = client.get("/api/v1/health/live", headers={"X-Request-ID": "abc123"})
    assert resp.headers["x-content-type-options"] == "nosniff"
    assert resp.headers["x-frame-options"] == "DENY"
    assert resp.headers["x-request-id"] == "abc123"
    assert resp.headers["cache-control"] == "no-store"


def test_public_health_does_not_leak_config(client: TestClient):
    body = client.get("/api/v1/health").text.lower()
    for leaked in ("smtp", "brevo", "resend", "sendgrid", "environment", "alembic"):
        assert leaked not in body


def test_error_codes_are_stable_and_leak_nothing(client: TestClient):
    r = client.get("/api/v1/auth/me")
    assert r.status_code == 401
    assert r.json()["error"]["code"] in ("UNAUTHENTICATED", "AUTHENTICATION_FAILED")
    r = client.get("/api/v1/does-not-exist")
    assert r.json()["error"]["code"] == "NOT_FOUND"


def test_invalid_jwt_does_not_echo_library_message(client: TestClient):
    r = client.get("/api/v1/auth/me", headers={"Authorization": "Bearer not.a.jwt"})
    assert r.status_code == 401
    assert "segments" not in r.text.lower() and "decode" not in r.text.lower()


# ---- C6: rate limiting -----------------------------------------------------
def test_rate_limiter_blocks_after_limit():
    reset_rate_limits()
    assert all(hit("t:1.1.1.1", 3, 60) == 0 for _ in range(3))
    assert hit("t:1.1.1.1", 3, 60) > 0
    assert hit("t:2.2.2.2", 3, 60) == 0


# ---- Auth: throttle, lockout, refresh rotation -----------------------------
@pytest.fixture
def limits_on(monkeypatch):
    from app.core.config import settings

    reset_rate_limits()
    monkeypatch.setattr(settings, "RATE_LIMIT_ENABLED", True)
    yield
    reset_rate_limits()


def _login(client, ident, pw):
    return client.post(
        "/api/v1/auth/login",
        json={"identifier": ident, "password": pw, "client_type": "admin_web"},
    )


def test_login_endpoint_is_throttled_per_ip(client: TestClient, limits_on):
    codes = [_login(client, f"nobody{i}@example.com", "x").status_code for i in range(12)]
    assert 429 in codes
    assert codes[:10].count(429) == 0


def test_account_lockout_after_repeated_failures(client: TestClient, limits_on):
    for _ in range(5):
        assert _login(client, "victim@example.com", "wrong").status_code == 401
    r = _login(client, "victim@example.com", "wrong")
    assert r.status_code == 429
    assert r.json()["error"]["code"] == "ACCOUNT_LOCKED"


def _register_admin(client):
    from app.core.config import settings

    reg = client.post(
        "/api/v1/auth/admin/register",
        json={
            "full_name": "Owner One",
            "email": "owner.one@example.com",
            "phone": "9876500001",
            "password": "StrongPass#123",
            "business_name": "Test PG",
            "super_key": settings.ADMIN_REGISTRATION_SUPER_KEY,
        },
    )
    return reg


def test_refresh_token_rotation_and_reuse_detection(client: TestClient):
    reg = _register_admin(client)
    assert reg.status_code in (200, 201), reg.text
    data = reg.json()["data"]
    tokens = data.get("tokens") or data
    old = tokens.get("refresh_token")
    if not old:
        login = _login(client, "owner.one@example.com", "StrongPass#123")
        old = login.json()["data"]["refresh_token"]

    first = client.post("/api/v1/auth/refresh", json={"refresh_token": old, "client_type": "admin_web"})
    assert first.status_code == 200, first.text
    new = first.json()["data"]["refresh_token"]
    assert new != old

    # Replaying the old (rotated) token is rejected AND revokes the whole family.
    replay = client.post("/api/v1/auth/refresh", json={"refresh_token": old, "client_type": "admin_web"})
    assert replay.status_code == 401
    after = client.post("/api/v1/auth/refresh", json={"refresh_token": new, "client_type": "admin_web"})
    assert after.status_code == 401
