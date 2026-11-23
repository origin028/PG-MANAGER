import uuid
from datetime import date
import pytest
from fastapi.testclient import TestClient

from app.core.security import create_access_token, get_password_hash
from app.main import app
from app.models.announcement import Announcement
from app.models.property import Company, Property
from app.models.resident import Resident
from app.models.role import Role
from app.models.room import Room
from app.models.bed import Bed
from app.models.user import User


@pytest.fixture
def db_session(client):
    session = app.state.testing_session()
    try:
        yield session
    finally:
        session.close()


@pytest.fixture
def announcement_setup(client, db_session):
    company = db_session.query(Company).filter_by(code="ANN_CORP").first()
    if not company:
        company = Company(
            name="Announcement Corp",
            code="ANN_CORP",
            email="ann@corp.com",
            phone="9191919191",
            subscription_plan="ENTERPRISE",
            subscription_status="ACTIVE",
        )
        db_session.add(company)
        db_session.flush()

    admin_role = db_session.query(Role).filter_by(name="SUPER_ADMIN").first()
    if not admin_role:
        admin_role = Role(name="SUPER_ADMIN", display_name="Super Admin", is_system_role=True, permissions=["*"])
        db_session.add(admin_role)
        db_session.flush()

    resident_role = db_session.query(Role).filter_by(name="RESIDENT").first()
    if not resident_role:
        resident_role = Role(name="RESIDENT", display_name="Resident", is_system_role=True, permissions=["resident:*"])
        db_session.add(resident_role)
        db_session.flush()

    prop1 = Property(
        company_id=company.id,
        name="Electronic City PG",
        code=f"PROP-ANN-{uuid.uuid4().hex[:6]}",
        address_line1="123 Info Way",
        city="Bangalore",
        state="Karnataka",
        pincode="560100",
    )
    prop2 = Property(
        company_id=company.id,
        name="Whitefield PG",
        code=f"PROP-ANN-{uuid.uuid4().hex[:6]}",
        address_line1="456 Tech Park",
        city="Bangalore",
        state="Karnataka",
        pincode="560066",
    )
    db_session.add_all([prop1, prop2])
    db_session.flush()

    admin_user = User(
        company_id=company.id,
        role_id=admin_role.id,
        email=f"admin_{uuid.uuid4().hex[:6]}@example.com",
        phone=f"999{uuid.uuid4().int % 10000000:07d}",
        password_hash=get_password_hash("AdminPass123!"),
        full_name="Announcement Admin",
        is_active=True,
    )
    res_user = User(
        company_id=company.id,
        role_id=resident_role.id,
        email=f"res_{uuid.uuid4().hex[:6]}@example.com",
        phone=f"888{uuid.uuid4().int % 10000000:07d}",
        password_hash=get_password_hash("ResPass123!"),
        full_name="John Resident",
        is_active=True,
    )
    db_session.add_all([admin_user, res_user])
    db_session.flush()

    room1 = Room(property_id=prop1.id, room_number="101", floor=1, room_type="DOUBLE", base_rent=8000)
    db_session.add(room1)
    db_session.flush()

    bed1 = Bed(room_id=room1.id, bed_number="A", status="OCCUPIED")
    db_session.add(bed1)
    db_session.flush()

    resident_profile = Resident(
        property_id=prop1.id,
        room_id=room1.id,
        bed_id=bed1.id,
        user_id=res_user.id,
        check_in_date=date.today(),
        status="ACTIVE",
    )
    db_session.add(resident_profile)
    db_session.commit()

    admin_token = create_access_token(str(admin_user.id), {"role": "SUPER_ADMIN", "company_id": str(company.id)})
    resident_token = create_access_token(str(res_user.id), {"role": "RESIDENT", "company_id": str(company.id)})

    return {
        "admin_token": admin_token,
        "resident_token": resident_token,
        "prop1_id": str(prop1.id),
        "prop2_id": str(prop2.id),
        "company_id": str(company.id),
    }


