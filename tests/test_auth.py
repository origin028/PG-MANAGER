def test_super_admin_login_email(client):
    response = client.post(
        "/api/v1/auth/login",
        json={
            "identifier": "admin@originpg.com",
            "password": "Admin@123456",
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
    assert user["email"] == "admin@originpg.com"
    assert user["role"]["name"] == "SUPER_ADMIN"
    # Super Admin has access to all 5 properties
    assert len(user["allowed_properties"]) == 5


def test_super_admin_login_phone(client):
    response = client.post(
        "/api/v1/auth/login",
        json={
            "identifier": "9876543210",
            "password": "Admin@123456",
            "client_type": "admin_mobile",
        },
    )
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True
    assert data["data"]["user"]["phone"] == "9876543210"


def test_property_manager_login(client):
    response = client.post(
        "/api/v1/auth/login",
        json={
            "identifier": "manager@originpg.com",
            "password": "Manager@123456",
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


def test_staff_login(client):
    response = client.post(
        "/api/v1/auth/login",
        json={
            "identifier": "staff@originpg.com",
            "password": "Staff@123456",
            "client_type": "admin_mobile",
        },
    )
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True
    user = data["data"]["user"]
    assert user["role"]["name"] == "STAFF"
    assert len(user["allowed_properties"]) == 1


def test_resident_login_resident_app(client):
    response = client.post(
        "/api/v1/auth/login",
        json={
            "identifier": "resident@originpg.com",
            "password": "Resident@123456",
            "client_type": "resident_mobile",
        },
    )
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True
    user = data["data"]["user"]
    assert user["role"]["name"] == "RESIDENT"


def test_resident_blocked_from_admin_web(client):
    """Residents must never be allowed to log into Admin Web panel."""
    response = client.post(
        "/api/v1/auth/login",
        json={
            "identifier": "resident@originpg.com",
            "password": "Resident@123456",
            "client_type": "admin_web",
        },
    )
    assert response.status_code == 403
    data = response.json()
    assert data["success"] is False
    assert data["error"]["code"] == "PERMISSION_DENIED"


def test_resident_blocked_from_admin_mobile(client):
    """Residents must never be allowed to log into Admin Mobile app."""
    response = client.post(
        "/api/v1/auth/login",
        json={
            "identifier": "resident@originpg.com",
            "password": "Resident@123456",
            "client_type": "admin_mobile",
        },
    )
    assert response.status_code == 403
    data = response.json()
    assert data["success"] is False


def test_admin_blocked_from_resident_mobile(client):
    """Admin users cannot log into Resident app."""
    response = client.post(
        "/api/v1/auth/login",
        json={
            "identifier": "admin@originpg.com",
            "password": "Admin@123456",
            "client_type": "resident_mobile",
        },
    )
    assert response.status_code == 403
    data = response.json()
    assert data["success"] is False


def test_invalid_password(client):
    response = client.post(
        "/api/v1/auth/login",
        json={
            "identifier": "admin@originpg.com",
            "password": "WrongPassword999",
            "client_type": "admin_web",
        },
    )
    assert response.status_code == 401
    data = response.json()
    assert data["success"] is False
    assert data["error"]["code"] == "AUTHENTICATION_FAILED"


def test_invalid_user(client):
    response = client.post(
        "/api/v1/auth/login",
        json={
            "identifier": "nonexistent@originpg.com",
            "password": "Password@123",
            "client_type": "admin_web",
        },
    )
    assert response.status_code == 401


def test_token_refresh_lifecycle(client):
    # 1. Login
    login_resp = client.post(
        "/api/v1/auth/login",
        json={
            "identifier": "admin@originpg.com",
            "password": "Admin@123456",
            "client_type": "admin_web",
        },
    )
    tokens = login_resp.json()["data"]
    refresh_token = tokens["refresh_token"]

    # 2. Refresh
    refresh_resp = client.post(
        "/api/v1/auth/refresh",
        json={
            "refresh_token": refresh_token,
            "client_type": "admin_web",
        },
    )
    assert refresh_resp.status_code == 200
    refreshed_data = refresh_resp.json()["data"]
    assert "access_token" in refreshed_data

    # 3. Use new access token to query /me
    me_resp = client.get(
        "/api/v1/auth/me",
        headers={"Authorization": f"Bearer {refreshed_data['access_token']}"},
    )
    assert me_resp.status_code == 200
    assert me_resp.json()["data"]["email"] == "admin@originpg.com"


def test_logout_revokes_token(client):
    login_resp = client.post(
        "/api/v1/auth/login",
        json={
            "identifier": "manager@originpg.com",
            "password": "Manager@123456",
            "client_type": "admin_web",
        },
    )
    tokens = login_resp.json()["data"]
    access_token = tokens["access_token"]
    refresh_token = tokens["refresh_token"]

    # Logout
    logout_resp = client.post(
        "/api/v1/auth/logout",
        headers={"Authorization": f"Bearer {access_token}"},
        json={"refresh_token": refresh_token},
    )
    assert logout_resp.status_code == 200

    # Try refreshing with the revoked token -> must fail
    refresh_attempt = client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": refresh_token},
    )
    assert refresh_attempt.status_code == 401


def test_auth_me_unauthorized(client):
    response = client.get("/api/v1/auth/me")
    assert response.status_code == 401


def test_change_password_flow(client):
    # 1. Login
    login_resp = client.post(
        "/api/v1/auth/login",
        json={
            "identifier": "staff@originpg.com",
            "password": "Staff@123456",
            "client_type": "admin_mobile",
        },
    )
    access_token = login_resp.json()["data"]["access_token"]

    # 2. Change password
    change_resp = client.post(
        "/api/v1/auth/change-password",
        headers={"Authorization": f"Bearer {access_token}"},
        json={
            "current_password": "Staff@123456",
            "new_password": "NewStaffPass@2026",
        },
    )
    assert change_resp.status_code == 200

    # 3. Old password should fail
    old_login = client.post(
        "/api/v1/auth/login",
        json={
            "identifier": "staff@originpg.com",
            "password": "Staff@123456",
            "client_type": "admin_mobile",
        },
    )
    assert old_login.status_code == 401

    # 4. New password should succeed
    new_login = client.post(
        "/api/v1/auth/login",
        json={
            "identifier": "staff@originpg.com",
            "password": "NewStaffPass@2026",
            "client_type": "admin_mobile",
        },
    )
    assert new_login.status_code == 200
