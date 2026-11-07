import pytest
import uuid

CREDS = {
    "admin": {"email": "admin@originpg.com", "pass": "Admin@123456", "client": "admin_web"},
    "manager": {"email": "manager@originpg.com", "pass": "Manager@123456", "client": "admin_web"},
    "staff": {"email": "staff@originpg.com", "pass": "Staff@123456", "client": "admin_mobile"},
    "resident": {"email": "resident@originpg.com", "pass": "Resident@123456", "client": "resident_mobile"},
}


def get_token(client, role_key):
    resp = client.post(
        "/api/v1/auth/login",
        json={
            "identifier": CREDS[role_key]["email"],
            "password": CREDS[role_key]["pass"],
            "client_type": CREDS[role_key]["client"],
        },
    )
    assert resp.status_code == 200
    return resp.json()["data"]["access_token"]


def test_super_admin_full_portfolio_access(client):
    """Super Admin can access all 5 properties and audit logs."""
    token = get_token(client, "admin")
    resp = client.get("/api/v1/properties", headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 200
    props = resp.json()["data"]
    assert len(props) == 5

    # Access audit logs
    audit_resp = client.get("/api/v1/audit-logs", headers={"Authorization": f"Bearer {token}"})
    assert audit_resp.status_code == 200

    # Access users list
    users_resp = client.get("/api/v1/users", headers={"Authorization": f"Bearer {token}"})
    assert users_resp.status_code == 200
    assert users_resp.json()["data"]["total"] == 4


def test_property_manager_scoped_access(client):
    """Property Manager is restricted to assigned properties (OG-KOR and OG-HSR)."""
    admin_token = get_token(client, "admin")
    all_props = client.get(
        "/api/v1/properties", headers={"Authorization": f"Bearer {admin_token}"}
    ).json()["data"]
    kor_prop = next(p for p in all_props if p["code"] == "OG-KOR")
    ind_prop = next(p for p in all_props if p["code"] == "OG-IND")

    mgr_token = get_token(client, "manager")

    # 1. Manager listing properties returns only their 2 assigned properties
    list_resp = client.get("/api/v1/properties", headers={"Authorization": f"Bearer {mgr_token}"})
    assert list_resp.status_code == 200
    mgr_props = list_resp.json()["data"]
    assert len(mgr_props) == 2
    assert {p["code"] for p in mgr_props} == {"OG-KOR", "OG-HSR"}

    # 2. Manager can view details of assigned property
    kor_resp = client.get(f"/api/v1/properties/{kor_prop['id']}", headers={"Authorization": f"Bearer {mgr_token}"})
    assert kor_resp.status_code == 200
    assert kor_resp.json()["data"]["code"] == "OG-KOR"

    # 3. Manager blocked from unassigned property (OG-IND)
    ind_resp = client.get(f"/api/v1/properties/{ind_prop['id']}", headers={"Authorization": f"Bearer {mgr_token}"})
    assert ind_resp.status_code == 403
    assert ind_resp.json()["error"]["code"] == "PERMISSION_DENIED"

    # 4. Manager blocked from viewing audit logs
    audit_resp = client.get("/api/v1/audit-logs", headers={"Authorization": f"Bearer {mgr_token}"})
    assert audit_resp.status_code == 403

    # 5. Manager blocked from creating properties
    create_resp = client.post(
        "/api/v1/properties",
        headers={"Authorization": f"Bearer {mgr_token}"},
        json={"name": "Illegal PG", "code": "ILLEGAL", "property_type": "CO_LIVING", "address_line1": "x", "city": "Bangalore", "state": "Karnataka", "pincode": "560001"},
    )
    assert create_resp.status_code == 403


def test_staff_scoped_access(client):
    """Staff is restricted to assigned property (OG-KOR) and cannot view users or audits."""
    admin_token = get_token(client, "admin")
    all_props = client.get(
        "/api/v1/properties", headers={"Authorization": f"Bearer {admin_token}"}
    ).json()["data"]
    kor_prop = next(p for p in all_props if p["code"] == "OG-KOR")
    ind_prop = next(p for p in all_props if p["code"] == "OG-IND")

    staff_token = get_token(client, "staff")

    # 1. Staff sees only 1 property
    list_resp = client.get("/api/v1/properties", headers={"Authorization": f"Bearer {staff_token}"})
    assert list_resp.status_code == 200
    assert len(list_resp.json()["data"]) == 1
    assert list_resp.json()["data"][0]["code"] == "OG-KOR"

    # 2. Staff can view assigned property details
    kor_resp = client.get(f"/api/v1/properties/{kor_prop['id']}", headers={"Authorization": f"Bearer {staff_token}"})
    assert kor_resp.status_code == 200

    # 3. Staff blocked from unassigned property
    ind_resp = client.get(f"/api/v1/properties/{ind_prop['id']}", headers={"Authorization": f"Bearer {staff_token}"})
    assert ind_resp.status_code == 403

    # 4. Staff blocked from users list
    users_resp = client.get("/api/v1/users", headers={"Authorization": f"Bearer {staff_token}"})
    assert users_resp.status_code == 403

    # 5. Staff blocked from audit logs
    audit_resp = client.get("/api/v1/audit-logs", headers={"Authorization": f"Bearer {staff_token}"})
    assert audit_resp.status_code == 403


def test_resident_isolation_and_privacy(client):
    """Resident cannot access company users, audit logs, or other residents' records."""
    resident_token = get_token(client, "resident")

    # 1. Resident sees only assigned property
    props_resp = client.get("/api/v1/properties", headers={"Authorization": f"Bearer {resident_token}"})
    assert props_resp.status_code == 200
    assert len(props_resp.json()["data"]) == 1
    assert props_resp.json()["data"][0]["code"] == "OG-KOR"

    # 2. Resident blocked from users directory
    users_resp = client.get("/api/v1/users", headers={"Authorization": f"Bearer {resident_token}"})
    assert users_resp.status_code == 403
    assert users_resp.json()["error"]["code"] == "PERMISSION_DENIED"

    # 3. Resident blocked from accessing another user's detail by ID
    random_user_id = uuid.uuid4()
    detail_resp = client.get(f"/api/v1/users/{random_user_id}", headers={"Authorization": f"Bearer {resident_token}"})
    assert detail_resp.status_code == 403
    assert detail_resp.json()["error"]["code"] == "PERMISSION_DENIED"

    # 4. Resident blocked from audit logs
    audit_resp = client.get("/api/v1/audit-logs", headers={"Authorization": f"Bearer {resident_token}"})
    assert audit_resp.status_code == 403

    # 5. Resident blocked from creating properties
    create_resp = client.post(
        "/api/v1/properties",
        headers={"Authorization": f"Bearer {resident_token}"},
        json={"name": "Resident PG", "code": "RES-PG", "property_type": "CO_LIVING", "address_line1": "x", "city": "Bangalore", "state": "Karnataka", "pincode": "560001"},
    )
    assert create_resp.status_code == 403


def test_super_admin_create_property_on_postgres(client):
    """Super Admin can create a new property against PostgreSQL within test transaction."""
    admin_token = get_token(client, "admin")
    payload = {
        "name": "Origin Suites PG - Whitefield",
        "code": "OG-WTF",
        "property_type": "CO_LIVING",
        "address_line1": "10, ITPL Main Road",
        "city": "Bangalore",
        "state": "Karnataka",
        "pincode": "560066",
        "contact_phone": "+919876543299",
        "total_floors": 5,
        "is_active": True,
        "settings": {},
    }
    resp = client.post(
        "/api/v1/properties",
        headers={"Authorization": f"Bearer {admin_token}"},
        json=payload,
    )
    assert resp.status_code == 201
    data = resp.json()["data"]
    assert data["code"] == "OG-WTF"
    assert data["name"] == "Origin Suites PG - Whitefield"