def test_announcement_crud_and_scoping(client: TestClient, announcement_setup):
    admin_headers = {"Authorization": f"Bearer {announcement_setup['admin_token']}"}
    res_headers = {"Authorization": f"Bearer {announcement_setup['resident_token']}"}
    prop1_id = announcement_setup["prop1_id"]
    prop2_id = announcement_setup["prop2_id"]

    # 1. Create announcement for Property 1
    create_res = client.post(
        "/api/v1/announcements",
        headers=admin_headers,
        json={
            "title": "Water Tank Cleaning",
            "content": "Water will be turned off between 10 AM and 2 PM tomorrow.",
            "property_id": prop1_id,
            "is_active": True,
        },
    )
    assert create_res.status_code == 201
    ann1 = create_res.json()["data"]
    assert ann1["title"] == "Water Tank Cleaning"
    assert ann1["property_name"] == "Electronic City PG"
    ann1_id = ann1["id"]

    # 2. Create announcement for Property 2
    create_res2 = client.post(
        "/api/v1/announcements",
        headers=admin_headers,
        json={
            "title": "Whitefield Wi-Fi Maintenance",
            "content": "Wi-Fi speeds will be enhanced this evening.",
            "property_id": prop2_id,
            "is_active": True,
        },
    )
    assert create_res2.status_code == 201
    ann2_id = create_res2.json()["data"]["id"]

    # 3. Create company-wide announcement
    create_res_all = client.post(
        "/api/v1/announcements",
        headers=admin_headers,
        json={
            "title": "New Year Holiday Notice",
            "content": "Office will remain closed on Jan 1st.",
            "property_id": None,
            "is_active": True,
        },
    )
    assert create_res_all.status_code == 201
    assert create_res_all.json()["data"]["property_name"] == "All Properties"

    # 4. Admin lists all announcements
    list_res = client.get("/api/v1/announcements", headers=admin_headers)
    assert list_res.status_code == 200
    all_anns = list_res.json()["data"]
    assert len(all_anns) >= 3

    # 5. Resident (assigned to Prop 1) queries announcements via /api/v1/announcements/resident
    res_anns = client.get("/api/v1/announcements/resident", headers=res_headers)
    assert res_anns.status_code == 200
    resident_list = res_anns.json()["data"]
    # Should see Water Tank Cleaning and New Year Holiday, but NOT Whitefield maintenance
    titles = [a["title"] for a in resident_list]
    assert "Water Tank Cleaning" in titles
    assert "New Year Holiday Notice" in titles
    assert "Whitefield Wi-Fi Maintenance" not in titles

    # 6. Also test the alias endpoint /api/v1/residents/announcements
    res_anns_alias = client.get("/api/v1/residents/announcements", headers=res_headers)
    assert res_anns_alias.status_code == 200
    alias_titles = [a["title"] for a in res_anns_alias.json()["data"]]
    assert "Water Tank Cleaning" in alias_titles
    assert "Whitefield Wi-Fi Maintenance" not in alias_titles

    # 7. Update announcement
    update_res = client.put(
        f"/api/v1/announcements/{ann1_id}",
        headers=admin_headers,
        json={"title": "Water Tank Cleaning [Rescheduled]", "content": "Rescheduled to 3 PM."},
    )
    assert update_res.status_code == 200
    assert update_res.json()["data"]["title"] == "Water Tank Cleaning [Rescheduled]"

    # 8. Deactivate announcement
    status_res = client.patch(
        f"/api/v1/announcements/{ann1_id}/status",
        headers=admin_headers,
        json={"is_active": False},
    )
    assert status_res.status_code == 200
    assert status_res.json()["data"]["is_active"] is False

    # 9. Inactive announcement should no longer appear for resident
    res_after_deactivate = client.get("/api/v1/announcements/resident", headers=res_headers)
    active_titles = [a["title"] for a in res_after_deactivate.json()["data"]]
    assert "Water Tank Cleaning [Rescheduled]" not in active_titles

    # 10. Delete announcement
    del_res = client.delete(f"/api/v1/announcements/{ann1_id}", headers=admin_headers)
    assert del_res.status_code == 200

    # 11. Verify not found
    get_del = client.get(f"/api/v1/announcements/{ann1_id}", headers=admin_headers)
    assert get_del.status_code == 404
