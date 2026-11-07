import secrets
import pytest
from fastapi.testclient import TestClient
from app.core.config import settings


def _get_error_message(resp) -> str:
    body = resp.json()
    if isinstance(body, dict):
        if "error" in body and isinstance(body["error"], dict):
            return body["error"].get("message", "")
        return str(body.get("detail", ""))
    return ""


def test_admin_registration_valid_super_key(client: TestClient):
    """Origin PG Owner registers with valid Common Super Key and is immediately activated."""
    unique = secrets.token_hex(4)
    email = f"owner_valid_{unique}@originpg.com"
    super_key = settings.ADMIN_REGISTRATION_SUPER_KEY or "ORIGIN_PG_SUPER_KEY_2026"

    response = client.post(
        "/api/v1/auth/admin/register",
        json={
            "business_name": f"Origin Verified PG {unique}",
            "email": email,
            "password": "ValidAdminPass@123",
            "confirm_password": "ValidAdminPass@123",
            "super_key": super_key,
        },
    )
    assert response.status_code == 201
    data = response.json()["data"]
    assert data["email"] == email
    assert data["role"] in ("PROPERTY_MANAGER", "SUPER_ADMIN")
    assert data["is_active"] is True
    assert data["is_verified"] is True
    assert data["approval_status"] == "APPROVED"
    assert "company" in data
    assert "user" in data


def test_admin_registration_invalid_super_key(client: TestClient):
    """Registration with an invalid Super Key is rejected with 400 Bad Request."""
    unique = secrets.token_hex(4)
    email = f"owner_invalid_{unique}@originpg.com"

    response = client.post(
        "/api/v1/auth/admin/register",
        json={
            "business_name": f"Invalid Key PG {unique}",
            "email": email,
            "password": "ValidAdminPass@123",
            "confirm_password": "ValidAdminPass@123",
            "super_key": "INCORRECT_SUPER_KEY_9999",
        },
    )
    assert response.status_code == 400
    msg = _get_error_message(response).lower()
    assert "super key" in msg or "invalid" in msg


def test_admin_registration_missing_super_key(client: TestClient):
    """Registration without a super_key field fails schema validation (422)."""
    unique = secrets.token_hex(4)
    email = f"owner_missing_{unique}@originpg.com"

    response = client.post(
        "/api/v1/auth/admin/register",
        json={
            "business_name": f"Missing Key PG {unique}",
            "email": email,
            "password": "ValidAdminPass@123",
            "confirm_password": "ValidAdminPass@123",
        },
    )
    assert response.status_code == 422


def test_admin_registration_duplicate_email(client: TestClient):
    """Registering an email that already exists returns 409 Conflict."""
    unique = secrets.token_hex(4)
    email = f"owner_dup_{unique}@originpg.com"
    super_key = settings.ADMIN_REGISTRATION_SUPER_KEY or "ORIGIN_PG_SUPER_KEY_2026"

    # First registration
    resp1 = client.post(
        "/api/v1/auth/admin/register",
        json={
            "business_name": f"Dup PG {unique}",
            "email": email,
            "password": "ValidAdminPass@123",
            "confirm_password": "ValidAdminPass@123",
            "super_key": super_key,
        },
    )
    assert resp1.status_code == 201

    # Second registration with same email
    resp2 = client.post(
        "/api/v1/auth/admin/register",
        json={
            "business_name": f"Dup PG 2 {unique}",
            "email": email,
            "password": "ValidAdminPass@123",
            "confirm_password": "ValidAdminPass@123",
            "super_key": super_key,
        },
    )
    assert resp2.status_code == 409
    msg = _get_error_message(resp2).lower()
    assert "already exists" in msg or "already registered" in msg


