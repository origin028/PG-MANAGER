import hashlib
import hmac
import uuid
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
import pytest
import sqlalchemy as sa

from app.core.config import settings
from app.core.security import create_access_token, get_password_hash
from app.models.bed import Bed
from app.models.device_token import DeviceToken
from app.models.invoice import Invoice
from app.models.notification import Notification
from app.models.payment import Payment
from app.models.property import Company, Property
from app.models.receipt import Receipt
from app.models.resident import Resident
from app.models.role import Role
from app.models.room import Room
from app.models.user import User, UserPropertyAccess


def seed_test_context(session_factory):
    db = session_factory()
    company = Company(name="Origin Stays Co", code="ORIGIN_RES")
    db.add(company)
    db.flush()

    super_admin_role = Role(name="SUPER_ADMIN", display_name="Super Admin")
    pm_role = Role(name="PROPERTY_MANAGER", display_name="Property Manager")
    resident_role = Role(name="RESIDENT", display_name="Resident")
    db.add_all([super_admin_role, pm_role, resident_role])
    db.flush()

    admin_user = User(
        company_id=company.id,
        role_id=pm_role.id,
        email="manager@origin.com",
        phone="9999900001",
        full_name="Property Manager Bob",
        password_hash=get_password_hash("password123"),
        is_active=True,
    )
    res_user_1 = User(
        company_id=company.id,
        role_id=resident_role.id,
        email="resident1@example.com",
        phone="9999900002",
        full_name="Resident Alice",
        password_hash=get_password_hash("password123"),
        is_active=True,
    )
    res_user_2 = User(
        company_id=company.id,
        role_id=resident_role.id,
        email="resident2@example.com",
        phone="9999900003",
        full_name="Resident Charlie",
        password_hash=get_password_hash("password123"),
        is_active=True,
    )
    db.add_all([admin_user, res_user_1, res_user_2])
    db.flush()

    prop = Property(
        company_id=company.id,
        name="Serenity PG",
        code="SER_01",
        address_line1="123 Park Street",
        pincode="560001",
    )
    db.add(prop)
    db.flush()

    db.add(UserPropertyAccess(user_id=admin_user.id, property_id=prop.id, access_level="MANAGER"))

    room = Room(property_id=prop.id, room_number="101", floor_number=1, room_type="DOUBLE_SHARING", max_occupancy=2)
    db.add(room)
    db.flush()

    bed_1 = Bed(room_id=room.id, bed_number="A")
    bed_2 = Bed(room_id=room.id, bed_number="B")
    db.add_all([bed_1, bed_2])
    db.flush()

    resident_1 = Resident(
        user_id=res_user_1.id,
        property_id=prop.id,
        room_id=room.id,
        bed_id=bed_1.id,
        check_in_date=date(2026, 1, 1),
        monthly_rent=Decimal("8500.00"),
        security_deposit=Decimal("17000.00"),
        kyc_status="VERIFIED",
        status="ACTIVE",
    )
    resident_2 = Resident(
        user_id=res_user_2.id,
        property_id=prop.id,
        room_id=room.id,
        bed_id=bed_2.id,
        check_in_date=date(2026, 2, 1),
        monthly_rent=Decimal("8500.00"),
        security_deposit=Decimal("17000.00"),
        kyc_status="PENDING",
        status="ACTIVE",
    )
    db.add_all([resident_1, resident_2])
    db.commit()

    ctx = {
        "company_id": company.id,
        "property_id": prop.id,
        "admin_user_id": admin_user.id,
        "res_1_user_id": res_user_1.id,
        "res_2_user_id": res_user_2.id,
        "res_1_id": resident_1.id,
        "res_2_id": resident_2.id,
        "room_id": room.id,
        "bed_1_id": bed_1.id,
    }
    db.close()
    return ctx


def make_auth_header(user_id: uuid.UUID) -> dict:
    token = create_access_token(user_id)
    return {"Authorization": f"Bearer {token}"}


