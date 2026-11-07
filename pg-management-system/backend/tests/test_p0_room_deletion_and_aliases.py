import uuid
from datetime import date, datetime, timezone
import pytest
import sqlalchemy as sa
from fastapi.testclient import TestClient

from app.core.security import create_access_token, get_password_hash
from app.models.bed import Bed
from app.models.food_menu import FoodMenu
from app.models.property import Company, Property
from app.models.resident import Resident
from app.models.role import Role
from app.models.room import Room
from app.models.user import User


@pytest.fixture
def test_setup(client: TestClient):
    session_factory = client.app.state.testing_session
    db = session_factory()
    try:
        company = Company(name="Origin Stays Co", code="ORIGIN_P0")
        db.add(company)
        db.flush()

        super_admin_role = Role(name="SUPER_ADMIN", display_name="Super Admin")
        pm_role = Role(name="PROPERTY_MANAGER", display_name="Property Manager")
        resident_role = Role(name="RESIDENT", display_name="Resident")
        db.add_all([super_admin_role, pm_role, resident_role])
        db.flush()

        admin_user = User(
            company_id=company.id,
            role_id=super_admin_role.id,
            full_name="Super Admin",
            email="superadmin.p0@example.com",
            phone="9999900001",
            password_hash=get_password_hash("password123"),
            is_active=True,
            is_verified=True,
        )
        resident_user = User(
            company_id=company.id,
            role_id=resident_role.id,
            full_name="Test Resident",
            email="resident.p0@example.com",
            phone="9999900002",
            password_hash=get_password_hash("password123"),
            is_active=True,
            is_verified=True,
        )
        db.add_all([admin_user, resident_user])
        db.flush()

        prop = Property(
            company_id=company.id,
            name="Origin Deluxe PG",
            code="ORIGIN_DLX",
            address_line1="100 Outer Ring Road",
            pincode="560103",
            is_active=True,
        )
        db.add(prop)
        db.flush()

        admin_token = create_access_token(
            str(admin_user.id),
            {"role": "SUPER_ADMIN", "company_id": str(company.id)},
        )
        resident_token = create_access_token(
            str(resident_user.id),
            {"role": "RESIDENT", "company_id": str(company.id)},
        )

        db.commit()

        return {
            "company_id": company.id,
            "property_id": prop.id,
            "admin_headers": {"Authorization": f"Bearer {admin_token}"},
            "resident_headers": {"Authorization": f"Bearer {resident_token}"},
            "resident_user_id": resident_user.id,
        }
    finally:
        db.close()


def test_delete_empty_room_success(client: TestClient, test_setup):
    """An empty room without historical records is permanently deleted."""
    session_factory = client.app.state.testing_session
    db = session_factory()
    prop_id = test_setup["property_id"]

    room = Room(
        property_id=prop_id,
        room_number="901",
        floor_number=9,
        room_type="SINGLE",
        base_monthly_rent=10000.0,
        deposit_amount=20000.0,
        is_active=True,
    )
    db.add(room)
    db.flush()

    bed = Bed(
        property_id=prop_id,
        room_id=room.id,
        bed_number="901-A",
        status="AVAILABLE",
        is_active=True,
        is_deleted=False,
    )
    db.add(bed)
    db.commit()
    room_id = room.id
    db.close()

    res = client.delete(f"/api/v1/rooms/{room_id}", headers=test_setup["admin_headers"])
    assert res.status_code == 200, res.text
    data = res.json()
    assert data["success"] is True
    assert data["data"]["status"] == "DELETED"

    # Verify room is permanently removed from DB
    db2 = session_factory()
    assert db2.get(Room, room_id) is None
    db2.close()


def test_delete_room_occupied_by_resident_rejected(client: TestClient, test_setup):
    """Deleting a room currently occupied by an active resident returns 400 Bad Request."""
    session_factory = client.app.state.testing_session
    db = session_factory()
    prop_id = test_setup["property_id"]

    room = Room(
        property_id=prop_id,
        room_number="902",
        floor_number=9,
        room_type="SINGLE",
        base_monthly_rent=10000.0,
        is_active=True,
    )
    db.add(room)
    db.flush()

    bed = Bed(
        property_id=prop_id,
        room_id=room.id,
        bed_number="902-A",
        status="OCCUPIED",
        is_active=True,
        is_deleted=False,
    )
    db.add(bed)
    db.flush()

    resident = Resident(
        property_id=prop_id,
        user_id=test_setup["resident_user_id"],
        room_id=room.id,
        bed_id=bed.id,
        full_name="Active Occupant",
        phone="9999900002",
        status="ACTIVE",
        check_in_date=date.today(),
    )
    db.add(resident)
    db.commit()
    room_id = room.id
    db.close()

    res = client.delete(f"/api/v1/rooms/{room_id}", headers=test_setup["admin_headers"])
    assert res.status_code == 400, res.text
    assert "currently occupied" in res.text.lower()


