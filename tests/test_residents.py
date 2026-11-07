import uuid
from tests.test_roles_and_scopes import get_token


def _setup_kor_hsr_ids(client, admin_token):
    props = client.get("/api/v1/properties", headers={"Authorization": f"Bearer {admin_token}"}).json()["data"]
    kor_id = next(p["id"] for p in props if p["code"] == "OG-KOR")
    hsr_id = next(p["id"] for p in props if p["code"] == "OG-HSR")
    ind_id = next(p["id"] for p in props if p["code"] == "OG-IND")
    return kor_id, hsr_id, ind_id


def test_super_admin_create_resident_admission_pending(client):
    admin_token = get_token(client, "admin@originpg.com", "Admin@123456")
    kor_id, _, _ = _setup_kor_hsr_ids(client, admin_token)

    payload = {
        "property_id": kor_id,
        "full_name": "Aarav Patel",
        "phone": "9123456789",
        "email": "aarav.patel@example.com",
        "emergency_contact_name": "Vikram Patel",
        "emergency_contact_phone": "9123456780",
        "monthly_rent": 10500.0,
        "security_deposit": 21000.0,
        "id_proof_type": "AADHAAR",
        "id_proof_number": "1234 5678 9012",
        "kyc_notes": "Physical verification pending",
    }
    resp = client.post(
        "/api/v1/residents",
        headers={"Authorization": f"Bearer {admin_token}"},
        json=payload,
    )
    assert resp.status_code == 201
    res_data = resp.json()["data"]
    assert res_data["full_name"] == "Aarav Patel"
    assert res_data["status"] == "PENDING"
    assert res_data["kyc_status"] == "PENDING"
    assert res_data["id_proof_number_masked"] == "XXXX-XXXX-9012"
    assert "1234 5678 9012" not in str(resp.json())


def test_resident_admission_field_validation_and_duplicate_phone(client):
    admin_token = get_token(client, "admin@originpg.com", "Admin@123456")
    kor_id, _, _ = _setup_kor_hsr_ids(client, admin_token)

    # 1. Validation error on missing phone and full_name
    bad_payload = {"property_id": kor_id}
    bad_resp = client.post(
        "/api/v1/residents",
        headers={"Authorization": f"Bearer {admin_token}"},
        json=bad_payload,
    )
    assert bad_resp.status_code == 422

    # 2. First admission succeeds
    valid_payload = {
        "property_id": kor_id,
        "full_name": "Priya Sharma",
        "phone": "9811223344",
        "email": "priya.sharma@example.com",
    }
    resp1 = client.post(
        "/api/v1/residents",
        headers={"Authorization": f"Bearer {admin_token}"},
        json=valid_payload,
    )
    assert resp1.status_code == 201

    # 3. Duplicate phone in same property returns 409 CONFLICT
    resp2 = client.post(
        "/api/v1/residents",
        headers={"Authorization": f"Bearer {admin_token}"},
        json=valid_payload,
    )
    assert resp2.status_code == 409
    assert resp2.json()["error"]["code"] == "CONFLICT"


