import uuid
import pytest
import sqlalchemy as sa
from app.models.room import Room
from app.models.bed import Bed

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


def test_postgres_room_crud_and_unique_constraint(client, pg_session):
    """Verifies room creation, retrieval, and PostgreSQL unique constraint enforcement."""
    admin_token = get_token(client, "admin")

    props = client.get("/api/v1/properties", headers={"Authorization": f"Bearer {admin_token}"}).json()["data"]
    kor_id = next(p["id"] for p in props if p["code"] == "OG-KOR")
    hsr_id = next(p["id"] for p in props if p["code"] == "OG-HSR")

    # 1. Create room 101 in OG-KOR
    payload = {
        "room_number": "PG-101",
        "floor_number": 1,
        "room_type": "DOUBLE",
        "base_monthly_rent": 11000.0,
        "deposit_amount": 22000.0,
        "amenities": ["AC", "BALCONY"],
        "is_active": True,
    }
    resp = client.post(
        f"/api/v1/properties/{kor_id}/rooms",
        headers={"Authorization": f"Bearer {admin_token}"},
        json=payload,
    )
    assert resp.status_code == 201
    room_data = resp.json()["data"]
    assert room_data["room_number"] == "PG-101"
    room_id = room_data["id"]

    # 2. Verify row exists in PostgreSQL via pg_session
    pg_room = pg_session.scalar(sa.select(Room).where(Room.id == uuid.UUID(room_id)))
    assert pg_room is not None
    assert pg_room.room_number == "PG-101"
    assert str(pg_room.property_id) == kor_id

    # 3. Duplicate room number in same property must be rejected
    dup_resp = client.post(
        f"/api/v1/properties/{kor_id}/rooms",
        headers={"Authorization": f"Bearer {admin_token}"},
        json=payload,
    )
    assert dup_resp.status_code == 409
    assert dup_resp.json()["error"]["code"] == "CONFLICT"

    # 4. Same room number in a different property (OG-HSR) must succeed
    diff_prop_resp = client.post(
        f"/api/v1/properties/{hsr_id}/rooms",
        headers={"Authorization": f"Bearer {admin_token}"},
        json=payload,
    )
    assert diff_prop_resp.status_code == 201
    assert diff_prop_resp.json()["data"]["property_id"] == hsr_id


def test_postgres_bed_crud_and_unique_constraint(client, pg_session):
    """Verifies bed creation, retrieval, and unique bed numbers per room in PostgreSQL."""
    admin_token = get_token(client, "admin")
    props = client.get("/api/v1/properties", headers={"Authorization": f"Bearer {admin_token}"}).json()["data"]
    kor_id = next(p["id"] for p in props if p["code"] == "OG-KOR")

    # Create Room 202
    room_resp = client.post(
        f"/api/v1/properties/{kor_id}/rooms",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"room_number": "PG-202", "floor_number": 2, "room_type": "TRIPLE", "base_monthly_rent": 7500.0},
    )
    assert room_resp.status_code == 201
    room_id = room_resp.json()["data"]["id"]

    # 1. Add Bed 1
    bed1_resp = client.post(
        f"/api/v1/rooms/{room_id}/beds",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"bed_number": "Bed-1", "monthly_rent": 7500.0, "status": "AVAILABLE"},
    )
    assert bed1_resp.status_code == 201
    bed1_id = bed1_resp.json()["data"]["id"]

    # 2. Add Bed 2
    bed2_resp = client.post(
        f"/api/v1/rooms/{room_id}/beds",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"bed_number": "Bed-2", "monthly_rent": 8000.0, "status": "AVAILABLE"},
    )
    assert bed2_resp.status_code == 201

    # 3. Duplicate bed number in same room must fail with 409 Conflict
    dup_bed_resp = client.post(
        f"/api/v1/rooms/{room_id}/beds",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"bed_number": "Bed-1", "monthly_rent": 7500.0, "status": "AVAILABLE"},
    )
    assert dup_bed_resp.status_code == 409

    # 4. Direct inspection in PostgreSQL verifies beds are indexed by property_id
    pg_beds = pg_session.scalars(sa.select(Bed).where(Bed.room_id == uuid.UUID(room_id))).all()
    assert len(pg_beds) == 2
    for b in pg_beds:
        assert str(b.property_id) == kor_id