def test_resident_profile_me_endpoint(client):
    from app.main import app
    ctx = seed_test_context(app.state.testing_session)

    # 1. Resident Alice queries /residents/me
    headers = make_auth_header(ctx["res_1_user_id"])
    res = client.get("/api/v1/residents/me", headers=headers)
    assert res.status_code == 200
    data = res.json()["data"]
    assert data["full_name"] == "Resident Alice"
    assert data["phone"] == "9999900002"
    assert data["property_name"] == "Serenity PG"
    assert data["room_number"] == "101"
    assert data["bed_number"] == "A"
    assert data["monthly_rent"] == 8500.00
    assert data["kyc_status"] == "VERIFIED"

    # 2. Non-resident (Manager) queries /residents/me -> 404
    admin_headers = make_auth_header(ctx["admin_user_id"])
    res_admin = client.get("/api/v1/residents/me", headers=admin_headers)
    assert res_admin.status_code == 404

    # 3. Unauthenticated -> 401
    assert client.get("/api/v1/residents/me").status_code == 401


def test_admin_invoice_generation_and_notification(client):
    from app.main import app
    ctx = seed_test_context(app.state.testing_session)

    headers = make_auth_header(ctx["admin_user_id"])
    payload = {
        "property_id": str(ctx["property_id"]),
        "resident_id": str(ctx["res_1_id"]),
        "billing_month": "2026-11",
        "invoice_type": "RENT",
        "amount": 8500.00,
        "due_date": "2026-11-05",
        "notes": "November Rent",
    }
    res = client.post("/api/v1/invoices", json=payload, headers=headers)
    assert res.status_code == 201
    inv_data = res.json()["data"]
    assert inv_data["amount"] == 8500.00
    assert inv_data["status"] == "PENDING"
    assert "INV-202611-" in inv_data["invoice_number"]

    # Verify in-app push notification enqueued for resident
    db = app.state.testing_session()
    notif = db.scalar(
        sa.select(Notification).where(Notification.user_id == ctx["res_1_user_id"])
    )
    assert notif is not None
    assert "Rent Invoice: 2026-11" in notif.title
    assert "8,500.00" in notif.body
    assert notif.channel == "PUSH"
    db.close()

    # Duplicate invoice cycle rejected with 409 Conflict
    res_dup = client.post("/api/v1/invoices", json=payload, headers=headers)
    assert res_dup.status_code == 409

    # Resident cannot call admin invoice creation -> 403
    res_headers = make_auth_header(ctx["res_1_user_id"])
    res_denied = client.post("/api/v1/invoices", json=payload, headers=res_headers)
    assert res_denied.status_code == 403


def test_resident_my_invoices_and_detail_scoping(client):
    from app.main import app
    ctx = seed_test_context(app.state.testing_session)

    # Seed an invoice for Resident 1
    db = app.state.testing_session()
    inv_1 = Invoice(
        property_id=ctx["property_id"],
        resident_id=ctx["res_1_id"],
        invoice_number="INV-202610-001",
        billing_month="2026-10",
        invoice_type="RENT",
        amount=Decimal("8500.00"),
        paid_amount=Decimal("0.00"),
        due_date=date(2026, 10, 5),
        status="PENDING",
    )
    # Seed an invoice for Resident 2
    inv_2 = Invoice(
        property_id=ctx["property_id"],
        resident_id=ctx["res_2_id"],
        invoice_number="INV-202610-002",
        billing_month="2026-10",
        invoice_type="RENT",
        amount=Decimal("8500.00"),
        paid_amount=Decimal("8500.00"),
        due_date=date(2026, 10, 5),
        status="PAID",
    )
    db.add_all([inv_1, inv_2])
    db.commit()
    inv_1_id = inv_1.id
    inv_2_id = inv_2.id
    db.close()

    # Resident 1 calls /invoices/my
    headers_1 = make_auth_header(ctx["res_1_user_id"])
    res = client.get("/api/v1/invoices/my", headers=headers_1)
    assert res.status_code == 200
    items = res.json()["data"]
    assert len(items) == 1
    assert items[0]["invoice_number"] == "INV-202610-001"
    assert items[0]["remaining_amount"] == 8500.00

    # Resident 1 accesses own invoice detail -> 200
    res_detail = client.get(f"/api/v1/invoices/{inv_1_id}", headers=headers_1)
    assert res_detail.status_code == 200
    assert res_detail.json()["data"]["resident_name"] == "Resident Alice"

    # Resident 1 attempts to access Resident 2's invoice -> 403 Forbidden!
    res_forbidden = client.get(f"/api/v1/invoices/{inv_2_id}", headers=headers_1)
    assert res_forbidden.status_code == 403

    # Property Manager can access both invoices
    admin_headers = make_auth_header(ctx["admin_user_id"])
    assert client.get(f"/api/v1/invoices/{inv_1_id}", headers=admin_headers).status_code == 200
    assert client.get(f"/api/v1/invoices/{inv_2_id}", headers=admin_headers).status_code == 200


