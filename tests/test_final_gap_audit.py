"""Focused regression tests for the final backend audit gaps.

Covers:
- PDF receipt generation and authorization
- Property dashboard metrics and scoping
- Room-scoped bed status transition rules
- Initial rent invoice generation on admission / check-in
- OTP registration, expiry, attempt limits and e-mail state reporting
- Invoice adjustment and partial/full payment transitions
- Complaints, expenses and staff scoping, validation and RBAC
"""

import hashlib
import uuid
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal

import sqlalchemy as sa

from app.models.otp import OtpVerification
from app.models.role import Role
from app.models.user import User
from tests.test_roles_and_scopes import get_token


def _auth(token):
    return {"Authorization": f"Bearer {token}"}


def _unique_phone():
    return f"9{uuid.uuid4().int % 10**9:09d}"


def _create_property(client, token, prefix="AUD"):
    code = f"{prefix}-{uuid.uuid4().hex[:8].upper()}"
    resp = client.post(
        "/api/v1/properties",
        headers=_auth(token),
        json={
            "name": f"Audit Property {code}",
            "code": code,
            "property_type": "CO_LIVING",
            "address_line1": "1 Audit Street",
            "city": "Bangalore",
            "state": "Karnataka",
            "pincode": "560001",
        },
    )
    assert resp.status_code == 201, resp.text
    return resp.json()["data"]["id"]


def _create_room(client, token, property_id, rent=12000.0):
    resp = client.post(
        f"/api/v1/properties/{property_id}/rooms",
        headers=_auth(token),
        json={
            "room_number": f"R{uuid.uuid4().hex[:6].upper()}",
            "floor_number": 1,
            "room_type": "SINGLE",
            "base_monthly_rent": rent,
            "deposit_amount": rent,
        },
    )
    assert resp.status_code == 201, resp.text
    return resp.json()["data"]["id"]


def _create_bed(client, token, room_id, rent=12000.0):
    resp = client.post(
        f"/api/v1/rooms/{room_id}/beds",
        headers=_auth(token),
        json={
            "bed_number": f"B{uuid.uuid4().hex[:4].upper()}",
            "monthly_rent": rent,
        },
    )
    assert resp.status_code == 201, resp.text
    return resp.json()["data"]["id"]


def _create_resident(
    client,
    token,
    property_id,
    *,
    bed_id=None,
    phone=None,
    rent=12000.0,
    check_in=False,
    name="Audit Resident",
    expect=201,
):
    phone = phone or _unique_phone()
    payload = {
        "property_id": property_id,
        "full_name": name,
        "phone": phone,
        "email": f"{phone}@example.com",
        "emergency_contact_name": "Emergency Contact",
        "emergency_contact_phone": "9880000000",
        "monthly_rent": rent,
        "security_deposit": rent * 2,
        "id_proof_type": "AADHAAR",
        "id_proof_number": "1234 5678 9012",
        "bed_id": bed_id,
        "check_in_immediately": check_in,
    }
    resp = client.post("/api/v1/residents", headers=_auth(token), json=payload)
    assert resp.status_code == expect, resp.text
    return resp.json()["data"] if expect == 201 else resp


def _invoices_for(client, token, resident_id):
    resp = client.get(
        f"/api/v1/invoices?resident_id={resident_id}",
        headers=_auth(token),
    )
    assert resp.status_code == 200, resp.text
    return resp.json()["data"]


def test_receipt_pdf_generation_and_authorization(client):
    admin = get_token(client, "admin@originpg.com", "Admin@123456")
    prop_id = _create_property(client, admin, "RCP")
    room_id = _create_room(client, admin, prop_id, rent=11000.0)
    bed_id = _create_bed(client, admin, room_id, rent=11000.0)
    resident = _create_resident(
        client, admin, prop_id, bed_id=bed_id, rent=11000.0, check_in=True
    )

    invoices = _invoices_for(client, admin, resident["id"])
    assert len(invoices) == 1
    invoice = invoices[0]
    assert invoice["invoice_type"] == "RENT"
    assert invoice["status"] == "ISSUED"

    resp = client.get(
        f"/api/v1/invoices/{invoice['id']}/receipt", headers=_auth(admin)
    )
    assert resp.status_code == 200, resp.text
    assert resp.headers["content-type"].startswith("application/pdf")
    assert resp.headers["content-disposition"].startswith("attachment;")
    assert invoice["invoice_number"] in resp.headers["content-disposition"]
    assert int(resp.headers["content-length"]) == len(resp.content)
    assert resp.content.startswith(b"%PDF-")
    assert b"%%EOF" in resp.content

    # A manager who is not assigned to this property must not download it.
    manager = get_token(client, "manager@originpg.com", "Manager@123456")
    forbidden = client.get(
        f"/api/v1/invoices/{invoice['id']}/receipt", headers=_auth(manager)
    )
    assert forbidden.status_code == 403

    # Unauthenticated access is rejected.
    unauthenticated = client.get(f"/api/v1/invoices/{invoice['id']}/receipt")
    assert unauthenticated.status_code in (401, 403)