def test_postgres_property_manager_scoping(client):
    """Verifies that Property Manager is strictly scoped to assigned properties."""
    mgr_token = get_token(client, "manager")
    admin_token = get_token(client, "admin")

    props = client.get("/api/v1/properties", headers={"Authorization": f"Bearer {admin_token}"}).json()["data"]
    kor_id = next(p["id"] for p in props if p["code"] == "OG-KOR")
    ind_id = next(p["id"] for p in props if p["code"] == "OG-IND")

    # Manager CAN create room in assigned OG-KOR
    resp1 = client.post(
        f"/api/v1/properties/{kor_id}/rooms",
        headers={"Authorization": f"Bearer {mgr_token}"},
        json={"room_number": "MGR-101", "floor_number": 1, "room_type": "SINGLE", "base_monthly_rent": 12000.0},
    )
    assert resp1.status_code == 201

    # Manager BLOCKED from creating room in unassigned OG-IND
    resp2 = client.post(
        f"/api/v1/properties/{ind_id}/rooms",
        headers={"Authorization": f"Bearer {mgr_token}"},
        json={"room_number": "MGR-101", "floor_number": 1, "room_type": "SINGLE", "base_monthly_rent": 12000.0},
    )
    assert resp2.status_code == 403
    assert resp2.json()["error"]["code"] == "PERMISSION_DENIED"

    # Manager BLOCKED from listing rooms in unassigned OG-IND
    resp3 = client.get(
        f"/api/v1/properties/{ind_id}/rooms",
        headers={"Authorization": f"Bearer {mgr_token}"},
    )
    assert resp3.status_code == 403


def test_postgres_staff_status_update_and_restrictions(client):
    """Staff can update bed status in assigned property, but cannot create rooms."""
    admin_token = get_token(client, "admin")
    staff_token = get_token(client, "staff")

    props = client.get("/api/v1/properties", headers={"Authorization": f"Bearer {admin_token}"}).json()["data"]
    kor_id = next(p["id"] for p in props if p["code"] == "OG-KOR")

    # Super admin creates room and bed
    r = client.post(
        f"/api/v1/properties/{kor_id}/rooms",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"room_number": "STF-101", "floor_number": 1, "room_type": "SINGLE", "base_monthly_rent": 9000.0},
    ).json()["data"]

    b = client.post(
        f"/api/v1/rooms/{r['id']}/beds",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"bed_number": "1", "monthly_rent": 9000.0, "status": "AVAILABLE"},
    ).json()["data"]
    bed_id = b["id"]

    # 1. Staff CAN update bed status to MAINTENANCE
    patch_resp = client.patch(
        f"/api/v1/beds/{bed_id}/status",
        headers={"Authorization": f"Bearer {staff_token}"},
        json={"status": "MAINTENANCE"},
    )
    assert patch_resp.status_code == 200
    assert patch_resp.json()["data"]["status"] == "MAINTENANCE"

    # 2. Staff BLOCKED from creating rooms
    create_room_resp = client.post(
        f"/api/v1/properties/{kor_id}/rooms",
        headers={"Authorization": f"Bearer {staff_token}"},
        json={"room_number": "ILLEGAL", "floor_number": 1, "room_type": "SINGLE", "base_monthly_rent": 5000.0},
    )
    assert create_room_resp.status_code == 403


def test_postgres_resident_blocked_from_all_room_bed_endpoints(client):
    """Residents must never be allowed access to room or bed management endpoints."""
    resident_token = get_token(client, "resident")

    # 1. Listing rooms
    assert client.get("/api/v1/rooms", headers={"Authorization": f"Bearer {resident_token}"}).status_code == 403

    # 2. Listing beds
    assert client.get("/api/v1/beds", headers={"Authorization": f"Bearer {resident_token}"}).status_code == 403


def test_postgres_portfolio_wide_owner_views(client):
    """Super Admin can list rooms and beds across all properties without a property filter."""
    admin_token = get_token(client, "admin")

    # 1. List rooms portfolio-wide
    rooms_resp = client.get("/api/v1/rooms", headers={"Authorization": f"Bearer {admin_token}"})
    assert rooms_resp.status_code == 200
    assert "data" in rooms_resp.json()

    # 2. List beds portfolio-wide
    beds_resp = client.get("/api/v1/beds", headers={"Authorization": f"Bearer {admin_token}"})
    assert beds_resp.status_code == 200
    assert "data" in beds_resp.json()