def test_payment_initiation_metadata_and_status(client, monkeypatch):
    from app.main import app
    ctx = seed_test_context(app.state.testing_session)

    # Mock gateway
    class MockGateway:
        def __init__(self, key_id, key_secret):
            pass
        def create_order(self, amount, currency, receipt, notes):
            return {"order_id": "order_mobile_test_1", "amount": amount, "currency": currency, "status": "created"}

    monkeypatch.setattr("app.api.v1.endpoints.payments.RazorpayGateway", MockGateway)
    monkeypatch.setattr(settings, "RAZORPAY_KEY_ID", "rzp_test_mobile_mock")

    # Seed unpaid invoice for Resident 1
    db = app.state.testing_session()
    invoice = Invoice(
        property_id=ctx["property_id"],
        resident_id=ctx["res_1_id"],
        invoice_number="INV-202611-PAY1",
        billing_month="2026-11",
        invoice_type="RENT",
        amount=Decimal("8500.00"),
        paid_amount=Decimal("0.00"),
        due_date=date(2026, 11, 5),
        status="PENDING",
    )
    db.add(invoice)
    db.commit()
    inv_id = invoice.id
    db.close()

    # Resident 1 calls POST /payments/requests
    headers_1 = make_auth_header(ctx["res_1_user_id"])
    req_payload = {
        "invoice_id": str(inv_id),
        "amount": 8500.00,
        "idempotency_key": "idemp_mobile_test_001",
    }
    res = client.post("/api/v1/payments/requests", json=req_payload, headers=headers_1)
    assert res.status_code == 201
    pay_data = res.json()["data"]
    payment_id = pay_data["payment_id"]
    assert pay_data["key_id"] == "rzp_test_mobile_mock"
    assert pay_data["property_name"] == "Serenity PG"
    assert pay_data["gateway_order_id"] == "order_mobile_test_1"
    assert pay_data["resident_name"] == "Resident Alice"

    # Query payment status: GET /payments/{payment_id}/status
    res_status = client.get(f"/api/v1/payments/{payment_id}/status", headers=headers_1)
    assert res_status.status_code == 200
    st_data = res_status.json()["data"]
    assert st_data["status"] == "PENDING"
    assert st_data["is_settled"] is False
    assert st_data["receipt_id"] is None

    # Resident 2 cannot inspect Resident 1's payment status -> 403
    headers_2 = make_auth_header(ctx["res_2_user_id"])
    assert client.get(f"/api/v1/payments/{payment_id}/status", headers=headers_2).status_code == 403


