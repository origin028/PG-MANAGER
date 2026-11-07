from datetime import date

from app.core.security import create_access_token, get_password_hash
from app.models.bed import Bed
from app.models.property import Company, Property
from app.models.resident import Resident
from app.models.role import Role
from app.models.room import Room
from app.models.user import User


def _add_user(db, company_id, role_id, number):
    user = User(
        company_id=company_id,
        role_id=role_id,
        email=f"user-{number}@example.test",
        phone=f"9000000{number:03d}",
        full_name=f"User {number}",
        password_hash=get_password_hash("not-used"),
    )
    db.add(user)
    db.flush()
    return user


def _seed_report_data(session_factory):
    db = session_factory()
    try:
        company = Company(name="Acme PG", code="ACME")
        role = Role(name="SUPER_ADMIN", display_name="Super admin")
        db.add_all((company, role))
        db.flush()
        admin = _add_user(db, company.id, role.id, 1)

        zero_bed_property = Property(company_id=company.id, name="Zero", code="ZERO", address_line1="0 Main St", pincode="560000")
        available_property = Property(company_id=company.id, name="Available", code="AVAILABLE", address_line1="1 Main St", pincode="560001")
        occupied_property = Property(company_id=company.id, name="Occupied", code="OCCUPIED", address_line1="2 Main St", pincode="560002")
        other_property = Property(company_id=company.id, name="Other", code="OTHER", address_line1="3 Main St", pincode="560003")
        db.add_all((zero_bed_property, available_property, occupied_property, other_property))
        db.flush()

        available_room = Room(property_id=available_property.id, room_number="101")
        occupied_room = Room(property_id=occupied_property.id, room_number="201")
        other_room = Room(property_id=other_property.id, room_number="301")
        db.add_all((available_room, occupied_room, other_room))
        db.flush()

        available_beds = [Bed(room_id=available_room.id, bed_number=str(number)) for number in range(1, 3)]
        occupied_beds = [Bed(room_id=occupied_room.id, bed_number=str(number)) for number in range(1, 5)]
        other_bed = Bed(room_id=other_room.id, bed_number="1")
        db.add_all([*available_beds, *occupied_beds, other_bed])
        db.flush()

        # ACTIVE and NOTICE_PERIOD residents occupy beds; CHECKED_OUT does not.
        for number, (bed, resident_status) in enumerate(
            ((occupied_beds[0], "ACTIVE"), (occupied_beds[1], "NOTICE_PERIOD"), (occupied_beds[2], "CHECKED_OUT")),
            start=2,
        ):
            user = _add_user(db, company.id, role.id, number)
            db.add(Resident(
                user_id=user.id, property_id=occupied_property.id, room_id=occupied_room.id,
                bed_id=bed.id, check_in_date=date.today(), status=resident_status,
            ))

        # This invalid cross-property pairing is possible with the current
        # schema; the report must not count it for either property.
        cross_property_user = _add_user(db, company.id, role.id, 5)
        db.add(Resident(
            user_id=cross_property_user.id, property_id=occupied_property.id,
            room_id=occupied_room.id, bed_id=other_bed.id, check_in_date=date.today(), status="ACTIVE",
        ))
        db.commit()
        token = create_access_token(str(admin.id), {"role": role.name, "company_id": str(company.id)})
        return {"zero": zero_bed_property.id, "available": available_property.id,
                "occupied": occupied_property.id, "other": other_property.id, "token": token}
    finally:
        db.close()


def _get_occupancy(client, property_id, token):
    response = client.get(
        f"/api/v1/reports/occupancy?property_id={property_id}",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 200
    return response.json()["data"]


def test_occupancy_report_handles_zero_and_available_beds(client):
    from app.main import app
    data = _seed_report_data(app.state.testing_session)

    assert _get_occupancy(client, data["zero"], data["token"]) == {
        "property_id": str(data["zero"]), "total_beds": 0, "occupied_beds": 0,
        "available_beds": 0, "occupancy_rate_percent": 0.0,
    }
    available = _get_occupancy(client, data["available"], data["token"])
    assert available["total_beds"] == 2
    assert available["occupied_beds"] == 0
    assert available["available_beds"] == 2


def test_occupancy_report_counts_active_and_notice_period_only(client):
    from app.main import app
    data = _seed_report_data(app.state.testing_session)

    assert _get_occupancy(client, data["occupied"], data["token"]) == {
        "property_id": str(data["occupied"]), "total_beds": 4, "occupied_beds": 2,
        "available_beds": 2, "occupancy_rate_percent": 50.0,
    }


def test_occupancy_report_excludes_cross_property_bed_assignment(client):
    from app.main import app
    data = _seed_report_data(app.state.testing_session)

    other = _get_occupancy(client, data["other"], data["token"])
    assert other["total_beds"] == 1
    assert other["occupied_beds"] == 0