def test_postgres_composite_fk_blocks_cross_property_mismatch(pg_session):
    """
    Directly exercises the PostgreSQL composite foreign key constraint
    'fk_beds_room_id_property_id' to prove that a bed can NEVER be inserted
    with a property_id different from its parent room's property_id.
    """
    # 1. Fetch two distinct properties
    props = pg_session.execute(sa.text("SELECT id FROM properties ORDER BY code LIMIT 2;")).fetchall()
    p1_id, p2_id = props[0][0], props[1][0]

    # 2. Create room in Property 1
    room_id = uuid.uuid4()
    pg_session.execute(
        sa.text("""
            INSERT INTO rooms (id, property_id, room_number, floor_number, room_type, base_monthly_rent, deposit_amount, amenities, is_active)
            VALUES (:id, :pid, 'CROSS-101', 1, 'SINGLE', 8000, 16000, '[]', true);
        """),
        {"id": room_id, "pid": p1_id},
    )

    # 3. Attempt to insert a bed referencing room_id (in P1) but specifying property_id = P2
    mismatched_bed_id = uuid.uuid4()
    with pytest.raises(sa.exc.IntegrityError) as exc_info:
        pg_session.execute(
            sa.text("""
                INSERT INTO beds (id, property_id, room_id, bed_number, monthly_rent, status, is_active)
                VALUES (:id, :pid, :rid, 'Bed-Mismatch', 8000, 'AVAILABLE', true);
            """),
            {"id": mismatched_bed_id, "pid": p2_id, "rid": room_id},
        )
    # Confirm PostgreSQL raised the composite foreign key violation
    err_str = str(exc_info.value)
    assert "fk_beds_room_id_property_id" in err_str or "foreign key constraint" in err_str.lower()


def test_postgres_restrict_blocks_deleting_room_with_beds(pg_session):
    """
    Verifies that ON DELETE RESTRICT on the composite foreign key prevents
    accidental cascading deletion of operational bed data when deleting a room.
    """
    props = pg_session.execute(sa.text("SELECT id FROM properties ORDER BY code LIMIT 1;")).fetchall()
    p1_id = props[0][0]

    room_id = uuid.uuid4()
    pg_session.execute(
        sa.text("""
            INSERT INTO rooms (id, property_id, room_number, floor_number, room_type, base_monthly_rent, deposit_amount, amenities, is_active)
            VALUES (:id, :pid, 'DEL-TEST-101', 1, 'SINGLE', 8000, 16000, '[]', true);
        """),
        {"id": room_id, "pid": p1_id},
    )

    bed_id = uuid.uuid4()
    pg_session.execute(
        sa.text("""
            INSERT INTO beds (id, property_id, room_id, bed_number, monthly_rent, status, is_active)
            VALUES (:id, :pid, :rid, 'B1', 8000, 'AVAILABLE', true);
        """),
        {"id": bed_id, "pid": p1_id, "rid": room_id},
    )

    # Attempting to delete the room directly must fail due to RESTRICT on the composite FK
    with pytest.raises(sa.exc.IntegrityError) as exc_info:
        pg_session.execute(
            sa.text("DELETE FROM rooms WHERE id = :id;"),
            {"id": room_id},
        )
    err_str = str(exc_info.value)
    assert "fk_beds_room_id_property_id" in err_str
    assert "restrict" in err_str.lower()


def test_postgres_manager_blocked_from_unassigned_room_beds(client):
    """Verifies manager receives 403 when requesting beds of an unassigned room."""
    admin_token = get_token(client, "admin")
    mgr_token = get_token(client, "manager")

    props = client.get("/api/v1/properties", headers={"Authorization": f"Bearer {admin_token}"}).json()["data"]
    ind_id = next(p["id"] for p in props if p["code"] == "OG-IND")

    r = client.post(
        f"/api/v1/properties/{ind_id}/rooms",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"room_number": "PG-IND-99", "floor_number": 1, "room_type": "SINGLE", "base_monthly_rent": 15000.0},
    ).json()["data"]

    resp = client.get(
        f"/api/v1/rooms/{r['id']}/beds",
        headers={"Authorization": f"Bearer {mgr_token}"},
    )
    assert resp.status_code == 403
    assert resp.json()["error"]["code"] == "PERMISSION_DENIED"

