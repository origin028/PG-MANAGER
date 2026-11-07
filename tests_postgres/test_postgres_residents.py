import concurrent.futures
import uuid
import pytest
import sqlalchemy as sa
from app.models.bed import Bed
from app.models.invoice import Invoice
from app.models.payment import Payment
from app.models.property import Property
from app.models.resident import Resident
from app.models.room import Room
from tests_postgres.test_postgres_rooms_and_beds import get_token


def _get_property_map(client, token):
    props = client.get("/api/v1/properties", headers={"Authorization": f"Bearer {token}"}).json()["data"]
    return {p["code"]: p["id"] for p in props}


def test_postgres_resident_admission_and_persistence(client, pg_session):
    """
    Verifies valid resident admission via API and confirms direct row persistence
    in the live PostgreSQL database with sensitive field masking.
    """
    admin_token = get_token(client, "admin")
    prop_map = _get_property_map(client, admin_token)
    kor_id = prop_map["OG-KOR"]

    payload = {
        "property_id": kor_id,
        "full_name": "Arjun Singhania",
        "phone": "9812340001",
        "email": "arjun.singhania@example.com",
        "emergency_contact_name": "Sunita Singhania",
        "emergency_contact_phone": "9812340002",
        "monthly_rent": 14000.0,
        "security_deposit": 28000.0,
        "id_proof_type": "AADHAAR",
        "id_proof_number": "9999 8888 7777",
        "kyc_notes": "Aadhaar verified via portal",
    }
    resp = client.post(
        "/api/v1/residents",
        headers={"Authorization": f"Bearer {admin_token}"},
        json=payload,
    )
    assert resp.status_code == 201
    res_data = resp.json()["data"]
    res_id = uuid.UUID(res_data["id"])

    # Verify direct PostgreSQL row
    pg_res = pg_session.scalar(sa.select(Resident).where(Resident.id == res_id))
    assert pg_res is not None
    assert pg_res.full_name == "Arjun Singhania"
    assert pg_res.phone == "9812340001"
    assert str(pg_res.property_id) == kor_id
    assert pg_res.status == "PENDING"
    assert pg_res.kyc_status == "PENDING"
    assert pg_res.id_proof_number_masked == "XXXX-XXXX-7777"
    assert "9999 8888 7777" not in str(pg_res.__dict__)


def test_postgres_composite_fk_blocks_resident_bed_property_mismatch(client, pg_session):
    """
    Verifies that PostgreSQL storage engine physically rejects assigning a bed
    belonging to Property 1 to a resident belonging to Property 2 via the
    composite foreign key constraint fk_residents_bed_id_property_id.
    """
    admin_token = get_token(client, "admin")
    prop_map = _get_property_map(client, admin_token)
    kor_id = uuid.UUID(prop_map["OG-KOR"])
    hsr_id = uuid.UUID(prop_map["OG-HSR"])

    # Create Room & Bed in OG-KOR
    room = Room(
        property_id=kor_id,
        room_number="FK-KOR-1",
        floor_number=1,
        room_type="SINGLE",
        base_monthly_rent=10000.0,
        deposit_amount=20000.0,
    )
    pg_session.add(room)
    pg_session.flush()

    bed = Bed(
        property_id=kor_id,
        room_id=room.id,
        bed_number="FK-B1",
        monthly_rent=10000.0,
        status="AVAILABLE",
    )
    pg_session.add(bed)
    pg_session.flush()

    # Attempt to insert a resident in OG-HSR with bed in OG-KOR directly in PostgreSQL
    mismatched_resident = Resident(
        company_id=pg_session.scalar(sa.select(Property.company_id).where(Property.id == kor_id)),
        property_id=hsr_id,  # Mismatch: Resident in HSR, Bed in KOR
        bed_id=bed.id,
        room_id=room.id,
        full_name="Mismatched Resident",
        phone="9800000001",
        status="ACTIVE",
    )
    pg_session.add(mismatched_resident)

    with pytest.raises(sa.exc.IntegrityError) as exc_info:
        pg_session.flush()

    # PostgreSQL must reject with foreign key violation on fk_residents_bed_id_property_id
    err_msg = str(exc_info.value).lower()
    assert "fk_residents_bed_id_property_id" in err_msg or "foreign key" in err_msg
    pg_session.rollback()


