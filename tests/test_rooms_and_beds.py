import uuid
from tests.test_roles_and_scopes import get_token


def test_super_admin_create_and_list_rooms(client):
    admin_token = get_token(client, "admin@originpg.com", "Admin@123456")

    # 1. Get Koramangala property ID
    props = client.get("/api/v1/properties", headers={"Authorization": f"Bearer {admin_token}"}).json()["data"]
    kor_prop = next(p for p in props if p["code"] == "OG-KOR")
    kor_id = kor_prop["id"]

    # 2. Create Room 101 in OG-KOR
    room_payload = {
        "room_number": "101",
        "floor_number": 1,
        "room_type": "DOUBLE",
        "base_monthly_rent": 12000.0,
        "deposit_amount": 24000.0,
        "amenities": ["AC", "ATTACHED_BATHROOM", "WIFI"],
        "is_active": True,
    }
    resp = client.post(
        f"/api/v1/properties/{kor_id}/rooms",
        headers={"Authorization": f"Bearer {admin_token}"},
        json=room_payload,
    )
    assert resp.status_code == 201
    room = resp.json()["data"]
    assert room["room_number"] == "101"
    assert room["property_id"] == kor_id
    assert room["total_beds"] == 0

    # 3. List rooms in OG-KOR
    list_resp = client.get(
        f"/api/v1/properties/{kor_id}/rooms",
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert list_resp.status_code == 200
    rooms = list_resp.json()["data"]
    assert any(r["room_number"] == "101" for r in rooms)


def test_duplicate_room_number_same_property_rejected(client):
    admin_token = get_token(client, "admin@originpg.com", "Admin@123456")
    props = client.get("/api/v1/properties", headers={"Authorization": f"Bearer {admin_token}"}).json()["data"]
    kor_id = next(p["id"] for p in props if p["code"] == "OG-KOR")

    payload = {
        "room_number": "102",
        "floor_number": 1,
        "room_type": "SINGLE",
        "base_monthly_rent": 15000.0,
    }
    # First creation succeeds
    resp1 = client.post(
        f"/api/v1/properties/{kor_id}/rooms",
        headers={"Authorization": f"Bearer {admin_token}"},
        json=payload,
    )
    assert resp1.status_code == 201

    # Second creation with identical room number in same property fails
    resp2 = client.post(
        f"/api/v1/properties/{kor_id}/rooms",
        headers={"Authorization": f"Bearer {admin_token}"},
        json=payload,
    )
    assert resp2.status_code == 409
    assert resp2.json()["error"]["code"] == "CONFLICT"


def test_same_room_number_different_property_allowed(client):
    admin_token = get_token(client, "admin@originpg.com", "Admin@123456")
    props = client.get("/api/v1/properties", headers={"Authorization": f"Bearer {admin_token}"}).json()["data"]
    kor_id = next(p["id"] for p in props if p["code"] == "OG-KOR")
    hsr_id = next(p["id"] for p in props if p["code"] == "OG-HSR")

    payload = {
        "room_number": "201",
        "floor_number": 2,
        "room_type": "DOUBLE",
        "base_monthly_rent": 10000.0,
    }
    # Create in Koramangala
    resp1 = client.post(
        f"/api/v1/properties/{kor_id}/rooms",
        headers={"Authorization": f"Bearer {admin_token}"},
        json=payload,
    )
    assert resp1.status_code == 201

    # Create same room number in HSR Layout - must succeed
    resp2 = client.post(
        f"/api/v1/properties/{hsr_id}/rooms",
        headers={"Authorization": f"Bearer {admin_token}"},
        json=payload,
    )
    assert resp2.status_code == 201
    assert resp2.json()["data"]["room_number"] == "201"
    assert resp2.json()["data"]["property_id"] == hsr_id


def test_bed_creation_and_duplicate_rejection(client):
    admin_token = get_token(client, "admin@originpg.com", "Admin@123456")
    props = client.get("/api/v1/properties", headers={"Authorization": f"Bearer {admin_token}"}).json()["data"]
    kor_id = next(p["id"] for p in props if p["code"] == "OG-KOR")

    # Create Room 301
    room_resp = client.post(
        f"/api/v1/properties/{kor_id}/rooms",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"room_number": "301", "floor_number": 3, "room_type": "DOUBLE", "base_monthly_rent": 8000.0},
    )
    assert room_resp.status_code == 201
    room_id = room_resp.json()["data"]["id"]

    # 1. Add Bed A
    bed_a_resp = client.post(
        f"/api/v1/rooms/{room_id}/beds",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"bed_number": "A", "monthly_rent": 8000.0, "status": "AVAILABLE"},
    )
    assert bed_a_resp.status_code == 201
    assert bed_a_resp.json()["data"]["bed_number"] == "A"
    assert bed_a_resp.json()["data"]["status"] == "AVAILABLE"

    # 2. Add Bed B
    bed_b_resp = client.post(
        f"/api/v1/rooms/{room_id}/beds",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"bed_number": "B", "monthly_rent": 8500.0, "status": "AVAILABLE"},
    )
    assert bed_b_resp.status_code == 201

    # 3. Add duplicate Bed A to same room -> 409 Conflict
    dup_resp = client.post(
        f"/api/v1/rooms/{room_id}/beds",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"bed_number": "A", "monthly_rent": 8000.0, "status": "AVAILABLE"},
    )
    assert dup_resp.status_code == 409
    assert dup_resp.json()["error"]["code"] == "CONFLICT"