def test_delete_room_with_historical_resident_soft_deactivates(client: TestClient, test_setup):
    """A room with past (CHECKED_OUT) resident history is deactivated (soft deleted), not hard deleted."""
    session_factory = client.app.state.testing_session
    db = session_factory()
    prop_id = test_setup["property_id"]

    room = Room(
        property_id=prop_id,
        room_number="903",
        floor_number=9,
        room_type="SINGLE",
        base_monthly_rent=10000.0,
        is_active=True,
    )
    db.add(room)
    db.flush()

    bed = Bed(
        property_id=prop_id,
        room_id=room.id,
        bed_number="903-A",
        status="AVAILABLE",
        is_active=True,
        is_deleted=False,
    )
    db.add(bed)
    db.flush()

    past_resident = Resident(
        property_id=prop_id,
        user_id=test_setup["resident_user_id"],
        room_id=room.id,
        bed_id=bed.id,
        full_name="Past Occupant",
        phone="9999900002",
        status="CHECKED_OUT",
        check_in_date=date(2025, 1, 1),
        actual_check_out_date=date(2025, 6, 1),
    )
    db.add(past_resident)
    db.commit()
    room_id = room.id
    db.close()

    res = client.delete(f"/api/v1/rooms/{room_id}", headers=test_setup["admin_headers"])
    assert res.status_code == 200, res.text
    data = res.json()
    assert data["success"] is True
    assert data["data"]["status"] == "DEACTIVATED"

    # Verify room is NOT permanently deleted, but soft-deactivated
    db2 = session_factory()
    r = db2.get(Room, room_id)
    assert r is not None
    assert r.is_active is False
    b = db2.scalar(sa.select(Bed).where(Bed.room_id == room_id))
    assert b.is_deleted is True
    assert b.is_active is False
    db2.close()


def test_delete_room_permissions(client: TestClient, test_setup):
    """Residents cannot delete rooms; returns 403 Forbidden."""
    room_id = uuid.uuid4()
    res = client.delete(f"/api/v1/rooms/{room_id}", headers=test_setup["resident_headers"])
    assert res.status_code == 403


def test_rooms_floor_wise_property_alias(client: TestClient, test_setup):
    """GET /api/v1/rooms/property/{id}/floors alias route returns floor-wise grouping."""
    prop_id = str(test_setup["property_id"])
    res = client.get(f"/api/v1/rooms/property/{prop_id}/floors", headers=test_setup["admin_headers"])
    assert res.status_code == 200, res.text
    data = res.json()
    assert data["success"] is True
    assert "floors" in data["data"]


def test_residents_onboard_alias(client: TestClient, test_setup):
    """POST /api/v1/residents/onboard alias successfully onboards a resident."""
    prop_id = str(test_setup["property_id"])
    payload = {
        "property_id": prop_id,
        "full_name": "Alias Onboarded Resident",
        "phone": "9876501234",
        "email": "alias.onboard@example.com",
        "monthly_rent": 9000.0,
        "security_deposit": 18000.0,
    }
    res = client.post("/api/v1/residents/onboard", json=payload, headers=test_setup["admin_headers"])
    assert res.status_code == 201, res.text
    data = res.json()
    assert data["success"] is True
    assert data["data"]["full_name"] == "Alias Onboarded Resident"


def test_food_menus_property_weekly_alias(client: TestClient, test_setup):
    """GET /api/v1/food-menus/property/{id}/weekly alias returns menu items."""
    prop_id = str(test_setup["property_id"])
    res = client.get(f"/api/v1/food-menus/property/{prop_id}/weekly", headers=test_setup["admin_headers"])
    assert res.status_code == 200, res.text
    data = res.json()
    assert data["success"] is True
    assert isinstance(data["data"], list)