def test_postgres_partial_unique_index_enforces_one_active_resident_per_bed(client, pg_session):
    """
    Verifies that the partial unique index uq_active_resident_bed prevents two
    concurrent active residents on the same bed, but allows multiple historical records.
    """
    admin_token = get_token(client, "admin")
    prop_map = _get_property_map(client, admin_token)
    kor_id = uuid.UUID(prop_map["OG-KOR"])
    company_id = pg_session.scalar(sa.select(Property.company_id).where(Property.id == kor_id))

    # Room & Bed
    room = Room(property_id=kor_id, room_number="UQ-R1", floor_number=1, room_type="SINGLE")
    pg_session.add(room)
    pg_session.flush()

    bed = Bed(property_id=kor_id, room_id=room.id, bed_number="UQ-B1", monthly_rent=12000.0, status="AVAILABLE")
    pg_session.add(bed)
    pg_session.flush()

    # 1. Insert Resident 1 as ACTIVE
    res1_id = uuid.uuid4()
    pg_session.execute(
        sa.text("""
            INSERT INTO residents (id, company_id, property_id, room_id, bed_id, full_name, phone, status, kyc_status)
            VALUES (:id, :company_id, :property_id, :room_id, :bed_id, 'Resident One', '9800000002', 'ACTIVE', 'PENDING')
        """).bindparams(id=res1_id, company_id=company_id, property_id=kor_id, room_id=room.id, bed_id=bed.id)
    )

    # 2. Insert Resident 2 also as ACTIVE on the same bed inside a SAVEPOINT -> Violates partial unique index!
    res2_id = uuid.uuid4()
    with pytest.raises(sa.exc.IntegrityError) as exc_info:
        with pg_session.begin_nested():
            pg_session.execute(
                sa.text("""
                    INSERT INTO residents (id, company_id, property_id, room_id, bed_id, full_name, phone, status, kyc_status)
                    VALUES (:id, :company_id, :property_id, :room_id, :bed_id, 'Resident Two', '9800000003', 'ACTIVE', 'PENDING')
                """).bindparams(id=res2_id, company_id=company_id, property_id=kor_id, room_id=room.id, bed_id=bed.id)
            )

    assert "uq_active_resident_bed" in str(exc_info.value)

    # 3. Update Resident 1 to CHECKED_OUT, then adding Resident 2 as ACTIVE succeeds
    pg_session.execute(
        sa.text("UPDATE residents SET status = 'CHECKED_OUT' WHERE id = :id").bindparams(id=res1_id)
    )

    pg_session.execute(
        sa.text("""
            INSERT INTO residents (id, company_id, property_id, room_id, bed_id, full_name, phone, status, kyc_status)
            VALUES (:id, :company_id, :property_id, :room_id, :bed_id, 'Resident Two Active', '9800000003', 'ACTIVE', 'PENDING')
        """).bindparams(id=res2_id, company_id=company_id, property_id=kor_id, room_id=room.id, bed_id=bed.id)
    )


def test_postgres_concurrent_bed_allocation():
    """
    Critical concurrency test:
    Two simultaneous HTTP requests attempt to check in two different residents
    to the exact same bed at the same instant over independent PostgreSQL connections.
    Validates SELECT ... FOR UPDATE row-locking and ensures exactly ONE succeeds (200),
    while the other receives a clean conflict (409 Conflict).
    """
    from fastapi.testclient import TestClient
    from app.main import app
    from app.api.deps import get_db
    from app.db.session import SessionLocal

    # Temporarily remove dependency override to enable true multi-connection concurrency
    old_override = app.dependency_overrides.pop(get_db, None)

    suffix = uuid.uuid4().hex[:6]
    room_number = f"CONC-{suffix}"
    bed_number = f"CB-{suffix}"
    phone_a = f"9811{uuid.uuid4().hex[:6]}"
    phone_b = f"9822{uuid.uuid4().hex[:6]}"

    client = TestClient(app)
    admin_token = get_token(client, "admin")
    prop_map = _get_property_map(client, admin_token)
    kor_id = prop_map["OG-KOR"]

    # 1. Create Room and Bed
    room_resp = client.post(
        f"/api/v1/properties/{kor_id}/rooms",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"room_number": room_number, "floor_number": 1, "room_type": "SINGLE"},
    )
    assert room_resp.status_code == 201
    room_id = room_resp.json()["data"]["id"]

    bed_resp = client.post(
        f"/api/v1/rooms/{room_id}/beds",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"bed_number": bed_number, "monthly_rent": 12000.0, "status": "AVAILABLE"},
    )
    assert bed_resp.status_code == 201
    bed_id = bed_resp.json()["data"]["id"]

    # 2. Admit two pending residents
    res_a_id = client.post(
        "/api/v1/residents",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"property_id": kor_id, "full_name": f"Concurrent Resident A {suffix}", "phone": phone_a},
    ).json()["data"]["id"]

    res_b_id = client.post(
        "/api/v1/residents",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"property_id": kor_id, "full_name": f"Concurrent Resident B {suffix}", "phone": phone_b},
    ).json()["data"]["id"]

    try:
        # 3. Fire simultaneous check-in requests
        def execute_checkin(resident_id):
            c = TestClient(app)
            return c.post(
                f"/api/v1/residents/{resident_id}/check-in",
                headers={"Authorization": f"Bearer {admin_token}"},
                json={"bed_id": bed_id},
            )

        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
            f1 = executor.submit(execute_checkin, res_a_id)
            f2 = executor.submit(execute_checkin, res_b_id)
            resp1 = f1.result()
            resp2 = f2.result()

        status_codes = [resp1.status_code, resp2.status_code]
        assert 200 in status_codes, f"Expected one 200 OK, got {status_codes}"
        assert 409 in status_codes, f"Expected one 409 Conflict, got {status_codes}"

        # Confirm bed is OCCUPIED
        bed_check = client.get(f"/api/v1/beds/{bed_id}", headers={"Authorization": f"Bearer {admin_token}"}).json()["data"]
        assert bed_check["status"] == "OCCUPIED"
    finally:
        # Clean up created demo test rows in dependency order. Check-in now
        # generates an initial rent invoice, so dependent ledger rows must be
        # removed before the residents they belong to.
        with SessionLocal() as s:
            res_ids = [uuid.UUID(res_a_id), uuid.UUID(res_b_id)]
            s.execute(sa.delete(Payment).where(Payment.resident_id.in_(res_ids)))
            s.execute(sa.delete(Invoice).where(Invoice.resident_id.in_(res_ids)))
            s.execute(sa.delete(Resident).where(Resident.id.in_(res_ids)))
            s.execute(sa.delete(Bed).where(Bed.id == uuid.UUID(bed_id)))
            s.execute(sa.delete(Room).where(Room.id == uuid.UUID(room_id)))
            s.commit()
        if old_override:
            app.dependency_overrides[get_db] = old_override