def test_property_manager_scoping_for_rooms(client):
    mgr_token = get_token(client, "manager@originpg.com", "Manager@123456")
    admin_token = get_token(client, "admin@originpg.com", "Admin@123456")

    props = client.get("/api/v1/properties", headers={"Authorization": f"Bearer {admin_token}"}).json()["data"]
    kor_id = next(p["id"] for p in props if p["code"] == "OG-KOR")
    ind_id = next(p["id"] for p in props if p["code"] == "OG-IND")

    # Manager CAN create room in assigned OG-KOR
    resp_kor = client.post(
        f"/api/v1/properties/{kor_id}/rooms",
        headers={"Authorization": f"Bearer {mgr_token}"},
        json={"room_number": "M-101", "floor_number": 1, "room_type": "SINGLE", "base_monthly_rent": 9000.0},
    )
    assert resp_kor.status_code == 201

    # Manager BLOCKED from creating room in unassigned OG-IND
    resp_ind = client.post(
        f"/api/v1/properties/{ind_id}/rooms",
        headers={"Authorization": f"Bearer {mgr_token}"},
        json={"room_number": "M-101", "floor_number": 1, "room_type": "SINGLE", "base_monthly_rent": 9000.0},
    )
    assert resp_ind.status_code == 403
    assert resp_ind.json()["error"]["code"] == "PERMISSION_DENIED"

    # Manager BLOCKED from listing rooms in unassigned OG-IND
    resp_list_ind = client.get(
        f"/api/v1/properties/{ind_id}/rooms",
        headers={"Authorization": f"Bearer {mgr_token}"},
    )
    assert resp_list_ind.status_code == 403


def test_staff_room_and_bed_permissions(client):
    staff_token = get_token(client, "staff@originpg.com", "Staff@123456", client_type="admin_mobile")
    admin_token = get_token(client, "admin@originpg.com", "Admin@123456")

    props = client.get("/api/v1/properties", headers={"Authorization": f"Bearer {admin_token}"}).json()["data"]
    kor_id = next(p["id"] for p in props if p["code"] == "OG-KOR")
    ind_id = next(p["id"] for p in props if p["code"] == "OG-IND")

    # 1. Staff CAN view rooms in assigned property
    staff_rooms = client.get(
        f"/api/v1/properties/{kor_id}/rooms",
        headers={"Authorization": f"Bearer {staff_token}"},
    )
    assert staff_rooms.status_code == 200

    # 2. Staff BLOCKED from viewing rooms in unassigned property
    staff_unassigned = client.get(
        f"/api/v1/properties/{ind_id}/rooms",
        headers={"Authorization": f"Bearer {staff_token}"},
    )
    assert staff_unassigned.status_code == 403

    # 3. Staff BLOCKED from creating rooms
    create_room_resp = client.post(
        f"/api/v1/properties/{kor_id}/rooms",
        headers={"Authorization": f"Bearer {staff_token}"},
        json={"room_number": "STAFF-01", "floor_number": 1, "room_type": "SINGLE", "base_monthly_rent": 5000.0},
    )
    assert create_room_resp.status_code == 403


