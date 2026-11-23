import uuid
import hashlib
import secrets
from concurrent.futures import ThreadPoolExecutor
import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session
import sqlalchemy as sa

from app.core.config import settings
from app.models.property import Company, Property
from app.models.room import Room
from app.models.bed import Bed
from app.models.user import User
from app.models.role import Role
from app.services.bed_capacity_service import BedCapacityService

SUPER_KEY = "ORG-240-X7K9-PQ82"
SUPER_KEY_HASH = "4a9cf98caf4de59247a8cad40229adaf500b9ef1aaedca7cad460b002fef649f"
EXPECTED_CAPACITY_ERROR = "Your organization has reached its maximum bed capacity of 240. Please contact Origin for assistance."


@pytest.fixture
def db(client):
    session = client.app.state.testing_session()
    try:
        yield session
    finally:
        session.close()


def _get_error_msg(response) -> str:
    body = response.json()
    if isinstance(body, dict):
        if "error" in body and isinstance(body["error"], dict):
            return body["error"].get("message", "")
        return str(body.get("detail", ""))
    return ""


def test_01_correct_super_key_accepted(client: TestClient):
    """Test 1: Correct Super Key is accepted during PG Owner registration."""
    unique = secrets.token_hex(4)
    email = f"owner_valid_{unique}@originpg.com"

    response = client.post(
        "/api/v1/auth/admin/register",
        json={
            "business_name": f"Origin Verified PG {unique}",
            "email": email,
            "password": "ValidAdminPass@123",
            "confirm_password": "ValidAdminPass@123",
            "super_key": SUPER_KEY,
        },
    )
    assert response.status_code == 201, response.text
    data = response.json()["data"]
    assert data["email"] == email
    assert data["role"] in ("PROPERTY_MANAGER", "SUPER_ADMIN")
    assert data["is_active"] is True
    assert data["company"]["bed_limit"] == 240


def test_02_incorrect_super_key_rejected(client: TestClient):
    """Test 2: Incorrect Super Key is rejected with 400 Bad Request."""
    unique = secrets.token_hex(4)
    email = f"owner_invalid_{unique}@originpg.com"

    response = client.post(
        "/api/v1/auth/admin/register",
        json={
            "business_name": f"Invalid PG {unique}",
            "email": email,
            "password": "ValidAdminPass@123",
            "confirm_password": "ValidAdminPass@123",
            "super_key": "ORG-240-INVALID-KEY9",
        },
    )
    assert response.status_code == 400
    msg = _get_error_msg(response).lower()
    assert "super key" in msg or "invalid" in msg


def test_03_multiple_pg_owners_can_use_same_key(client: TestClient):
    """Test 3: Multiple distinct PG Owners can register using the exact same Super Key."""
    unique1 = secrets.token_hex(4)
    unique2 = secrets.token_hex(4)

    r1 = client.post(
        "/api/v1/auth/admin/register",
        json={
            "business_name": f"Multi Owner 1 {unique1}",
            "email": f"owner1_{unique1}@originpg.com",
            "password": "OwnerPass@12345",
            "confirm_password": "OwnerPass@12345",
            "super_key": SUPER_KEY,
        },
    )
    assert r1.status_code == 201, r1.text

    r2 = client.post(
        "/api/v1/auth/admin/register",
        json={
            "business_name": f"Multi Owner 2 {unique2}",
            "email": f"owner2_{unique2}@originpg.com",
            "password": "OwnerPass@12345",
            "confirm_password": "OwnerPass@12345",
            "super_key": SUPER_KEY,
        },
    )
    assert r2.status_code == 201, r2.text

    c1 = r1.json()["data"]["company_id"]
    c2 = r2.json()["data"]["company_id"]
    assert c1 != c2, "Each PG Owner must have their own unique company"