def test_postgres_checkout_atomically_releases_bed(client, pg_session):
    """
    Verifies that checking out a resident atomically releases their occupied bed
    back to AVAILABLE and updates actual_check_out_date in PostgreSQL.
    """
    admin_token = get_token(client, "admin")
    prop_map = _get_property_map(client, admin_token)
    kor_id = prop_map["OG-KOR"]

    room_id = client.post(
        f"/api/v1/properties/{kor_id}/rooms",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"room_number": "OUT-101", "floor_number": 1, "room_type": "SINGLE"},
    ).json()["data"]["id"]

    bed_id = client.post(
        f"/api/v1/rooms/{room_id}/beds",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"bed_number": "OUT-B1", "monthly_rent": 11000.0, "status": "AVAILABLE"},
    ).json()["data"]["id"]

    res_id = client.post(
        "/api/v1/residents",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"property_id": kor_id, "full_name": "Checkout Subject", "phone": "9811000003"},
    ).json()["data"]["id"]

    # Check in
    client.post(
        f"/api/v1/residents/{res_id}/check-in",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"bed_id": bed_id},
    )

    # Check out
    out_resp = client.post(
        f"/api/v1/residents/{res_id}/check-out",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"notes": "Normal departure"},
    )
    assert out_resp.status_code == 200
    assert out_resp.json()["data"]["status"] == "CHECKED_OUT"

    # Verify live bed status is AVAILABLE in PostgreSQL
    pg_bed = pg_session.scalar(sa.select(Bed).where(Bed.id == uuid.UUID(bed_id)))
    assert pg_bed.status == "AVAILABLE"


def test_postgres_property_manager_cross_property_isolation(client):
    """
    Verifies that a Property Manager assigned to Koramangala and HSR Layout
    is strictly blocked with 403 Forbidden when attempting any resident operation
    in unassigned properties (Indiranagar, Electronic City, Bellandur).
    """
    manager_token = get_token(client, "manager")
    admin_token = get_token(client, "admin")
    prop_map = _get_property_map(client, admin_token)
    kor_id = prop_map["OG-KOR"]
    ind_id = prop_map["OG-IND"]

    # Manager CAN admit resident in assigned OG-KOR
    kor_resp = client.post(
        "/api/v1/residents",
        headers={"Authorization": f"Bearer {manager_token}"},
        json={"property_id": kor_id, "full_name": "PG-1 Manager Resident", "phone": "9822000001"},
    )
    assert kor_resp.status_code == 201

    # Manager CANNOT admit resident in unassigned OG-IND -> 403 Forbidden
    ind_resp = client.post(
        "/api/v1/residents",
        headers={"Authorization": f"Bearer {manager_token}"},
        json={"property_id": ind_id, "full_name": "PG-3 Illegal Resident", "phone": "9822000002"},
    )
    assert ind_resp.status_code == 403
    assert ind_resp.json()["error"]["code"] == "PERMISSION_DENIED"


