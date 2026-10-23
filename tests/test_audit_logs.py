from tests.test_roles_and_scopes import get_token


def test_audit_logs_recorded_and_retrieved(client):
    admin_token = get_token(client, "admin@originpg.com", "Admin@123456")

    # Fetch audit logs as Super Admin
    resp = client.get(
        "/api/v1/audit-logs",
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert resp.status_code == 200
    data = resp.json()["data"]
    assert data["total"] > 0
    items = data["items"]

    # Verify actions were captured
    actions = {item["action"] for item in items}
    assert "AUTH_LOGIN" in actions


def test_manager_cannot_view_audit_logs(client):
    mgr_token = get_token(client, "manager@originpg.com", "Manager@123456")
    resp = client.get(
        "/api/v1/audit-logs",
        headers={"Authorization": f"Bearer {mgr_token}"},
    )
    assert resp.status_code == 403
    assert resp.json()["error"]["code"] == "PERMISSION_DENIED"
