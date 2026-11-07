import uuid


def get_token(client, email, password, client_type="admin_web"):
    resp = client.post(
        "/api/v1/auth/login",
        json={"identifier": email, "password": password, "client_type": client_type},
    )
    return resp.json()["data"]["access_token"]


def test_property_scoping_super_admin(client):
    token = get_token(client, "admin@originpg.com", "Admin@123456")
    resp = client.get("/api/v1/properties", headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 200
    props = resp.json()["data"]
    # Super Admin sees all 5 properties
    assert len(props) == 5


def test_property_scoping_manager(client):
    token = get_token(client, "manager@originpg.com", "Manager@123456")
    resp = client.get("/api/v1/properties", headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 200
    props = resp.json()["data"]
    # Manager sees only their 2 assigned properties
    assert len(props) == 2
    codes = {p["code"] for p in props}
    assert codes == {"OG-KOR", "OG-HSR"}


def test_property_scoping_staff(client):
    token = get_token(client, "staff@originpg.com", "Staff@123456", "admin_mobile")
    resp = client.get("/api/v1/properties", headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 200
    props = resp.json()["data"]
    # Staff sees only their 1 assigned property
    assert len(props) == 1
    assert props[0]["code"] == "OG-KOR"


def test_manager_cannot_access_unassigned_property(client):
    # 1. Get an unassigned property ID (e.g., OG-IND Indiranagar) using Super Admin
    admin_token = get_token(client, "admin@originpg.com", "Admin@123456")
    all_props = client.get(
        "/api/v1/properties", headers={"Authorization": f"Bearer {admin_token}"}
    ).json()["data"]
    unassigned_prop = next(p for p in all_props if p["code"] == "OG-IND")
    unassigned_id = unassigned_prop["id"]

    # 2. Attempt to view it as Property Manager (who only has OG-KOR and OG-HSR)
    mgr_token = get_token(client, "manager@originpg.com", "Manager@123456")
    resp = client.get(
        f"/api/v1/properties/{unassigned_id}",
        headers={"Authorization": f"Bearer {mgr_token}"},
    )
    assert resp.status_code == 403
    assert resp.json()["error"]["code"] == "PERMISSION_DENIED"


def test_resident_cannot_access_user_list(client):
    resident_token = get_token(
        client, "resident@originpg.com", "Resident@123456", client_type="resident_mobile"
    )
    resp = client.get(
        "/api/v1/users",
        headers={"Authorization": f"Bearer {resident_token}"},
    )
    assert resp.status_code == 403
    assert resp.json()["error"]["code"] == "PERMISSION_DENIED"


def test_super_admin_create_property(client):
    admin_token = get_token(client, "admin@originpg.com", "Admin@123456")
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


def test_manager_cannot_create_property(client):
    mgr_token = get_token(client, "manager@originpg.com", "Manager@123456")
    payload = {
        "name": "Unauthorized PG",
        "code": "OG-UNAUTH",
        "property_type": "CO_LIVING",
        "address_line1": "Street",
        "city": "Bangalore",
        "state": "Karnataka",
        "pincode": "560001",
        "total_floors": 2,
    }
    resp = client.post(
        "/api/v1/properties",
        headers={"Authorization": f"Bearer {mgr_token}"},
        json=payload,
    )
    assert resp.status_code == 403


def test_super_admin_create_and_assign_user(client):
    admin_token = get_token(client, "admin@originpg.com", "Admin@123456")
    # Get manager role ID
    me_resp = client.get(
        "/api/v1/auth/me", headers={"Authorization": f"Bearer {admin_token}"}
    )
    admin_profile = me_resp.json()["data"]
    company_id = admin_profile["company_id"]

    # Get roles from users list
    users_resp = client.get(
        "/api/v1/users", headers={"Authorization": f"Bearer {admin_token}"}
    )
    assert users_resp.status_code == 200

    # Get one property to assign
    props_resp = client.get(
        "/api/v1/properties", headers={"Authorization": f"Bearer {admin_token}"}
    )
    prop_id = props_resp.json()["data"][0]["id"]

    # Fetch a role ID by inspecting manager user
    mgr_user = client.get(
        "/api/v1/users",
        headers={"Authorization": f"Bearer {admin_token}"},
        params={"role_name": "STAFF"},
    ).json()["data"]["items"][0]
    staff_detail = client.get(
        f"/api/v1/users/{mgr_user['id']}",
        headers={"Authorization": f"Bearer {admin_token}"},
    ).json()["data"]
    staff_role_id = staff_detail["role"]["id"]

    new_user_payload = {
        "full_name": "Kavita Reddy (New Staff)",
        "email": "kavita.reddy@originpg.com",
        "phone": "9876543299",
        "password": "StaffPass@123",
        "role_id": staff_role_id,
        "property_ids": [prop_id],
    }
    create_resp = client.post(
        "/api/v1/users",
        headers={"Authorization": f"Bearer {admin_token}"},
        json=new_user_payload,
    )
    assert create_resp.status_code == 201
    created_user = create_resp.json()["data"]
    assert created_user["phone"] == "9876543299"
    assert len(created_user["allowed_properties"]) == 1