def test_property_dashboard_metrics_and_scoping(client):
    admin = get_token(client, "admin@originpg.com", "Admin@123456")
    prop_id = _create_property(client, admin, "DSH")
    room_a = _create_room(client, admin, prop_id, rent=10000.0)
    bed_a = _create_bed(client, admin, room_a, rent=10000.0)
    room_b = _create_room(client, admin, prop_id, rent=8000.0)
    bed_b = _create_bed(client, admin, room_b, rent=8000.0)

    resident_a = _create_resident(
        client, admin, prop_id, bed_id=bed_a, rent=10000.0, check_in=True
    )
    _create_resident(
        client, admin, prop_id, bed_id=bed_b, rent=8000.0, check_in=True
    )

    resp = client.get(
        f"/api/v1/properties/{prop_id}/dashboard", headers=_auth(admin)
    )
    assert resp.status_code == 200, resp.text
    data = resp.json()["data"]
    assert data["total_tenants"] == 2
    assert data["unpaid_tenants"] == 2
    assert data["available_beds"] == 0
    assert data["revenue_this_month"] == 0.0
    assert data["revenue_growth_percentage"] == 0.0

    invoice_a = _invoices_for(client, admin, resident_a["id"])[0]
    payment = client.post(
        f"/api/v1/invoices/{invoice_a['id']}/record-payment",
        headers=_auth(admin),
        json={
            "amount": "10000.00",
            "payment_method": "Cash",
            "date": date.today().isoformat(),
        },
    )
    assert payment.status_code == 200, payment.text

    resp = client.get(
        f"/api/v1/properties/{prop_id}/dashboard", headers=_auth(admin)
    )
    data = resp.json()["data"]
    assert data["unpaid_tenants"] == 1
    assert data["revenue_this_month"] == 10000.0
    # Growth is only defined against a non-zero previous month; 0.0 avoids a
    # division-by-zero baseline while revenue_this_month still moves.
    assert data["revenue_growth_percentage"] == 0.0
    assert data["total_tenants"] == 2

    # Managers and staff only see assigned properties.
    manager = get_token(client, "manager@originpg.com", "Manager@123456")
    staff = get_token(client, "staff@originpg.com", "Staff@123456")
    resident_user = get_token(
        client, "resident@originpg.com", "Resident@123456", client_type="resident_mobile"
    )
    assert (
        client.get(
            f"/api/v1/properties/{prop_id}/dashboard", headers=_auth(manager)
        ).status_code
        == 403
    )
    assert (
        client.get(
            f"/api/v1/properties/{prop_id}/dashboard", headers=_auth(staff)
        ).status_code
        == 403
    )
    assert (
        client.get(
            f"/api/v1/properties/{prop_id}/dashboard", headers=_auth(resident_user)
        ).status_code
        == 403
    )