def test_payment_verify_and_receipt_retrieval(client, monkeypatch):
    from app.main import app
    ctx = seed_test_context(app.state.testing_session)

    TEST_KEY_SECRET = "secret_for_checkout_verify_test"
    monkeypatch.setattr(settings, "RAZORPAY_KEY_SECRET", TEST_KEY_SECRET)
    monkeypatch.setattr(settings, "RAZORPAY_KEY_ID", "rzp_test_12345")

    # Seed unpaid invoice & pending payment
    db = app.state.testing_session()
    invoice = Invoice(
        property_id=ctx["property_id"],
        resident_id=ctx["res_1_id"],
        invoice_number="INV-202611-VER1",
        billing_month="2026-11",
        invoice_type="RENT",
        amount=Decimal("8500.00"),
        paid_amount=Decimal("0.00"),
        due_date=date(2026, 11, 5),
        status="PENDING",
    )
    db.add(invoice)
    db.flush()

    payment = Payment(
        property_id=ctx["property_id"],
        invoice_id=invoice.id,
        resident_id=ctx["res_1_id"],
        payment_number="PAY-VERIFY-TEST-001",
        amount=Decimal("8500.00"),
        payment_mode="UPI",
        gateway_order_id="order_checkout_verify_001",
        status="PENDING",
        idempotency_key="idemp_verify_001",
    )
    db.add(payment)
    db.commit()
    payment_id = payment.id
    invoice_id = invoice.id
    db.close()

    headers_1 = make_auth_header(ctx["res_1_user_id"])
    order_id = "order_checkout_verify_001"
    pay_id = "pay_checkout_verify_001"

    # 1. Test invalid signature rejected with 400 Bad Request
    bad_verify_payload = {
        "payment_id": str(payment_id),
        "razorpay_order_id": order_id,
        "razorpay_payment_id": pay_id,
        "razorpay_signature": "invalid_fake_signature_abc",
    }
    res_bad = client.post("/api/v1/payments/verify", json=bad_verify_payload, headers=headers_1)
    assert res_bad.status_code == 400
    assert "Invalid payment signature" in res_bad.text

    # 2. Compute authentic Razorpay signature: HMAC-SHA256(order_id|payment_id, secret)
    msg = f"{order_id}|{pay_id}".encode("utf-8")
    valid_sig = hmac.new(TEST_KEY_SECRET.encode("utf-8"), msg, hashlib.sha256).hexdigest()

    good_verify_payload = {
        "payment_id": str(payment_id),
        "razorpay_order_id": order_id,
        "razorpay_payment_id": pay_id,
        "razorpay_signature": valid_sig,
    }
    res_good = client.post("/api/v1/payments/verify", json=good_verify_payload, headers=headers_1)
    assert res_good.status_code == 200
    verified_data = res_good.json()["data"]
    assert verified_data["is_settled"] is True
    assert verified_data["status"] == "SUCCESS"
    receipt_id = verified_data["receipt_id"]
    assert receipt_id is not None
    assert verified_data["receipt_number"] is not None

    # Check invoice status updated to PAID in database
    db = app.state.testing_session()
    inv_check = db.get(Invoice, invoice_id)
    assert inv_check.status == "PAID"
    assert inv_check.paid_amount == Decimal("8500.00")
    db.close()

    # 3. Duplicate verify call is idempotent -> returns already settled status
    res_dup = client.post("/api/v1/payments/verify", json=good_verify_payload, headers=headers_1)
    assert res_dup.status_code == 200
    assert res_dup.json()["data"]["is_settled"] is True

    # 4. Resident retrieves receipt list: GET /receipts/my
    res_receipts = client.get("/api/v1/receipts/my", headers=headers_1)
    assert res_receipts.status_code == 200
    rcpt_list = res_receipts.json()["data"]
    assert len(rcpt_list) == 1
    assert rcpt_list[0]["id"] == str(receipt_id)
    assert rcpt_list[0]["amount"] == 8500.00
    assert rcpt_list[0]["invoice_number"] == "INV-202611-VER1"

    # 5. Resident retrieves single receipt detail: GET /receipts/{receipt_id}
    res_rcpt_detail = client.get(f"/api/v1/receipts/{receipt_id}", headers=headers_1)
    assert res_rcpt_detail.status_code == 200
    rcpt_detail = res_rcpt_detail.json()["data"]
    assert rcpt_detail["resident_name"] == "Resident Alice"
    assert rcpt_detail["property_name"] == "Serenity PG"
    assert rcpt_detail["room_number"] == "101"
    assert rcpt_detail["gateway_payment_id"] == pay_id

    # 6. Cross-resident access blocked: Resident 2 cannot access Resident 1's receipt -> 403
    headers_2 = make_auth_header(ctx["res_2_user_id"])
    res_unauth = client.get(f"/api/v1/receipts/{receipt_id}", headers=headers_2)
    assert res_unauth.status_code == 403


def test_device_token_registration(client):
    from app.main import app
    ctx = seed_test_context(app.state.testing_session)

    headers_1 = make_auth_header(ctx["res_1_user_id"])
    token_payload = {
        "device_token": "pushy_device_token_hex_998877665544332211",
        "platform": "android",
        "device_name": "Pixel 7 Pro",
    }
    res = client.post("/api/v1/notifications/device-token", json=token_payload, headers=headers_1)
    assert res.status_code == 200
    token_data = res.json()["data"]
    assert token_data["device_token"] == "pushy_device_token_hex_998877665544332211"
    assert token_data["platform"] == "android"
    assert token_data["is_active"] is True

    # Verify persisted in database
    db = app.state.testing_session()
    dt_record = db.scalar(
        sa.select(DeviceToken).where(DeviceToken.user_id == ctx["res_1_user_id"])
    )
    assert dt_record is not None
    assert dt_record.device_name == "Pixel 7 Pro"
    db.close()

    # Re-registering updates last_seen_at idempotently
    res_upsert = client.post("/api/v1/notifications/device-token", json=token_payload, headers=headers_1)
    assert res_upsert.status_code == 200

    # Unauthenticated returns 401
    assert client.post("/api/v1/notifications/device-token", json=token_payload).status_code == 401
