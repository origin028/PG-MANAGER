import pytest

# Documented development test credentials for local testing
CREDS = {
    "admin": {"email": "admin@originpg.com", "phone": "9876543210", "pass": "Admin@123456"},
    "manager": {"email": "manager@originpg.com", "phone": "9876543211", "pass": "Manager@123456"},
    "staff": {"email": "staff@originpg.com", "phone": "9876543212", "pass": "Staff@123456"},
    "resident": {"email": "resident@originpg.com", "phone": "9876543213", "pass": "Resident@123456"},
}


def test_super_admin_login_email(client):
    """Super Admin authenticates with email via Admin Web client."""
    response = client.post(
        "/api/v1/auth/login",
        json={
            "identifier": CREDS["admin"]["email"],
            "password": CREDS["admin"]["pass"],
            "client_type": "admin_web",
        },
    )
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True
    assert data["data"]["token_type"] == "bearer"
    assert "access_token" in data["data"]
    assert "refresh_token" in data["data"]

    user = data["data"]["user"]
    assert user["email"] == CREDS["admin"]["email"]
    assert user["role"]["name"] == "SUPER_ADMIN"
    # Super Admin has portfolio-wide access (5 properties)
    assert len(user["allowed_properties"]) == 5


def test_super_admin_login_phone(client):
    """Super Admin authenticates with phone number via Admin Mobile client."""
    response = client.post(
        "/api/v1/auth/login",
        json={
            "identifier": CREDS["admin"]["phone"],
            "password": CREDS["admin"]["pass"],
            "client_type": "admin_mobile",
        },
    )
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True
    assert data["data"]["user"]["phone"] == CREDS["admin"]["phone"]


def test_property_manager_login(client):
    """Property Manager authenticates via Admin Web client."""
    response = client.post(
        "/api/v1/auth/login",
        json={
            "identifier": CREDS["manager"]["email"],
            "password": CREDS["manager"]["pass"],
            "client_type": "admin_web",
        },
    )
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True

    user = data["data"]["user"]
    assert user["role"]["name"] == "PROPERTY_MANAGER"
    # Property Manager has 2 assigned properties
    assert len(user["allowed_properties"]) == 2
    assigned_codes = {p["code"] for p in user["allowed_properties"]}
    assert assigned_codes == {"OG-KOR", "OG-HSR"}


def test_staff_login(client):
    """Staff authenticates via Admin Mobile client."""
    response = client.post(
        "/api/v1/auth/login",
        json={
            "identifier": CREDS["staff"]["email"],
            "password": CREDS["staff"]["pass"],
            "client_type": "admin_mobile",
        },
    )
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True

    user = data["data"]["user"]
    assert user["role"]["name"] == "STAFF"
    # Staff has 1 assigned property
    assert len(user["allowed_properties"]) == 1
    assert user["allowed_properties"][0]["code"] == "OG-KOR"


def test_resident_login_resident_app(client):
    """Resident authenticates via Resident Mobile client."""
    response = client.post(
        "/api/v1/auth/login",
        json={
            "identifier": CREDS["resident"]["email"],
            "password": CREDS["resident"]["pass"],
            "client_type": "resident_mobile",
        },
    )
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True

    user = data["data"]["user"]
    assert user["role"]["name"] == "RESIDENT"


def test_client_type_isolation_enforcement(client):
    """Verifies that client type access controls prevent cross-client login."""
    # 1. Resident cannot log into Admin Web
    resp = client.post(
        "/api/v1/auth/login",
        json={
            "identifier": CREDS["resident"]["email"],
            "password": CREDS["resident"]["pass"],
            "client_type": "admin_web",
        },
    )
    assert resp.status_code == 403
    assert resp.json()["error"]["code"] == "PERMISSION_DENIED"

    # 2. Resident cannot log into Admin Mobile
    resp = client.post(
        "/api/v1/auth/login",
        json={
            "identifier": CREDS["resident"]["email"],
            "password": CREDS["resident"]["pass"],
            "client_type": "admin_mobile",
        },
    )
    assert resp.status_code == 403
    assert resp.json()["error"]["code"] == "PERMISSION_DENIED"

    # 3. Super Admin cannot log into Resident Mobile
    resp = client.post(
        "/api/v1/auth/login",
        json={
            "identifier": CREDS["admin"]["email"],
            "password": CREDS["admin"]["pass"],
            "client_type": "resident_mobile",
        },
    )
    assert resp.status_code == 403
    assert resp.json()["error"]["code"] == "PERMISSION_DENIED"


def test_me_endpoint_for_all_seeded_roles(client):
    """Verifies GET /api/v1/auth/me returns the proper user profile for each role."""
    expected_roles = {
        "admin": "SUPER_ADMIN",
        "manager": "PROPERTY_MANAGER",
        "staff": "STAFF",
        "resident": "RESIDENT",
    }
    for role_key, client_type in [
        ("admin", "admin_web"),
        ("manager", "admin_web"),
        ("staff", "admin_mobile"),
        ("resident", "resident_mobile"),
    ]:
        login_resp = client.post(
            "/api/v1/auth/login",
            json={
                "identifier": CREDS[role_key]["email"],
                "password": CREDS[role_key]["pass"],
                "client_type": client_type,
            },
        )
        assert login_resp.status_code == 200
        token = login_resp.json()["data"]["access_token"]

        # Call /me endpoint with the Bearer token
        me_resp = client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {token}"})
        assert me_resp.status_code == 200
        me_data = me_resp.json()
        assert me_data["success"] is True
        assert me_data["data"]["email"] == CREDS[role_key]["email"]
        assert me_data["data"]["role"]["name"] == expected_roles[role_key]


def test_invalid_credentials_rejected(client):
    """Tests bad password rejection without protected data leakage."""
    resp = client.post(
        "/api/v1/auth/login",
        json={
            "identifier": CREDS["admin"]["email"],
            "password": "WrongPassword999#",
            "client_type": "admin_web",
        },
    )
    assert resp.status_code == 401
    data = resp.json()
    assert data["success"] is False
    assert data["error"]["code"] == "AUTHENTICATION_FAILED"
    # Confirm no stack traces or secrets returned
    assert data["error"]["details"] is None


def test_unknown_user_rejected(client):
    """Tests unknown user identifier rejection without leaking account presence."""
    resp = client.post(
        "/api/v1/auth/login",
        json={
            "identifier": "nonexistent@originpg.com",
            "password": "Password@123",
            "client_type": "admin_web",
        },
    )
    assert resp.status_code == 401
    data = resp.json()
    assert data["success"] is False
    assert data["error"]["code"] == "AUTHENTICATION_FAILED"


def test_unauthenticated_requests_denied(client):
    """Verifies that accessing protected endpoints without a Bearer token returns 401."""
    resp = client.get("/api/v1/auth/me")
    assert resp.status_code == 401
    data = resp.json()
    assert data["success"] is False
    assert data["error"]["code"] == "AUTHENTICATION_FAILED"

    resp_invalid_token = client.get(
        "/api/v1/auth/me",
        headers={"Authorization": "Bearer invalid.token.value"},
    )
    assert resp_invalid_token.status_code == 401
    assert resp_invalid_token.json()["error"]["code"] == "AUTHENTICATION_FAILED"