def test_bed_status_transitions(client):
    admin_token = get_token(client, "admin@originpg.com", "Admin@123456")
    staff_token = get_token(client, "staff@originpg.com", "Staff@123456", client_type="admin_mobile")

    props = client.get("/api/v1/properties", headers={"Authorization": f"Bearer {admin_token}"}).json()["data"]
    kor_id = next(p["id"] for p in props if p["code"] == "OG-KOR")

    # Setup room and bed
    r = client.post(
        f"/api/v1/properties/{kor_id}/rooms",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"room_number": "401", "floor_number": 4, "room_type": "SINGLE", "base_monthly_rent": 10000.0},
    ).json()["data"]

    b = client.post(
        f"/api/v1/rooms/{r['id']}/beds",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"bed_number": "1", "monthly_rent": 10000.0, "status": "AVAILABLE"},
    ).json()["data"]
    bed_id = b["id"]

    # 1. Staff updates status AVAILABLE -> MAINTENANCE
    patch_resp1 = client.patch(
        f"/api/v1/beds/{bed_id}/status",
        headers={"Authorization": f"Bearer {staff_token}"},
        json={"status": "MAINTENANCE"},
    )
    assert patch_resp1.status_code == 200
    assert patch_resp1.json()["data"]["status"] == "MAINTENANCE"

    # 2. Staff updates status MAINTENANCE -> AVAILABLE
    patch_resp2 = client.patch(
        f"/api/v1/beds/{bed_id}/status",
        headers={"Authorization": f"Bearer {staff_token}"},
        json={"status": "AVAILABLE"},
    )
    assert patch_resp2.status_code == 200
    assert patch_resp2.json()["data"]["status"] == "AVAILABLE"

    # 3. Invalid status value rejected
    patch_invalid = client.patch(
        f"/api/v1/beds/{bed_id}/status",
        headers={"Authorization": f"Bearer {staff_token}"},
        json={"status": "BROKEN"},
    )
    assert patch_invalid.status_code == 422


def test_resident_blocked_from_rooms_and_beds(client):
    resident_token = get_token(client, "resident@originpg.com", "Resident@123456", client_type="resident_mobile")

    # Resident blocked from listing rooms
    resp1 = client.get("/api/v1/rooms", headers={"Authorization": f"Bearer {resident_token}"})
    assert resp1.status_code == 403
    assert resp1.json()["error"]["code"] == "PERMISSION_DENIED"

    # Resident blocked from listing beds
    resp2 = client.get("/api/v1/beds", headers={"Authorization": f"Bearer {resident_token}"})
    assert resp2.status_code == 403
    assert resp2.json()["error"]["code"] == "PERMISSION_DENIED"


def test_manager_blocked_from_unassigned_room_beds(client):
    admin_token = get_token(client, "admin@originpg.com", "Admin@123456")
    mgr_token = get_token(client, "manager@originpg.com", "Manager@123456")

    # Create room in OG-IND (unassigned to manager)
    props = client.get("/api/v1/properties", headers={"Authorization": f"Bearer {admin_token}"}).json()["data"]
    ind_id = next(p["id"] for p in props if p["code"] == "OG-IND")

    r = client.post(
        f"/api/v1/properties/{ind_id}/rooms",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"room_number": "IND-101", "floor_number": 1, "room_type": "SINGLE", "base_monthly_rent": 14000.0},
    ).json()["data"]

    # Manager calling /rooms/{room_id}/beds on unassigned room must be denied
    resp = client.get(
        f"/api/v1/rooms/{r['id']}/beds",
        headers={"Authorization": f"Bearer {mgr_token}"},
    )
    assert resp.status_code == 403
    assert resp.json()["error"]["code"] == "PERMISSION_DENIED"


def test_nonexistent_room_returns_404(client):
    admin_token = get_token(client, "admin@originpg.com", "Admin@123456")
    random_id = uuid.uuid4()
    resp = client.get(
        f"/api/v1/rooms/{random_id}/beds",
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert resp.status_code == 404
    assert resp.json()["error"]["code"] == "NOT_FOUND"


def test_occupied_bed_cannot_manually_be_made_available(client):
    admin_token = get_token(client, "admin@originpg.com", "Admin@123456")
    props = client.get("/api/v1/properties", headers={"Authorization": f"Bearer {admin_token}"}).json()["data"]
    kor_id = next(p["id"] for p in props if p["code"] == "OG-KOR")

    # Create room and bed with status OCCUPIED
    r = client.post(
        f"/api/v1/properties/{kor_id}/rooms",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"room_number": "OCC-101", "floor_number": 1, "room_type": "SINGLE", "base_monthly_rent": 10000.0},
    ).json()["data"]

    b = client.post(
        f"/api/v1/rooms/{r['id']}/beds",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"bed_number": "1", "monthly_rent": 10000.0, "status": "OCCUPIED"},
    ).json()["data"]

    # Attempting to manually reset OCCUPIED bed to AVAILABLE must be rejected
    resp = client.patch(
        f"/api/v1/beds/{b['id']}/status",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"status": "AVAILABLE"},
    )
    assert resp.status_code == 422
    assert "occupied bed cannot be manually marked available" in resp.json()["error"]["message"]