def test_check_in_resident_assigns_available_bed(client):
    admin_token = get_token(client, "admin@originpg.com", "Admin@123456")
    kor_id, _, _ = _setup_kor_hsr_ids(client, admin_token)

    # Create room and bed
    room_resp = client.post(
        f"/api/v1/properties/{kor_id}/rooms",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"room_number": "R-101", "floor_number": 1, "room_type": "SINGLE", "base_monthly_rent": 15000.0},
    )
    room_id = room_resp.json()["data"]["id"]

    bed_resp = client.post(
        f"/api/v1/rooms/{room_id}/beds",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"bed_number": "B-1", "monthly_rent": 15000.0, "status": "AVAILABLE"},
    )
    bed_id = bed_resp.json()["data"]["id"]

    # Admit resident (PENDING)
    res_resp = client.post(
        "/api/v1/residents",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"property_id": kor_id, "full_name": "Kiran Kumar", "phone": "9988776655"},
    )
    assert res_resp.status_code == 201
    resident_id = res_resp.json()["data"]["id"]
    assert res_resp.json()["data"]["status"] == "PENDING"

    # Check in resident
    checkin_resp = client.post(
        f"/api/v1/residents/{resident_id}/check-in",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"bed_id": bed_id},
    )
    assert checkin_resp.status_code == 200
    checked_in = checkin_resp.json()["data"]
    assert checked_in["status"] == "ACTIVE"
    assert checked_in["bed_id"] == bed_id
    assert checked_in["bed_number"] == "B-1"
    assert checked_in["room_number"] == "R-101"

    # Verify bed status is now OCCUPIED
    bed_status = client.get(f"/api/v1/beds/{bed_id}", headers={"Authorization": f"Bearer {admin_token}"}).json()["data"]
    assert bed_status["status"] == "OCCUPIED"

    # Verify occupancy endpoint
    occ_resp = client.get(
        f"/api/v1/residents/{resident_id}/occupancy",
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert occ_resp.status_code == 200
    occ_data = occ_resp.json()["data"]
    assert occ_data["status"] == "ACTIVE"
    assert occ_data["bed_number"] == "B-1"
    assert occ_data["room_number"] == "R-101"


def test_check_in_rejects_occupied_reserved_maintenance_bed(client):
    admin_token = get_token(client, "admin@originpg.com", "Admin@123456")
    kor_id, _, _ = _setup_kor_hsr_ids(client, admin_token)

    # Create room & beds
    room_resp = client.post(
        f"/api/v1/properties/{kor_id}/rooms",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"room_number": "R-102", "floor_number": 1, "room_type": "DOUBLE", "base_monthly_rent": 9000.0},
    )
    room_id = room_resp.json()["data"]["id"]

    bed1_id = client.post(
        f"/api/v1/rooms/{room_id}/beds",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"bed_number": "B-102A", "monthly_rent": 9000.0, "status": "AVAILABLE"},
    ).json()["data"]["id"]

    bed2_id = client.post(
        f"/api/v1/rooms/{room_id}/beds",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"bed_number": "B-102B", "monthly_rent": 9000.0, "status": "MAINTENANCE"},
    ).json()["data"]["id"]

    # Admit 2 residents
    res1_id = client.post(
        "/api/v1/residents",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"property_id": kor_id, "full_name": "Resident One", "phone": "9000000001"},
    ).json()["data"]["id"]

    res2_id = client.post(
        "/api/v1/residents",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"property_id": kor_id, "full_name": "Resident Two", "phone": "9000000002"},
    ).json()["data"]["id"]

    # Res1 checks into bed1 -> SUCCESS
    c1 = client.post(
        f"/api/v1/residents/{res1_id}/check-in",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"bed_id": bed1_id},
    )
    assert c1.status_code == 200

    # Res2 attempts to check into already OCCUPIED bed1 -> 409 CONFLICT
    c2 = client.post(
        f"/api/v1/residents/{res2_id}/check-in",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"bed_id": bed1_id},
    )
    assert c2.status_code == 409
    assert c2.json()["error"]["code"] == "CONFLICT"

    # Res2 attempts to check into MAINTENANCE bed2 -> 409 CONFLICT
    c3 = client.post(
        f"/api/v1/residents/{res2_id}/check-in",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"bed_id": bed2_id},
    )
    assert c3.status_code == 409
    assert c3.json()["error"]["code"] == "CONFLICT"


def test_resident_bed_property_mismatch_rejected(client):
    admin_token = get_token(client, "admin@originpg.com", "Admin@123456")
    kor_id, hsr_id, _ = _setup_kor_hsr_ids(client, admin_token)

    # Bed in HSR Layout
    hsr_room_id = client.post(
        f"/api/v1/properties/{hsr_id}/rooms",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"room_number": "HSR-101", "floor_number": 1, "room_type": "SINGLE"},
    ).json()["data"]["id"]

    hsr_bed_id = client.post(
        f"/api/v1/rooms/{hsr_room_id}/beds",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"bed_number": "HSR-B1", "monthly_rent": 12000.0, "status": "AVAILABLE"},
    ).json()["data"]["id"]

    # Resident admitted to Koramangala
    kor_res_id = client.post(
        "/api/v1/residents",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"property_id": kor_id, "full_name": "Cross Property Resident", "phone": "9111222333"},
    ).json()["data"]["id"]

    # Attempt cross-property check-in
    cross_resp = client.post(
        f"/api/v1/residents/{kor_res_id}/check-in",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"bed_id": hsr_bed_id},
    )
    assert cross_resp.status_code == 409
    assert "mismatch" in cross_resp.json()["error"]["message"].lower()