def test_bed_status_transitions_via_room_route(client):
    admin = get_token(client, "admin@originpg.com", "Admin@123456")
    prop_id = _create_property(client, admin, "BED")
    room_id = _create_room(client, admin, prop_id)
    other_room_id = _create_room(client, admin, prop_id)
    bed_id = _create_bed(client, admin, room_id)

    # Valid non-occupancy transition.
    resp = client.put(
        f"/api/v1/rooms/{room_id}/beds/{bed_id}",
        headers=_auth(admin),
        json={"status": "MAINTENANCE"},
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["data"]["status"] == "MAINTENANCE"

    resp = client.put(
        f"/api/v1/rooms/{room_id}/beds/{bed_id}",
        headers=_auth(admin),
        json={"status": "AVAILABLE"},
    )
    assert resp.status_code == 200, resp.text

    # Occupancy cannot be created manually.
    resp = client.put(
        f"/api/v1/rooms/{room_id}/beds/{bed_id}",
        headers=_auth(admin),
        json={"status": "OCCUPIED"},
    )
    assert resp.status_code == 422

    # The bed must belong to the room in the URL.
    resp = client.put(
        f"/api/v1/rooms/{other_room_id}/beds/{bed_id}",
        headers=_auth(admin),
        json={"status": "MAINTENANCE"},
    )
    assert resp.status_code == 404

    # Once a resident occupies the bed, status cannot be freed manually.
    resident = _create_resident(
        client, admin, prop_id, bed_id=bed_id, check_in=True
    )
    assert resident["status"] == "ACTIVE"
    resp = client.put(
        f"/api/v1/rooms/{room_id}/beds/{bed_id}",
        headers=_auth(admin),
        json={"status": "MAINTENANCE"},
    )
    assert resp.status_code == 422

    # Staff may not touch beds outside their assigned properties.
    staff = get_token(client, "staff@originpg.com", "Staff@123456")
    resp = client.put(
        f"/api/v1/rooms/{room_id}/beds/{bed_id}",
        headers=_auth(staff),
        json={"status": "MAINTENANCE"},
    )
    assert resp.status_code == 403


def test_checkin_generates_single_initial_rent_invoice_and_blocks_duplicate_bed(client):
    admin = get_token(client, "admin@originpg.com", "Admin@123456")
    prop_id = _create_property(client, admin, "INV")
    room_id = _create_room(client, admin, prop_id, rent=15000.0)
    bed_id = _create_bed(client, admin, room_id, rent=15000.0)

    # Pending admission without a bed must not create an invoice.
    pending = _create_resident(
        client, admin, prop_id, rent=15000.0, check_in=False
    )
    assert pending["status"] == "PENDING"
    assert pending["check_in_date"] is None
    assert _invoices_for(client, admin, pending["id"]) == []

    # Check-in allocates the bed and generates exactly one rent invoice.
    resp = client.post(
        f"/api/v1/residents/{pending['id']}/check-in",
        headers=_auth(admin),
        json={"bed_id": bed_id},
    )
    assert resp.status_code == 200, resp.text
    checked_in = resp.json()["data"]
    assert checked_in["status"] == "ACTIVE"
    assert checked_in["bed_id"] == bed_id
    assert checked_in["room_id"] == room_id
    assert checked_in["check_in_date"] == date.today().isoformat()

    invoices = _invoices_for(client, admin, pending["id"])
    assert len(invoices) == 1
    assert invoices[0]["invoice_type"] == "RENT"
    assert invoices[0]["billing_month"] == date.today().strftime("%Y-%m")
    assert Decimal(str(invoices[0]["total_amount"])) == Decimal("15000.00")
    assert invoices[0]["status"] == "ISSUED"

    # Re-check-in is rejected and must not duplicate the invoice.
    resp = client.post(
        f"/api/v1/residents/{pending['id']}/check-in",
        headers=_auth(admin),
        json={"bed_id": bed_id},
    )
    assert resp.status_code == 409
    assert len(_invoices_for(client, admin, pending["id"])) == 1

    # Another resident cannot take the now-occupied bed.
    duplicate = _create_resident(
        client,
        admin,
        prop_id,
        bed_id=bed_id,
        rent=15000.0,
        check_in=True,
        expect=409,
    )
    assert duplicate.status_code == 409

    second_room = _create_room(client, admin, prop_id, rent=9000.0)
    second_bed = _create_bed(client, admin, second_room, rent=9000.0)
    second = _create_resident(
        client, admin, prop_id, bed_id=second_bed, rent=9000.0, check_in=True
    )
    assert second["status"] == "ACTIVE"
    assert len(_invoices_for(client, admin, second["id"])) == 1


def test_register_verify_otp_flow_and_email_state(client, db_session):
    email = f"owner-{uuid.uuid4().hex[:10]}@example.com"
    payload = {
        "business_name": "Audit PG",
        "email": email,
        "password": "StrongPass@123",
        "city": "Bangalore",
    }

    resp = client.post("/api/v1/auth/register", json=payload)
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["success"] is True
    assert body["data"]["email"] == email
    # SMTP is not configured in tests, so the response must not claim delivery.
    assert body["data"]["email_sent"] is False

    # Duplicate registration is rejected.
    assert client.post("/api/v1/auth/register", json=payload).status_code == 409

    user = db_session.scalar(sa.select(User).where(User.email == email))
    assert user is not None and user.is_active is False and user.is_verified is False

    # Login before verification is blocked.
    login = client.post(
        "/api/v1/auth/login",
        json={
            "identifier": email,
            "password": "StrongPass@123",
            "client_type": "admin_web",
        },
    )
    assert login.status_code == 401

    otp_record = db_session.scalar(
        sa.select(OtpVerification)
        .where(OtpVerification.email == email)
        .order_by(OtpVerification.created_at.desc())
    )
    assert otp_record is not None
    known_otp = "654321"
    otp_record.otp_hash = hashlib.sha256(known_otp.encode()).hexdigest()
    otp_record.attempts = 0
    db_session.commit()

    # Legacy "super_key" alias is still accepted.
    verify = client.post(
        "/api/v1/auth/verify-otp",
        json={"email": email, "super_key": known_otp},
    )
    assert verify.status_code == 200, verify.text
    assert verify.json()["data"]["is_verified"] is True

    db_session.refresh(user)
    db_session.refresh(otp_record)
    assert user.is_active is True and user.is_verified is True
    assert otp_record.is_used is True

    # The same code cannot be redeemed twice.
    assert (
        client.post(
            "/api/v1/auth/verify-otp",
            json={"email": email, "otp": known_otp},
        ).status_code
        == 401
    )

    login = client.post(
        "/api/v1/auth/login",
        json={
            "identifier": email,
            "password": "StrongPass@123",
            "client_type": "admin_web",
        },
    )
    assert login.status_code == 200, login.text


def test_otp_expiry_and_attempt_limits(client, db_session):
    short_pw = client.post(
        "/api/v1/auth/register",
        json={
            "business_name": "Short Password PG",
            "email": f"short-{uuid.uuid4().hex[:8]}@example.com",
            "password": "short7c",
            "city": "Bangalore",
        },
    )
    assert short_pw.status_code == 422

    # Expired OTP is rejected.
    expired_email = f"expired-{uuid.uuid4().hex[:10]}@example.com"
    assert (
        client.post(
            "/api/v1/auth/register",
            json={
                "business_name": "Expired OTP PG",
                "email": expired_email,
                "password": "StrongPass@123",
                "city": "Bangalore",
            },
        ).status_code
        == 200
    )
    expired_record = db_session.scalar(
        sa.select(OtpVerification)
        .where(OtpVerification.email == expired_email)
        .order_by(OtpVerification.created_at.desc())
    )
    known_otp = "111222"
    expired_record.otp_hash = hashlib.sha256(known_otp.encode()).hexdigest()
    expired_record.expires_at = datetime.now(timezone.utc) - timedelta(minutes=1)
    db_session.commit()

    resp = client.post(
        "/api/v1/auth/verify-otp",
        json={"email": expired_email, "otp": known_otp},
    )
    assert resp.status_code == 401
    expired_user = db_session.scalar(
        sa.select(User).where(User.email == expired_email)
    )
    db_session.refresh(expired_user)
    assert expired_user.is_active is False

    # Attempt limit is enforced and burns the code.
    limited_email = f"limited-{uuid.uuid4().hex[:10]}@example.com"
    assert (
        client.post(
            "/api/v1/auth/register",
            json={
                "business_name": "Attempt Limit PG",
                "email": limited_email,
                "password": "StrongPass@123",
                "city": "Bangalore",
            },
        ).status_code
        == 200
    )
    limited_record = db_session.scalar(
        sa.select(OtpVerification)
        .where(OtpVerification.email == limited_email)
        .order_by(OtpVerification.created_at.desc())
    )
    limited_record.otp_hash = hashlib.sha256(b"333444").hexdigest()
    limited_record.attempts = 0
    db_session.commit()

    for _ in range(5):
        attempt = client.post(
            "/api/v1/auth/verify-otp",
            json={"email": limited_email, "otp": "999999"},
        )
        assert attempt.status_code == 401

    db_session.refresh(limited_record)
    assert limited_record.is_used is True
    assert limited_record.attempts >= 5

    # Even the correct code cannot be used after the attempt limit.
    assert (
        client.post(
            "/api/v1/auth/verify-otp",
            json={"email": limited_email, "otp": "333444"},
        ).status_code
        == 401
    )
    limited_user = db_session.scalar(
        sa.select(User).where(User.email == limited_email)
    )
    db_session.refresh(limited_user)
    assert limited_user.is_active is False


def test_invoice_adjustment_and_payment_transitions(client):
    admin = get_token(client, "admin@originpg.com", "Admin@123456")
    prop_id = _create_property(client, admin, "ADJ")
    room_id = _create_room(client, admin, prop_id, rent=15000.0)
    bed_id = _create_bed(client, admin, room_id, rent=15000.0)
    resident = _create_resident(
        client, admin, prop_id, bed_id=bed_id, rent=15000.0, check_in=True
    )
    invoice = _invoices_for(client, admin, resident["id"])[0]
    invoice_id = invoice["id"]

    # Partial payment leaves the invoice partially paid.
    resp = client.post(
        f"/api/v1/invoices/{invoice_id}/record-payment",
        headers=_auth(admin),
        json={
            "amount": "5000.00",
            "payment_method": "upi",
            "date": date.today().isoformat(),
        },
    )
    assert resp.status_code == 200, resp.text
    assert Decimal(str(resp.json()["data"]["amount"])) == Decimal("5000.00")

    detail = client.get(f"/api/v1/invoices/{invoice_id}", headers=_auth(admin)).json()["data"]
    assert detail["status"] == "PARTIALLY_PAID"
    assert Decimal(str(detail["paid_amount"])) == Decimal("5000.00")
    assert Decimal(str(detail["balance_amount"])) == Decimal("10000.00")

    # Overpayment is rejected.
    over = client.post(
        f"/api/v1/invoices/{invoice_id}/record-payment",
        headers=_auth(admin),
        json={
            "amount": "20000.00",
            "payment_method": "Cash",
            "date": date.today().isoformat(),
        },
    )
    assert over.status_code == 409

    # Cannot adjust below already collected money.
    below_paid = client.put(
        f"/api/v1/invoices/{invoice_id}/adjust",
        headers=_auth(admin),
        json={"new_amount": "4000.00", "reason": "Too low"},
    )
    assert below_paid.status_code == 409

    # Valid adjustment recalculates the balance and keeps the invoice partial.
    adjusted = client.put(
        f"/api/v1/invoices/{invoice_id}/adjust",
        headers=_auth(admin),
        json={"new_amount": "20000.00", "reason": "Rent revision"},
    )
    assert adjusted.status_code == 200, adjusted.text
    adjusted_data = adjusted.json()["data"]
    assert Decimal(str(adjusted_data["total_amount"])) == Decimal("20000.00")
    assert Decimal(str(adjusted_data["paid_amount"])) == Decimal("5000.00")
    assert Decimal(str(adjusted_data["balance_amount"])) == Decimal("15000.00")
    assert adjusted_data["status"] == "PARTIALLY_PAID"

    # Short reason and staff role are rejected.
    assert (
        client.put(
            f"/api/v1/invoices/{invoice_id}/adjust",
            headers=_auth(admin),
            json={"new_amount": "21000.00", "reason": "x"},
        ).status_code
        == 422
    )
    staff = get_token(client, "staff@originpg.com", "Staff@123456")
    assert (
        client.put(
            f"/api/v1/invoices/{invoice_id}/adjust",
            headers=_auth(staff),
            json={"new_amount": "21000.00", "reason": "Not allowed"},
        ).status_code
        == 403
    )

    # Settling the remaining balance marks the invoice PAID.
    settle = client.post(
        f"/api/v1/invoices/{invoice_id}/record-payment",
        headers=_auth(admin),
        json={
            "amount": "15000.00",
            "payment_method": "Bank Transfer",
            "date": date.today().isoformat(),
        },
    )
    assert settle.status_code == 200, settle.text
    detail = client.get(f"/api/v1/invoices/{invoice_id}", headers=_auth(admin)).json()["data"]
    assert detail["status"] == "PAID"
    assert Decimal(str(detail["balance_amount"])) == Decimal("0.00")
    assert Decimal(str(detail["paid_amount"])) == Decimal("20000.00")
    assert len(detail["payments"]) == 2

    # No further payments are accepted on a settled invoice.
    again = client.post(
        f"/api/v1/invoices/{invoice_id}/record-payment",
        headers=_auth(admin),
        json={
            "amount": "100.00",
            "payment_method": "Cash",
            "date": date.today().isoformat(),
        },
    )
    assert again.status_code == 409


def test_complaints_scoping_workflow_and_rbac(client, db_session):
    admin = get_token(client, "admin@originpg.com", "Admin@123456")
    prop_id = _create_property(client, admin, "CMP")
    room_id = _create_room(client, admin, prop_id)
    bed_id = _create_bed(client, admin, room_id)

    resident_role = db_session.scalar(sa.select(Role).where(Role.name == "RESIDENT"))
    resident_phone = _unique_phone()
    resident_email = f"{resident_phone}@example.com"
    user_resp = client.post(
        "/api/v1/users",
        headers=_auth(admin),
        json={
            "full_name": "Complaint Resident",
            "email": resident_email,
            "phone": resident_phone,
            "password": "Resident@123456",
            "role_id": str(resident_role.id),
            "property_ids": [prop_id],
        },
    )
    assert user_resp.status_code == 201, user_resp.text

    resident = _create_resident(
        client,
        admin,
        prop_id,
        bed_id=bed_id,
        phone=resident_phone,
        check_in=True,
        name="Complaint Resident",
    )
    assert resident["user_id"] is not None

    other_room = _create_room(client, admin, prop_id)
    other_bed = _create_bed(client, admin, other_room)
    other = _create_resident(
        client, admin, prop_id, bed_id=other_bed, check_in=True, name="Other Resident"
    )

    created = client.post(
        "/api/v1/complaints",
        headers=_auth(admin),
        json={
            "resident_id": resident["id"],
            "issue": "Water leakage in the bathroom ceiling",
            "priority": "high",
        },
    )
    assert created.status_code == 201, created.text
    complaint = created.json()["data"]
    assert complaint["status"] == "PENDING"
    assert complaint["priority"] == "HIGH"
    assert complaint["room_id"] == room_id

    other_complaint = client.post(
        "/api/v1/complaints",
        headers=_auth(admin),
        json={
            "resident_id": other["id"],
            "issue": "Noise complaint from the corridor at night",
            "priority": "LOW",
        },
    )
    assert other_complaint.status_code == 201, other_complaint.text

    invalid = client.post(
        "/api/v1/complaints",
        headers=_auth(admin),
        json={
            "resident_id": resident["id"],
            "issue": "Invalid priority should fail",
            "priority": "CRITICAL",
        },
    )
    assert invalid.status_code == 422

    # A resident session only sees its own complaints.
    resident_token = get_token(
        client, resident_email, "Resident@123456", client_type="resident_mobile"
    )
    own = client.get("/api/v1/complaints", headers=_auth(resident_token))
    assert own.status_code == 200, own.text
    ids = {c["id"] for c in own.json()["data"]}
    assert complaint["id"] in ids
    assert other_complaint.json()["data"]["id"] not in ids

    # Residents cannot drive the workflow.
    assert (
        client.put(
            f"/api/v1/complaints/{complaint['id']}",
            headers=_auth(resident_token),
            json={"status": "RESOLVED"},
        ).status_code
        == 403
    )

    # Managers and staff are restricted to assigned properties.
    manager = get_token(client, "manager@originpg.com", "Manager@123456")
    staff = get_token(client, "staff@originpg.com", "Staff@123456")
    assert (
        client.get(
            f"/api/v1/complaints?property_id={prop_id}", headers=_auth(manager)
        ).status_code
        == 403
    )
    assert (
        client.get(
            f"/api/v1/complaints?property_id={prop_id}", headers=_auth(staff)
        ).status_code
        == 403
    )

    # Admin can advance the workflow and record resolution time.
    in_progress = client.put(
        f"/api/v1/complaints/{complaint['id']}",
        headers=_auth(admin),
        json={"status": "in-progress", "resolution_notes": "Plumber assigned"},
    )
    assert in_progress.status_code == 200, in_progress.text
    assert in_progress.json()["data"]["status"] == "IN_PROGRESS"
    assert in_progress.json()["data"]["resolved_at"] is None

    resolved = client.put(
        f"/api/v1/complaints/{complaint['id']}",
        headers=_auth(admin),
        json={"status": "RESOLVED"},
    )
    assert resolved.status_code == 200, resolved.text
    assert resolved.json()["data"]["status"] == "RESOLVED"
    assert resolved.json()["data"]["resolved_at"] is not None


def test_expenses_persistence_validation_and_rbac(client):
    admin = get_token(client, "admin@originpg.com", "Admin@123456")
    prop_id = _create_property(client, admin, "EXP")

    created = client.post(
        "/api/v1/expenses",
        headers=_auth(admin),
        json={
            "property_id": prop_id,
            "title": "Audit monthly groceries",
            "category": "groceries",
            "amount": "450.50",
            "date": date.today().isoformat(),
            "method": "cash",
            "notes": "Vegetables and staples",
        },
    )
    assert created.status_code == 201, created.text
    expense = created.json()["data"]
    assert expense["category"] == "GROCERIES"
    assert expense["method"] == "CASH"
    assert expense["amount"] == 450.5
    assert expense["property_id"] == prop_id

    listed = client.get(
        f"/api/v1/expenses?property_id={prop_id}", headers=_auth(admin)
    )
    assert listed.status_code == 200, listed.text
    assert [e["id"] for e in listed.json()["data"]] == [expense["id"]]

    assert (
        client.post(
            "/api/v1/expenses",
            headers=_auth(admin),
            json={
                "property_id": prop_id,
                "title": "Bad category",
                "category": "FOOD",
                "amount": "10.00",
                "date": date.today().isoformat(),
                "method": "CASH",
            },
        ).status_code
        == 422
    )
    assert (
        client.post(
            "/api/v1/expenses",
            headers=_auth(admin),
            json={
                "property_id": prop_id,
                "title": "Zero amount",
                "category": "UTILITIES",
                "amount": "0",
                "date": date.today().isoformat(),
                "method": "CASH",
            },
        ).status_code
        == 422
    )

    manager = get_token(client, "manager@originpg.com", "Manager@123456")
    staff = get_token(client, "staff@originpg.com", "Staff@123456")
    assert (
        client.get(
            f"/api/v1/expenses?property_id={prop_id}", headers=_auth(manager)
        ).status_code
        == 403
    )
    assert (
        client.post(
            "/api/v1/expenses",
            headers=_auth(manager),
            json={
                "property_id": prop_id,
                "title": "Unassigned property expense",
                "category": "UTILITIES",
                "amount": "10.00",
                "date": date.today().isoformat(),
                "method": "CASH",
            },
        ).status_code
        == 403
    )
    assert (
        client.get("/api/v1/expenses", headers=_auth(staff)).status_code == 403
    )


def test_staff_persistence_validation_and_rbac(client):
    admin = get_token(client, "admin@originpg.com", "Admin@123456")
    prop_id = _create_property(client, admin, "STF")
    phone = _unique_phone()

    created = client.post(
        "/api/v1/staff",
        headers=_auth(admin),
        json={
            "name": "Audit Warden",
            "role": "warden",
            "phone": phone,
            "salary": "25000.00",
            "property_id": prop_id,
        },
    )
    assert created.status_code == 201, created.text
    staff_record = created.json()["data"]
    assert staff_record["role"] == "WARDEN"
    assert staff_record["salary"] == 25000.0
    assert staff_record["is_active"] is True

    listed = client.get(
        f"/api/v1/staff?property_id={prop_id}", headers=_auth(admin)
    )
    assert listed.status_code == 200, listed.text
    assert [s["id"] for s in listed.json()["data"]] == [staff_record["id"]]

    # Duplicate active phone is rejected.
    duplicate = client.post(
        "/api/v1/staff",
        headers=_auth(admin),
        json={
            "name": "Duplicate Warden",
            "role": "WARDEN",
            "phone": phone,
            "salary": "20000.00",
            "property_id": prop_id,
        },
    )
    assert duplicate.status_code == 409

    assert (
        client.post(
            "/api/v1/staff",
            headers=_auth(admin),
            json={
                "name": "Invalid Role",
                "role": "ASTRONAUT",
                "phone": _unique_phone(),
                "salary": "1000.00",
                "property_id": prop_id,
            },
        ).status_code
        == 422
    )
    assert (
        client.post(
            "/api/v1/staff",
            headers=_auth(admin),
            json={
                "name": "Bad Phone",
                "role": "WARDEN",
                "phone": "abc",
                "salary": "1000.00",
                "property_id": prop_id,
            },
        ).status_code
        == 422
    )

    manager = get_token(client, "manager@originpg.com", "Manager@123456")
    staff = get_token(client, "staff@originpg.com", "Staff@123456")
    assert (
        client.get(f"/api/v1/staff?property_id={prop_id}", headers=_auth(manager)).status_code
        == 403
    )
    assert client.get("/api/v1/staff", headers=_auth(staff)).status_code == 403