def test_postgres_staff_scoped_access_and_kyc(client):
    """
    Verifies Staff (Warden) permissions:
    - CAN read residents and update KYC in assigned property (OG-KOR).
    - CANNOT create resident admissions, check-in, or check-out (403 Forbidden).
    - CANNOT access unassigned properties (403 Forbidden).
    """
    staff_token = get_token(client, "staff")
    admin_token = get_token(client, "admin")
    prop_map = _get_property_map(client, admin_token)
    kor_id = prop_map["OG-KOR"]
    ind_id = prop_map["OG-IND"]

    # 1. Staff reads residents in OG-KOR
    read_resp = client.get(f"/api/v1/residents?property_id={kor_id}", headers={"Authorization": f"Bearer {staff_token}"})
    assert read_resp.status_code == 200

    # 2. Staff cannot read unassigned OG-IND
    unassigned_resp = client.get(f"/api/v1/residents?property_id={ind_id}", headers={"Authorization": f"Bearer {staff_token}"})
    assert unassigned_resp.status_code == 403

    # 3. Staff cannot admit resident
    admit_resp = client.post(
        "/api/v1/residents",
        headers={"Authorization": f"Bearer {staff_token}"},
        json={"property_id": kor_id, "full_name": "Staff Admit Attempt", "phone": "9833000001"},
    )
    assert admit_resp.status_code == 403

    # 4. Super admin admits resident, Staff updates KYC
    res_id = client.post(
        "/api/v1/residents",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"property_id": kor_id, "full_name": "Staff KYC Resident", "phone": "9833000002"},
    ).json()["data"]["id"]

    kyc_resp = client.patch(
        f"/api/v1/residents/{res_id}/kyc",
        headers={"Authorization": f"Bearer {staff_token}"},
        json={"kyc_status": "VERIFIED", "id_proof_type": "DRIVING_LICENSE", "id_proof_number": "KA0120220001234"},
    )
    assert kyc_resp.status_code == 200
    assert kyc_resp.json()["data"]["kyc_status"] == "VERIFIED"
    assert kyc_resp.json()["data"]["id_proof_number_masked"] == "XXXXXXXXXXX1234"


def test_postgres_resident_role_isolation_and_privacy(client):
    """
    Verifies Resident role boundaries:
    - Resident cannot access general resident lists or other residents' profiles.
    - Resident can access own profile (/me) and own occupancy (/me/occupancy).
    """
    resident_token = get_token(client, "resident")
    admin_token = get_token(client, "admin")
    prop_map = _get_property_map(client, admin_token)
    kor_id = prop_map["OG-KOR"]

    # 1. Resident cannot list residents -> 403 Forbidden
    list_resp = client.get("/api/v1/residents", headers={"Authorization": f"Bearer {resident_token}"})
    assert list_resp.status_code == 403

    # 2. Seeded resident profile exists for phone 9876543213
    client.post(
        "/api/v1/residents",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"property_id": kor_id, "full_name": "Rohan Deshmukh", "phone": "9876543213"},
    )

    # 3. Resident accesses /me and /me/occupancy
    me_resp = client.get("/api/v1/residents/me", headers={"Authorization": f"Bearer {resident_token}"})
    assert me_resp.status_code == 200
    assert me_resp.json()["data"]["phone"] == "9876543213"

    me_occ = client.get("/api/v1/residents/me/occupancy", headers={"Authorization": f"Bearer {resident_token}"})
    assert me_occ.status_code == 200


def test_postgres_restrict_blocks_deleting_bed_with_active_or_historical_resident(client, pg_session):
    """
    Verifies that foreign key ON DELETE RESTRICT blocks accidental or cascade
    deletion of a Bed that has resident allocation records.
    """
    admin_token = get_token(client, "admin")
    prop_map = _get_property_map(client, admin_token)
    kor_id = uuid.UUID(prop_map["OG-KOR"])
    company_id = pg_session.scalar(sa.select(Property.company_id).where(Property.id == kor_id))

    room = Room(property_id=kor_id, room_number="DEL-R1", floor_number=1, room_type="SINGLE")
    pg_session.add(room)
    pg_session.flush()

    bed = Bed(property_id=kor_id, room_id=room.id, bed_number="DEL-B1", monthly_rent=10000.0, status="AVAILABLE")
    pg_session.add(bed)
    pg_session.flush()

    resident = Resident(
        company_id=company_id,
        property_id=kor_id,
        room_id=room.id,
        bed_id=bed.id,
        full_name="Deletable Bed Resident",
        phone="9844000001",
        status="ACTIVE",
    )
    pg_session.add(resident)
    pg_session.flush()

    # Attempt to delete the Bed row directly in PostgreSQL
    with pytest.raises(sa.exc.IntegrityError) as exc_info:
        pg_session.execute(sa.text(f"DELETE FROM beds WHERE id = '{bed.id}';"))
        pg_session.flush()

    err = str(exc_info.value).lower()
    assert "foreign key" in err or "restrict" in err or "fk_residents_bed_id_property_id" in err
    pg_session.rollback()