def test_successful_checkout_and_bed_release(client):
    admin_token = get_token(client, "admin@originpg.com", "Admin@123456")
    kor_id, _, _ = _setup_kor_hsr_ids(client, admin_token)

    # Room and Bed
    room_id = client.post(
        f"/api/v1/properties/{kor_id}/rooms",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"room_number": "R-103", "floor_number": 1, "room_type": "SINGLE"},
    ).json()["data"]["id"]
    bed_id = client.post(
        f"/api/v1/rooms/{room_id}/beds",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"bed_number": "B-103", "monthly_rent": 10000.0, "status": "AVAILABLE"},
    ).json()["data"]["id"]

    # Admit and check-in
    res_id = client.post(
        "/api/v1/residents",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"property_id": kor_id, "full_name": "Checkout Tester", "phone": "9777888999"},
    ).json()["data"]["id"]

    client.post(
        f"/api/v1/residents/{res_id}/check-in",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"bed_id": bed_id},
    )

    # Verify bed is occupied
    assert client.get(f"/api/v1/beds/{bed_id}", headers={"Authorization": f"Bearer {admin_token}"}).json()["data"]["status"] == "OCCUPIED"

    # Execute checkout
    checkout_resp = client.post(
        f"/api/v1/residents/{res_id}/check-out",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"notes": "Relocating for job"},
    )
    assert checkout_resp.status_code == 200
    res_data = checkout_resp.json()["data"]
    assert res_data["status"] == "CHECKED_OUT"
    assert res_data["actual_check_out_date"] is not None

    # Verify bed is released to AVAILABLE
    assert client.get(f"/api/v1/beds/{bed_id}", headers={"Authorization": f"Bearer {admin_token}"}).json()["data"]["status"] == "AVAILABLE"


def test_checkout_only_allowed_for_active_resident(client):
    admin_token = get_token(client, "admin@originpg.com", "Admin@123456")
    kor_id, _, _ = _setup_kor_hsr_ids(client, admin_token)

    # Pending resident
    pending_id = client.post(
        "/api/v1/residents",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"property_id": kor_id, "full_name": "Pending Resident", "phone": "9666555444"},
    ).json()["data"]["id"]

    resp = client.post(
        f"/api/v1/residents/{pending_id}/check-out",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={},
    )
    assert resp.status_code == 409
    assert resp.json()["error"]["code"] == "CONFLICT"


def test_property_manager_scoping_for_residents(client):
    manager_token = get_token(client, "manager@originpg.com", "Manager@123456")
    admin_token = get_token(client, "admin@originpg.com", "Admin@123456")
    kor_id, hsr_id, ind_id = _setup_kor_hsr_ids(client, admin_token)

    # Manager CAN admit resident in assigned OG-KOR
    kor_res = client.post(
        "/api/v1/residents",
        headers={"Authorization": f"Bearer {manager_token}"},
        json={"property_id": kor_id, "full_name": "Manager Kor Resident", "phone": "9555444333"},
    )
    assert kor_res.status_code == 201

    # Manager CANNOT admit resident in unassigned OG-IND -> 403 Forbidden
    ind_res = client.post(
        "/api/v1/residents",
        headers={"Authorization": f"Bearer {manager_token}"},
        json={"property_id": ind_id, "full_name": "Manager Ind Resident", "phone": "9444333222"},
    )
    assert ind_res.status_code == 403
    assert ind_res.json()["error"]["code"] == "PERMISSION_DENIED"


def test_staff_resident_permissions(client):
    staff_token = get_token(client, "staff@originpg.com", "Staff@123456", client_type="admin_mobile")
    admin_token = get_token(client, "admin@originpg.com", "Admin@123456")
    kor_id, _, ind_id = _setup_kor_hsr_ids(client, admin_token)

    # Staff CAN view residents in assigned OG-KOR
    list_resp = client.get(
        f"/api/v1/residents?property_id={kor_id}",
        headers={"Authorization": f"Bearer {staff_token}"},
    )
    assert list_resp.status_code == 200

    # Staff CANNOT view residents in unassigned OG-IND -> 403 Forbidden
    unassigned_resp = client.get(
        f"/api/v1/residents?property_id={ind_id}",
        headers={"Authorization": f"Bearer {staff_token}"},
    )
    assert unassigned_resp.status_code == 403

    # Staff CANNOT create resident admissions -> 403 Forbidden
    create_resp = client.post(
        "/api/v1/residents",
        headers={"Authorization": f"Bearer {staff_token}"},
        json={"property_id": kor_id, "full_name": "Staff Admission Attempt", "phone": "9333222111"},
    )
    assert create_resp.status_code == 403