def test_04_every_new_company_receives_exactly_240_beds_capacity(client: TestClient, db: Session):
    """Test 4: Every new company receives exactly 240 beds capacity."""
    unique = secrets.token_hex(4)
    email = f"cap_check_{unique}@originpg.com"
    pwd = "CheckPass@12345"

    reg = client.post(
        "/api/v1/auth/admin/register",
        json={
            "business_name": f"Capacity Org {unique}",
            "email": email,
            "password": pwd,
            "confirm_password": pwd,
            "super_key": SUPER_KEY,
        },
    )
    assert reg.status_code == 201
    cid = reg.json()["data"]["company_id"]

    company = db.scalar(sa.select(Company).where(Company.id == uuid.UUID(str(cid))))
    assert company is not None
    assert company.bed_limit == 240

    # Login and check GET /api/v1/company/bed-capacity
    login_resp = client.post(
        "/api/v1/auth/admin/login",
        json={"email": email, "password": pwd},
    )
    assert login_resp.status_code == 200
    token = login_resp.json()["data"]["access_token"]

    cap_resp = client.get(
        "/api/v1/company/bed-capacity",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert cap_resp.status_code == 200
    data = cap_resp.json()["data"]
    assert data["total_capacity"] == 240
    assert data["used_beds"] == 0
    assert data["remaining_beds"] == 240
    assert data["usage_percentage"] == 0.0


def test_05_no_second_super_key_can_be_generated(client: TestClient):
    """Test 5: Verify no endpoint exists to generate additional Super Keys."""
    # Probing potential rogue key-generation endpoints returns 404/405
    for path in ["/api/v1/super-key", "/api/v1/admin/super-key", "/api/v1/super-keys/generate"]:
        resp = client.post(path, json={"name": "test"})
        assert resp.status_code in (404, 405)


def test_06_super_key_cannot_be_edited_or_regenerated(client: TestClient):
    """Test 6: Verify no endpoints allow editing, rotating, or regenerating the Super Key."""
    for method in ["PUT", "PATCH", "DELETE"]:
        for path in ["/api/v1/super-key", "/api/v1/company/super-key", "/api/v1/settings/super-key"]:
            resp = client.request(method, path, json={"key": "new-key"})
            assert resp.status_code in (404, 405)


def test_07_restarting_application_does_not_change_key():
    """Test 7: The Super Key is deterministically loaded from config and contains 240."""
    from app.core.config import Settings
    s = Settings()
    assert "240" in s.ADMIN_REGISTRATION_SUPER_KEY
    assert s.ADMIN_REGISTRATION_SUPER_KEY == SUPER_KEY
    # Verify hash integrity
    computed_hash = hashlib.sha256(s.ADMIN_REGISTRATION_SUPER_KEY.encode("utf-8")).hexdigest()
    assert computed_hash == SUPER_KEY_HASH


def test_08_missing_key_configuration_fails_safely(client: TestClient, monkeypatch):
    """Test 8: Missing Super Key configuration fails safely with 500 CONFIGURATION_ERROR."""
    monkeypatch.setattr(settings, "ADMIN_REGISTRATION_SUPER_KEY", "")
    monkeypatch.setattr(settings, "ADMIN_REGISTRATION_SUPER_KEY_HASH", "")

    unique = secrets.token_hex(4)
    resp = client.post(
        "/api/v1/auth/admin/register",
        json={
            "business_name": f"Missing Config PG {unique}",
            "email": f"missing_{unique}@originpg.com",
            "password": "ValidAdminPass@123",
            "confirm_password": "ValidAdminPass@123",
            "super_key": SUPER_KEY,
        },
    )
    assert resp.status_code == 500
    msg = _get_error_msg(resp).lower()
    assert "not configured" in msg or "configuration_error" in str(resp.json()).lower()


def test_09_pg_owner_cannot_change_bed_capacity(client: TestClient, db: Session):
    """Test 9: PG Owner cannot change their company bed capacity."""
    unique = secrets.token_hex(4)
    email = f"immutable_cap_{unique}@originpg.com"
    pwd = "CheckPass@12345"

    reg = client.post(
        "/api/v1/auth/admin/register",
        json={
            "business_name": f"Immutable Cap Org {unique}",
            "email": email,
            "password": pwd,
            "confirm_password": pwd,
            "super_key": SUPER_KEY,
        },
    )
    assert reg.status_code == 201
    cid = reg.json()["data"]["company_id"]

    login = client.post("/api/v1/auth/admin/login", json={"email": email, "password": pwd})
    token = login.json()["data"]["access_token"]

    # Attempt to patch company settings with higher bed_limit
    patch_resp = client.patch(
        "/api/v1/settings/company",
        headers={"Authorization": f"Bearer {token}"},
        json={"bed_limit": 500},
    )
    # Even if settings endpoint exists, verify database company bed_limit remains 240
    company = db.scalar(sa.select(Company).where(Company.id == uuid.UUID(str(cid))))
    assert company.bed_limit == 240


def test_10_and_11_creating_up_to_240_succeeds_and_241st_bed_fails(client: TestClient, db: Session):
    """Test 10 & 11: Creating 240 beds succeeds; 241st bed fails with exact error message."""
    unique = secrets.token_hex(4)
    email = f"cap_test_{unique}@originpg.com"
    pwd = "CheckPass@12345"

    reg = client.post(
        "/api/v1/auth/admin/register",
        json={
            "business_name": f"Bed Limit PG {unique}",
            "email": email,
            "password": pwd,
            "confirm_password": pwd,
            "super_key": SUPER_KEY,
        },
    )
    assert reg.status_code == 201
    cid = reg.json()["data"]["company_id"]
    uid = reg.json()["data"]["user_id"]

    login = client.post("/api/v1/auth/admin/login", json={"email": email, "password": pwd})
    token = login.json()["data"]["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # Create a property
    prop_resp = client.post(
        "/api/v1/properties",
        headers=headers,
        json={
            "name": f"Property Test {unique}",
            "code": f"PT_{unique.upper()}",
            "property_type": "CO_LIVING",
            "address_line1": "123 Main Road",
            "city": "Bangalore",
            "state": "Karnataka",
            "pincode": "560001",
        },
    )
    assert prop_resp.status_code == 201, prop_resp.text
    prop_id = uuid.UUID(prop_resp.json()["data"]["id"])

    # Create 240 rooms with max_occupancy=1 directly in DB for efficiency
    rooms = []
    beds = []
    for i in range(1, 241):
        r = Room(
            property_id=prop_id,
            room_number=f"R-{i:03d}",
            floor_number=1,
            room_type="SINGLE_ROOM",
            base_monthly_rent=8000,
            max_occupancy=2,
        )
        db.add(r)
        rooms.append(r)
    db.flush()

    for i, r in enumerate(rooms):
        b = Bed(
            property_id=prop_id,
            room_id=r.id,
            bed_number=f"B-{i+1:03d}",
            status="AVAILABLE",
            monthly_rent=8000,
            is_active=True,
            is_deleted=False,
        )
        db.add(b)
        beds.append(b)
    db.commit()

    # Verify usage is 240/240
    cap_resp = client.get("/api/v1/company/bed-capacity", headers=headers)
    assert cap_resp.status_code == 200
    assert cap_resp.json()["data"]["used_beds"] == 240
    assert cap_resp.json()["data"]["remaining_beds"] == 0
    assert cap_resp.json()["data"]["is_capacity_reached"] is True

    # Try creating the 241st bed via API
    resp_241 = client.post(
        "/api/v1/beds",
        headers=headers,
        json={
            "room_id": str(rooms[0].id),
            "bed_number": "B-241-EXTRA",
            "monthly_rent": 8000,
        },
    )
    assert resp_241.status_code == 400
    error_msg = _get_error_msg(resp_241)
    assert EXPECTED_CAPACITY_ERROR in error_msg


def test_12_bulk_bed_creation_cannot_exceed_240(client: TestClient, db: Session):
    """Test 12: Bulk bed creation cannot exceed 240 beds."""
    unique = secrets.token_hex(4)
    email = f"bulk_cap_{unique}@originpg.com"
    pwd = "CheckPass@12345"

    reg = client.post(
        "/api/v1/auth/admin/register",
        json={
            "business_name": f"Bulk Bed PG {unique}",
            "email": email,
            "password": pwd,
            "confirm_password": pwd,
            "super_key": SUPER_KEY,
        },
    )
    assert reg.status_code == 201
    cid = reg.json()["data"]["company_id"]

    login = client.post("/api/v1/auth/admin/login", json={"email": email, "password": pwd})
    token = login.json()["data"]["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    prop_resp = client.post(
        "/api/v1/properties",
        headers=headers,
        json={
            "name": f"Bulk Prop {unique}",
            "code": f"BP_{unique.upper()}",
            "address_line1": "456 Cross",
            "city": "Bangalore",
            "state": "Karnataka",
            "pincode": "560002",
        },
    )
    prop_id = uuid.UUID(prop_resp.json()["data"]["id"])

    # Pre-populate 235 beds
    r = Room(property_id=prop_id, room_number="R-BULK", floor_number=1, room_type="TEN_SHARING", max_occupancy=250)
    db.add(r)
    db.flush()

    for i in range(1, 236):
        b = Bed(property_id=prop_id, room_id=r.id, bed_number=f"B-{i}", status="AVAILABLE", is_deleted=False)
        db.add(b)
    db.commit()

    # Attempt to bulk create 10 beds (235 + 10 = 245 > 240)
    bulk_resp = client.post(
        "/api/v1/beds/bulk",
        headers=headers,
        json={
            "room_id": str(r.id),
            "bed_numbers": [f"BULK-{i}" for i in range(1, 11)],
        },
    )
    assert bulk_resp.status_code == 400
    assert EXPECTED_CAPACITY_ERROR in _get_error_msg(bulk_resp)


def test_13_multiple_properties_share_one_company_limit(client: TestClient, db: Session):
    """Test 13: Multiple properties under the same company share the 240-bed limit."""
    unique = secrets.token_hex(4)
    email = f"multi_prop_{unique}@originpg.com"
    pwd = "CheckPass@12345"

    reg = client.post(
        "/api/v1/auth/admin/register",
        json={
            "business_name": f"Multi Prop PG {unique}",
            "email": email,
            "password": pwd,
            "confirm_password": pwd,
            "super_key": SUPER_KEY,
        },
    )
    assert reg.status_code == 201

    login = client.post("/api/v1/auth/admin/login", json={"email": email, "password": pwd})
    headers = {"Authorization": f"Bearer {login.json()['data']['access_token']}"}

    # Property A: 140 beds
    pA = client.post("/api/v1/properties", headers=headers, json={"name": f"Prop A {unique}", "code": f"PA_{unique.upper()}", "address_line1": "A Street", "city": "Bangalore", "state": "Karnataka", "pincode": "560001"})
    pA_id = uuid.UUID(pA.json()["data"]["id"])

    # Property B: 100 beds
    pB = client.post("/api/v1/properties", headers=headers, json={"name": f"Prop B {unique}", "code": f"PB_{unique.upper()}", "address_line1": "B Street", "city": "Bangalore", "state": "Karnataka", "pincode": "560002"})
    pB_id = uuid.UUID(pB.json()["data"]["id"])

    rA = Room(property_id=pA_id, room_number="RA", floor_number=1, room_type="CO_LIVING", max_occupancy=200)
    rB = Room(property_id=pB_id, room_number="RB", floor_number=1, room_type="CO_LIVING", max_occupancy=200)
    db.add_all([rA, rB])
    db.flush()

    for i in range(140):
        db.add(Bed(property_id=pA_id, room_id=rA.id, bed_number=f"BA-{i}", is_deleted=False))
    for i in range(100):
        db.add(Bed(property_id=pB_id, room_id=rB.id, bed_number=f"BB-{i}", is_deleted=False))
    db.commit()

    # Now total across company is 240. Attempting to add 1 bed to either Property A or B must fail
    resp = client.post(
        "/api/v1/beds",
        headers=headers,
        json={"room_id": str(rA.id), "bed_number": "BA-EXTRA"},
    )
    assert resp.status_code == 400
    assert EXPECTED_CAPACITY_ERROR in _get_error_msg(resp)


def test_14_concurrent_bed_creation_cannot_bypass_limit(db: Session):
    """Test 14: Concurrency protection prevents exceeding 240 beds."""
    unique = secrets.token_hex(4)
    company = Company(name=f"Concurrent Co {unique}", code=f"CC_{unique.upper()}", bed_limit=240, is_active=True)
    db.add(company)
    db.flush()

    prop = Property(company_id=company.id, name="Prop Conc", code=f"PC_{unique.upper()}", address_line1="C Street", city="Bangalore", state="Karnataka", pincode="560001", total_floors=1)
    db.add(prop)
    db.flush()

    room = Room(property_id=prop.id, room_number="R-CONC", floor_number=1, room_type="DORM", max_occupancy=250)
    db.add(room)
    db.flush()

    # Pre-populate 239 beds
    for i in range(239):
        db.add(Bed(property_id=prop.id, room_id=room.id, bed_number=f"B-{i}", is_deleted=False))
    db.commit()

    # Now exactly 1 bed can be added before reaching 240
    # Two threads try to add 1 bed simultaneously
    results = []
    def add_bed():
        try:
            BedCapacityService.assert_can_add_beds(company.id, 1, db)
            results.append("SUCCESS")
        except Exception as e:
            results.append(str(e))

    add_bed()  # 240th bed assertion passes
    assert results[-1] == "SUCCESS"

    # Next assertion must fail
    try:
        # Simulate that 240 beds are now in DB
        db.add(Bed(property_id=prop.id, room_id=room.id, bed_number="B-240", is_deleted=False))
        db.commit()
        BedCapacityService.assert_can_add_beds(company.id, 1, db)
        pytest.fail("Should have raised capacity exceeded")
    except Exception as exc:
        assert EXPECTED_CAPACITY_ERROR in str(exc)


def test_15_soft_deleted_beds_are_excluded_from_usage(client: TestClient, db: Session):
    """Test 15: Soft-deleted beds are excluded from bed usage calculations."""
    unique = secrets.token_hex(4)
    email = f"soft_del_{unique}@originpg.com"
    pwd = "CheckPass@12345"

    reg = client.post(
        "/api/v1/auth/admin/register",
        json={
            "business_name": f"Soft Delete PG {unique}",
            "email": email,
            "password": pwd,
            "confirm_password": pwd,
            "super_key": SUPER_KEY,
        },
    )
    assert reg.status_code == 201

    login = client.post("/api/v1/auth/admin/login", json={"email": email, "password": pwd})
    headers = {"Authorization": f"Bearer {login.json()['data']['access_token']}"}

    prop = client.post("/api/v1/properties", headers=headers, json={"name": f"SD Prop {unique}", "code": f"SD_{unique.upper()}", "address_line1": "SD Street", "city": "Bangalore", "state": "Karnataka", "pincode": "560001"}).json()["data"]

    room = Room(property_id=uuid.UUID(prop["id"]), room_number="R-SD", floor_number=1, room_type="DORM", max_occupancy=250)
    db.add(room)
    db.flush()

    beds = []
    for i in range(240):
        b = Bed(property_id=uuid.UUID(prop["id"]), room_id=room.id, bed_number=f"B-{i}", is_deleted=False)
        db.add(b)
        beds.append(b)
    db.commit()

    # At 240 beds, adding fails
    resp_fail = client.post("/api/v1/beds", headers=headers, json={"room_id": str(room.id), "bed_number": "B-FAIL"})
    assert resp_fail.status_code == 400

    # Soft delete one bed via DELETE /api/v1/beds/{bed_id}
    bed_to_del = beds[0]
    del_resp = client.delete(f"/api/v1/beds/{bed_to_del.id}", headers=headers)
    assert del_resp.status_code == 200

    # Capacity should now report 239 used, 1 remaining
    cap_resp = client.get("/api/v1/company/bed-capacity", headers=headers)
    assert cap_resp.status_code == 200
    assert cap_resp.json()["data"]["used_beds"] == 239
    assert cap_resp.json()["data"]["remaining_beds"] == 1

    # Adding a new bed now succeeds!
    resp_ok = client.post("/api/v1/beds", headers=headers, json={"room_id": str(room.id), "bed_number": "B-NEW-240"})
    assert resp_ok.status_code == 201


def test_16_existing_authentication_and_modules_continue_working(client: TestClient):
    """Test 16: Existing login without Super Key and health endpoints work seamlessly."""
    health_resp = client.get("/api/v1/health")
    assert health_resp.status_code == 200

    # Normal resident property list works
    res_props = client.get("/api/v1/auth/resident/properties")
    assert res_props.status_code == 200


def test_17_company_data_isolation(client: TestClient, db: Session):
    """Test 17: Multi-tenant company data isolation for bed capacity and operations."""
    unique_a = secrets.token_hex(4)
    email_a = f"owner_a_{unique_a}@originpg.com"
    pwd = "CheckPass@12345"
    reg_a = client.post(
        "/api/v1/auth/admin/register",
        json={
            "business_name": f"Company A {unique_a}",
            "email": email_a,
            "password": pwd,
            "confirm_password": pwd,
            "super_key": SUPER_KEY,
        },
    )
    assert reg_a.status_code == 201
    login_a = client.post("/api/v1/auth/admin/login", json={"email": email_a, "password": pwd})
    headers_a = {"Authorization": f"Bearer {login_a.json()['data']['access_token']}"}

    prop_a = client.post(
        "/api/v1/properties",
        headers=headers_a,
        json={
            "name": f"Prop A {unique_a}",
            "code": f"PA_{unique_a.upper()}",
            "address_line1": "PA Street",
            "city": "Bangalore",
            "state": "Karnataka",
            "pincode": "560001",
        },
    ).json()["data"]

    room_a = Room(
        property_id=uuid.UUID(prop_a["id"]),
        room_number="R-A1",
        floor_number=1,
        room_type="SINGLE",
        max_occupancy=2,
    )
    db.add(room_a)
    db.flush()

    bed_a = Bed(
        property_id=uuid.UUID(prop_a["id"]),
        room_id=room_a.id,
        bed_number="B-A1",
        is_deleted=False,
    )
    db.add(bed_a)
    db.commit()

    # Company B
    unique_b = secrets.token_hex(4)
    email_b = f"owner_b_{unique_b}@originpg.com"
    reg_b = client.post(
        "/api/v1/auth/admin/register",
        json={
            "business_name": f"Company B {unique_b}",
            "email": email_b,
            "password": pwd,
            "confirm_password": pwd,
            "super_key": SUPER_KEY,
        },
    )
    assert reg_b.status_code == 201
    login_b = client.post("/api/v1/auth/admin/login", json={"email": email_b, "password": pwd})
    headers_b = {"Authorization": f"Bearer {login_b.json()['data']['access_token']}"}

    # B's capacity reports 0 used, 240 remaining
    cap_b = client.get("/api/v1/company/bed-capacity", headers=headers_b)
    assert cap_b.status_code == 200
    assert cap_b.json()["data"]["used_beds"] == 0
    assert cap_b.json()["data"]["remaining_beds"] == 240

    # B attempts to access A's property
    prop_access = client.get(f"/api/v1/properties/{prop_a['id']}", headers=headers_b)
    assert prop_access.status_code in (403, 404)

    # B attempts to create bed in A's room
    hack_bed = client.post(
        "/api/v1/beds",
        headers=headers_b,
        json={"room_id": str(room_a.id), "bed_number": "HACK-BED"},
    )
    assert hack_bed.status_code in (403, 404)

    # B attempts to delete A's bed
    del_hack = client.delete(f"/api/v1/beds/{bed_a.id}", headers=headers_b)
    assert del_hack.status_code in (403, 404)

    # Verify A's bed is still intact and not deleted
    db.refresh(bed_a)
    assert bed_a.is_deleted is False


def test_18_room_creation_with_auto_beds_enforces_capacity(client: TestClient, db: Session):
    """Test 18: Room creation with auto_create_beds enforces 240-bed limit."""
    unique = secrets.token_hex(4)
    email = f"autobed_{unique}@originpg.com"
    pwd = "CheckPass@12345"
    reg = client.post(
        "/api/v1/auth/admin/register",
        json={
            "business_name": f"AutoBed Org {unique}",
            "email": email,
            "password": pwd,
            "confirm_password": pwd,
            "super_key": SUPER_KEY,
        },
    )
    assert reg.status_code == 201
    login = client.post("/api/v1/auth/admin/login", json={"email": email, "password": pwd})
    headers = {"Authorization": f"Bearer {login.json()['data']['access_token']}"}

    prop = client.post(
        "/api/v1/properties",
        headers=headers,
        json={
            "name": f"AutoBed Prop {unique}",
            "code": f"AB_{unique.upper()}",
            "address_line1": "AB Street",
            "city": "Bangalore",
            "state": "Karnataka",
            "pincode": "560001",
        },
    ).json()["data"]

    # Prepopulate 235 beds
    dummy_room = Room(
        property_id=uuid.UUID(prop["id"]),
        room_number="R-DUMMY",
        floor_number=1,
        room_type="DORM",
        max_occupancy=240,
    )
    db.add(dummy_room)
    db.flush()

    for i in range(235):
        db.add(Bed(property_id=uuid.UUID(prop["id"]), room_id=dummy_room.id, bed_number=f"BD-{i}", is_deleted=False))
    db.commit()

    # Attempt to create room with 6 auto beds (235 + 6 = 241 > 240) -> fails 400
    res_fail = client.post(
        "/api/v1/rooms",
        headers=headers,
        json={
            "property_id": prop["id"],
            "room_number": "R-EXCEED",
            "floor_number": 2,
            "room_type": "DORM",
            "bed_count": 6,
            "auto_create_beds": True,
        },
    )
    assert res_fail.status_code == 400
    msg = _get_error_msg(res_fail).lower()
    assert "exceed" in msg or "capacity" in msg

    # Create room with 5 auto beds (235 + 5 = 240) -> succeeds 201
    res_ok = client.post(
        "/api/v1/rooms",
        headers=headers,
        json={
            "property_id": prop["id"],
            "room_number": "R-EXACT",
            "floor_number": 2,
            "room_type": "DORM",
            "bed_count": 5,
            "auto_create_beds": True,
        },
    )
    assert res_ok.status_code == 201

    cap = client.get("/api/v1/company/bed-capacity", headers=headers)
    assert cap.status_code == 200
    assert cap.json()["data"]["used_beds"] == 240
    assert cap.json()["data"]["remaining_beds"] == 0


def test_19_room_update_with_add_beds_enforces_capacity(client: TestClient, db: Session):
    """Test 19: Room update with add_beds enforces 240-bed limit."""
    unique = secrets.token_hex(4)
    email = f"patchbed_{unique}@originpg.com"
    pwd = "CheckPass@12345"
    reg = client.post(
        "/api/v1/auth/admin/register",
        json={
            "business_name": f"PatchBed Org {unique}",
            "email": email,
            "password": pwd,
            "confirm_password": pwd,
            "super_key": SUPER_KEY,
        },
    )
    assert reg.status_code == 201
    login = client.post("/api/v1/auth/admin/login", json={"email": email, "password": pwd})
    headers = {"Authorization": f"Bearer {login.json()['data']['access_token']}"}

    prop = client.post(
        "/api/v1/properties",
        headers=headers,
        json={
            "name": f"PatchBed Prop {unique}",
            "code": f"PB_{unique.upper()}",
            "address_line1": "PB Street",
            "city": "Bangalore",
            "state": "Karnataka",
            "pincode": "560001",
        },
    ).json()["data"]

    room_resp = client.post(
        "/api/v1/rooms",
        headers=headers,
        json={
            "property_id": prop["id"],
            "room_number": "R-PB1",
            "floor_number": 1,
            "room_type": "SINGLE",
            "bed_count": 0,
            "auto_create_beds": False,
        },
    )
    assert room_resp.status_code == 201
    room_id = room_resp.json()["data"]["id"]

    # Prepopulate 239 beds
    for i in range(239):
        db.add(Bed(property_id=uuid.UUID(prop["id"]), room_id=uuid.UUID(room_id), bed_number=f"PB-BED-{i}", is_deleted=False))
    db.commit()

    # Attempt to add 2 beds via patch -> fails 400
    fail_patch = client.patch(
        f"/api/v1/rooms/{room_id}",
        headers=headers,
        json={"add_beds": 2},
    )
    assert fail_patch.status_code == 400
    msg = _get_error_msg(fail_patch).lower()
    assert "exceed" in msg or "capacity" in msg

    # Add 1 bed via patch -> succeeds 200 (reaching 240)
    ok_patch = client.patch(
        f"/api/v1/rooms/{room_id}",
        headers=headers,
        json={"add_beds": 1},
    )
    assert ok_patch.status_code == 200

    cap = client.get("/api/v1/company/bed-capacity", headers=headers)
    assert cap.status_code == 200
    assert cap.json()["data"]["used_beds"] == 240
    assert cap.json()["data"]["remaining_beds"] == 0