def test_admin_login_email_password_only_direct_tokens(client: TestClient):
    """Admin logs in using ONLY Email and Password and directly receives JWT tokens without 2FA."""
    unique = secrets.token_hex(4)
    email = f"login_admin_{unique}@originpg.com"
    password = "AdminLoginPass@123"
    super_key = settings.ADMIN_REGISTRATION_SUPER_KEY or "ORIGIN_PG_SUPER_KEY_2026"

    # Register admin
    reg_resp = client.post(
        "/api/v1/auth/admin/register",
        json={
            "business_name": f"Login Test PG {unique}",
            "email": email,
            "password": password,
            "confirm_password": password,
            "super_key": super_key,
        },
    )
    assert reg_resp.status_code == 201

    # Direct login with Email + Password only
    login_resp = client.post(
        "/api/v1/auth/admin/login",
        json={
            "email": email,
            "password": password,
        },
    )
    assert login_resp.status_code == 200
    token_data = login_resp.json()["data"]
    assert "access_token" in token_data
    assert "refresh_token" in token_data
    assert token_data["token_type"] == "bearer"
    assert token_data["user"]["email"] == email
    # Confirm NO 2FA or Super Key step was requested
    assert token_data.get("requires_2fa") is not True


def test_admin_login_invalid_password(client: TestClient):
    """Admin login with wrong password returns 401 Unauthorized."""
    unique = secrets.token_hex(4)
    email = f"wrong_pass_{unique}@originpg.com"
    password = "CorrectPass@123"
    super_key = settings.ADMIN_REGISTRATION_SUPER_KEY or "ORIGIN_PG_SUPER_KEY_2026"

    # Register
    client.post(
        "/api/v1/auth/admin/register",
        json={
            "business_name": f"Wrong Pass PG {unique}",
            "email": email,
            "password": password,
            "confirm_password": password,
            "super_key": super_key,
        },
    )

    # Attempt login with incorrect password
    resp = client.post(
        "/api/v1/auth/admin/login",
        json={
            "email": email,
            "password": "IncorrectPassword999",
        },
    )
    assert resp.status_code == 401


def test_admin_login_rejects_resident_role(client: TestClient):
    """Residents cannot log in via the admin login endpoint."""
    resp = client.post(
        "/api/v1/auth/admin/login",
        json={
            "email": "demo_test_resident@originpg.com",
            "password": "AnyPassword123!",
        },
    )
    # Either 401 (if password doesn't match) or 403 (Resident access denied)
    assert resp.status_code in (401, 403)


def test_admin_registration_to_login_case_insensitive_super_key_and_dashboard_access(client: TestClient):
    """End-to-end verification of registration with lowercase/mixed-case super key, immediate activation, and dashboard login."""
    unique = secrets.token_hex(4)
    email = f"owner_flow_{unique}@originpg.com"
    password = "OwnerPass@2026!"
    # User types lowercase super key
    super_key_input = "org-240-x7k9-pq82"

    reg_resp = client.post(
        "/api/v1/auth/admin/register",
        json={
            "business_name": f"EndToEnd PG {unique}",
            "email": email,
            "password": password,
            "confirm_password": password,
            "super_key": super_key_input,
        },
    )
    assert reg_resp.status_code == 201
    reg_data = reg_resp.json()["data"]
    assert reg_data["email"] == email.lower()
    assert reg_data["role"] == "PROPERTY_MANAGER"
    assert reg_data["is_active"] is True
    assert reg_data["is_verified"] is True
    assert reg_data["approval_status"] == "APPROVED"

    # Login with exact same credentials
    login_resp = client.post(
        "/api/v1/auth/admin/login",
        json={
            "email": email,
            "password": password,
        },
    )
    assert login_resp.status_code == 200
    login_data = login_resp.json()["data"]
    assert "access_token" in login_data
    token = login_data["access_token"]
    assert login_data["user"]["role"]["name"] == "PROPERTY_MANAGER"
    assert login_data["user"]["is_active"] is True

    # User accesses dashboard / me and bed capacity
    headers = {"Authorization": f"Bearer {token}"}
    me_resp = client.get("/api/v1/auth/me", headers=headers)
    assert me_resp.status_code == 200
    assert me_resp.json()["data"]["role"]["name"] == "PROPERTY_MANAGER"

    cap_resp = client.get("/api/v1/company/bed-capacity", headers=headers)
    assert cap_resp.status_code == 200
    assert cap_resp.json()["data"]["total_capacity"] == 240
    assert cap_resp.json()["data"]["used_beds"] == 0