def test_resident_role_restrictions(client):
    resident_token = get_token(client, "resident@originpg.com", "Resident@123456", client_type="resident_mobile")
    admin_token = get_token(client, "admin@originpg.com", "Admin@123456")
    kor_id, _, _ = _setup_kor_hsr_ids(client, admin_token)

    # 1. Resident cannot list all residents -> 403 Forbidden
    assert client.get("/api/v1/residents", headers={"Authorization": f"Bearer {resident_token}"}).status_code == 403

    # 2. Resident cannot admit another resident -> 403 Forbidden
    assert client.post(
        "/api/v1/residents",
        headers={"Authorization": f"Bearer {resident_token}"},
        json={"property_id": kor_id, "full_name": "Hacker Resident", "phone": "9222111000"},
    ).status_code == 403

    # 3. Create a resident for the seeded resident user (phone: 9876543213)
    admin_res = client.post(
        "/api/v1/residents",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"property_id": kor_id, "full_name": "Rohan Deshmukh", "phone": "9876543213"},
    ).json()["data"]

    # 4. Resident can access /me profile
    me_resp = client.get("/api/v1/residents/me", headers={"Authorization": f"Bearer {resident_token}"})
    assert me_resp.status_code == 200
    assert me_resp.json()["data"]["phone"] == "9876543213"

    # 5. Resident can access /me/occupancy
    me_occ = client.get("/api/v1/residents/me/occupancy", headers={"Authorization": f"Bearer {resident_token}"})
    assert me_occ.status_code == 200

    # 6. Resident cannot access another resident's ID -> 403 Forbidden
    other_res = client.post(
        "/api/v1/residents",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"property_id": kor_id, "full_name": "Other Guy", "phone": "9111000999"},
    ).json()["data"]

    forbidden_resp = client.get(
        f"/api/v1/residents/{other_res['id']}",
        headers={"Authorization": f"Bearer {resident_token}"},
    )
    assert forbidden_resp.status_code == 403


def test_kyc_verification_flow_and_sensitive_redaction(client):
    admin_token = get_token(client, "admin@originpg.com", "Admin@123456")
    kor_id, _, _ = _setup_kor_hsr_ids(client, admin_token)

    # 1. Admit resident
    res_id = client.post(
        "/api/v1/residents",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"property_id": kor_id, "full_name": "KYC Subject", "phone": "9000111222"},
    ).json()["data"]["id"]

    # 2. Staff updates KYC verification
    staff_token = get_token(client, "staff@originpg.com", "Staff@123456", client_type="admin_mobile")
    kyc_resp = client.patch(
        f"/api/v1/residents/{res_id}/kyc",
        headers={"Authorization": f"Bearer {staff_token}"},
        json={
            "kyc_status": "VERIFIED",
            "id_proof_type": "PAN",
            "id_proof_number": "ABCDE1234F",
            "kyc_notes": "Verified original PAN card",
        },
    )
    assert kyc_resp.status_code == 200
    kyc_data = kyc_resp.json()["data"]
    assert kyc_data["kyc_status"] == "VERIFIED"
    assert kyc_data["id_proof_type"] == "PAN"
    assert kyc_data["id_proof_number_masked"] == "XXXXXX234F"
    assert kyc_data["verified_at"] is not None
    # Verify unmasked plaintext is NEVER in response
    assert "ABCDE1234F" not in str(kyc_resp.json())


def test_audit_logs_recorded_for_resident_lifecycle(client):
    admin_token = get_token(client, "admin@originpg.com", "Admin@123456")
    kor_id, _, _ = _setup_kor_hsr_ids(client, admin_token)

    # 1. Setup room & bed
    room_id = client.post(
        f"/api/v1/properties/{kor_id}/rooms",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"room_number": "R-AUD", "floor_number": 1, "room_type": "SINGLE"},
    ).json()["data"]["id"]
    bed_id = client.post(
        f"/api/v1/rooms/{room_id}/beds",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"bed_number": "B-AUD", "monthly_rent": 11000.0, "status": "AVAILABLE"},
    ).json()["data"]["id"]

    # 2. Admit
    res_id = client.post(
        "/api/v1/residents",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"property_id": kor_id, "full_name": "Audit Resident", "phone": "9898989898"},
    ).json()["data"]["id"]

    # 3. Check in
    client.post(
        f"/api/v1/residents/{res_id}/check-in",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"bed_id": bed_id},
    )

    # 4. KYC
    client.patch(
        f"/api/v1/residents/{res_id}/kyc",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"kyc_status": "VERIFIED", "id_proof_type": "PASSPORT", "id_proof_number": "Z1234567"},
    )

    # 5. Check out
    client.post(
        f"/api/v1/residents/{res_id}/check-out",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={},
    )

    # 6. Verify audit logs
    audit_resp = client.get("/api/v1/audit-logs", headers={"Authorization": f"Bearer {admin_token}"})
    assert audit_resp.status_code == 200
    items = audit_resp.json()["data"]["items"]
    actions = [log["action"] for log in items]
    assert "RESIDENT_ADMITTED" in actions
    assert "RESIDENT_CHECKED_IN" in actions
    assert "RESIDENT_KYC_UPDATED" in actions
    assert "RESIDENT_CHECKED_OUT" in actions

    # Verify no raw sensitive data in audit logs
    audit_str = str(items)
    assert "Z1234567" not in audit_str
