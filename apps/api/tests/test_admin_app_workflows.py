import secrets
import uuid
import pytest
from fastapi.testclient import TestClient

from app.core.config import settings


def _register_and_login_admin(client: TestClient) -> dict:
    unique = secrets.token_hex(4)
    email = f"admin_{unique}@originpg.com"
    password = "AdminValidPassword@123"
    super_key = settings.ADMIN_REGISTRATION_SUPER_KEY or "ORIGIN_PG_SUPER_KEY_2026"

    reg = client.post(
        "/api/v1/auth/admin/register",
        json={
            "business_name": f"Origin Test PG {unique}",
            "email": email,
            "password": password,
            "confirm_password": password,
            "super_key": super_key,
        },
    )
    assert reg.status_code == 201

    login = client.post(
        "/api/v1/auth/admin/login",
        json={"email": email, "password": password},
    )
    assert login.status_code == 200
    token = login.json()["data"]["access_token"]
    return {"Authorization": f"Bearer {token}"}


def test_property_creation_with_aliases_and_auto_code(client: TestClient):
    """Verify that property creation works with 'address' instead of 'address_line1' and auto-generates code."""
    headers = _register_and_login_admin(client)
    payload = {
        "name": f"Origin Test Heights {uuid.uuid4().hex[:6]}",
        "address": "456 Outer Ring Road, Marathahalli",
        "city": "Bengaluru",
        "pincode": "560037",
        "total_floors": 3,
        "property_type": "Boys",
    }
    response = client.post("/api/v1/properties", json=payload, headers=headers)
    assert response.status_code == 201
    data = response.json()
    assert data["success"] is True
    assert data["data"]["name"] == payload["name"]
    assert data["data"]["address_line1"] == payload["address"]
    assert data["data"]["pincode"] == "560037"
    assert data["data"]["code"].startswith("ORIGIN")


def test_lead_conversion_workflow(client: TestClient):
    """Verify complete lead creation and atomic conversion to an onboarded resident."""
    headers = _register_and_login_admin(client)

    # 1. Create property
    prop_res = client.post(
        "/api/v1/properties",
        json={
            "name": f"Origin Lead Prop {uuid.uuid4().hex[:6]}",
            "address": "123 Indiranagar 100ft Road",
            "city": "Bengaluru",
            "pincode": "560038",
        },
        headers=headers,
    )
    assert prop_res.status_code == 201
    prop_id = prop_res.json()["data"]["id"]

    # 2. Create room
    room_res = client.post(
        "/api/v1/rooms",
        json={
            "property_id": prop_id,
            "room_number": "101",
            "floor_number": 1,
            "room_type": "DOUBLE",
            "max_occupancy": 2,
        },
        headers=headers,
    )
    assert room_res.status_code == 201
    room_id = room_res.json()["data"]["id"]

    # 3. Create bed
    bed_res = client.post(
        "/api/v1/beds",
        json={
            "room_id": room_id,
            "bed_number": "Bed A",
            "monthly_rent": 8500.0,
        },
        headers=headers,
    )
    assert bed_res.status_code == 201
    bed_id = bed_res.json()["data"]["id"]

    # 4. Create Lead
    phone = f"98765{secrets.randbelow(90000) + 10000}"
    lead_payload = {
        "property_id": prop_id,
        "name": "Arun Kumar",
        "phone": phone,
        "email": f"arun_{phone}@example.com",
        "source": "WALK_IN",
        "requirement": "Single bed near window",
    }
    lead_res = client.post("/api/v1/leads", json=lead_payload, headers=headers)
    assert lead_res.status_code == 201
    lead_id = lead_res.json()["data"]["id"]
    assert lead_res.json()["data"]["status"] == "NEW"

    # 5. Convert Lead to Resident with room & bed allocation
    convert_payload = {
        "room_id": room_id,
        "bed_id": bed_id,
        "monthly_rent": 7500.0,
        "security_deposit": 15000.0,
        "notes": "Converted on spot with full deposit promise",
    }
    conv_res = client.post(f"/api/v1/leads/{lead_id}/convert", json=convert_payload, headers=headers)
    print("CONV RES:", conv_res.status_code, conv_res.json())
    assert conv_res.status_code == 200
    conv_data = conv_res.json()
    assert conv_data["success"] is True
    assert conv_data["data"]["status"] == "CONVERTED"
    assert conv_data["data"]["resident_id"] is not None

    # 6. Verify double conversion is prevented
    double_res = client.post(f"/api/v1/leads/{lead_id}/convert", json=convert_payload, headers=headers)
    assert double_res.status_code == 409


def test_complaint_assignment_and_resolution(client: TestClient):
    """Verify staff creation, complaint assignment, and resolution."""
    headers = _register_and_login_admin(client)

    # 1. Create property
    prop_res = client.post(
        "/api/v1/properties",
        json={
            "name": f"Origin Complaint Prop {uuid.uuid4().hex[:6]}",
            "address": "789 Koramangala 5th Block",
            "city": "Bengaluru",
            "pincode": "560034",
        },
        headers=headers,
    )
    assert prop_res.status_code == 201
    prop_id = prop_res.json()["data"]["id"]

    # 2. Create Staff
    phone = f"91234{secrets.randbelow(90000) + 10000}"
    staff_payload = {
        "property_id": prop_id,
        "name": "Ramesh Electrician",
        "role": "ELECTRICIAN",
        "phone": phone,
        "salary": 18000.0,
    }
    staff_res = client.post("/api/v1/staff", json=staff_payload, headers=headers)
    assert staff_res.status_code == 201
    staff_id = staff_res.json()["data"]["id"]

    # 3. Onboard a resident
    res_phone = f"97777{secrets.randbelow(90000) + 10000}"
    onboard_res = client.post(
        "/api/v1/residents",
        json={
            "property_id": prop_id,
            "full_name": "Suresh Raina",
            "phone": res_phone,
            "email": f"suresh_{res_phone}@example.com",
            "monthly_rent": 8000.0,
            "security_deposit": 16000.0,
        },
        headers=headers,
    )
    assert onboard_res.status_code == 201
    resident_id = onboard_res.json()["data"]["id"]

    # 4. Create Complaint in DB
    from app.models.complaint import Complaint
    db_session = client.app.state.testing_session()
    complaint = Complaint(
        property_id=uuid.UUID(prop_id),
        resident_id=uuid.UUID(resident_id),
        category="ELECTRICAL",
        title="Geyser not heating in Room 102",
        description="Resident reported water is cold",
        priority="HIGH",
        status="PENDING",
    )
    db_session.add(complaint)
    db_session.commit()
    db_session.refresh(complaint)
    complaint_id = str(complaint.id)
    db_session.close()

    # 5. Assign Staff
    assign_res = client.post(f"/api/v1/complaints/{complaint_id}/assign", json={"staff_id": staff_id}, headers=headers)
    assert assign_res.status_code == 200

    # 6. Resolve Complaint
    resolve_res = client.post(f"/api/v1/complaints/{complaint_id}/resolve", json={"resolution_notes": "Replaced thermostat"}, headers=headers)
    assert resolve_res.status_code == 200
    assert resolve_res.json()["data"]["status"] == "RESOLVED"
