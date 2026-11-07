import uuid
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
import pytest
from fastapi.testclient import TestClient

from app.core.security import create_access_token, get_password_hash
from app.models.bed import Bed
from app.models.invoice import Invoice
from app.models.payment import Payment
from app.models.property import Company, Property
from app.models.receipt import Receipt
from app.models.resident import Resident
from app.models.role import Role
from app.models.room import Room
from app.models.user import User, UserPropertyAccess
from app.models.webhook_event import ProcessedWebhookEvent


@pytest.fixture(autouse=True)
def enable_mock_gateway(monkeypatch):
    from app.core.config import settings
    monkeypatch.setattr(settings, "PAYMENT_GATEWAY_PROVIDER", "MOCK")
    monkeypatch.setattr(settings, "RAZORPAY_KEY_ID", "")
    monkeypatch.setattr(settings, "RAZORPAY_KEY_SECRET", "")
    monkeypatch.setattr(settings, "RAZORPAY_WEBHOOK_SECRET", "mock_webhook_secret")


def setup_test_context(session_factory):
    db = session_factory()
    company = Company(name="Origin Living", code="ORIGIN_PG")
    admin_role = Role(name="SUPER_ADMIN", display_name="Super Admin")
    pm_role = Role(name="PROPERTY_MANAGER", display_name="Property Manager")
    staff_role = Role(name="STAFF", display_name="Staff")
    resident_role = Role(name="RESIDENT", display_name="Resident")
    db.add_all([company, admin_role, pm_role, staff_role, resident_role])
    db.flush()

    def make_user(role, n, approval="APPROVED"):
        u = User(
            company_id=company.id,
            role_id=role.id,
            phone=f"98800000{n:02d}",
            email=f"user{n}@example.com",
            full_name=f"Test User {n}",
            password_hash=get_password_hash("pass123"),
            approval_status=approval,
            is_active=True,
        )
        db.add(u)
        db.flush()
        return u

    admin = make_user(admin_role, 1)
    pm1 = make_user(pm_role, 2)
    pm2 = make_user(pm_role, 3)
    staff = make_user(staff_role, 4)
    res_user1 = make_user(resident_role, 5)
    res_user2 = make_user(resident_role, 6)

    p1 = Property(company_id=company.id, name="Smart PG H1", code="H1", address_line1="1st Main", pincode="560001")
    p2 = Property(company_id=company.id, name="Smart PG H2", code="H2", address_line1="2nd Main", pincode="560002")
    db.add_all([p1, p2])
    db.flush()

    db.add_all([
        UserPropertyAccess(user_id=pm1.id, property_id=p1.id),
        UserPropertyAccess(user_id=pm2.id, property_id=p2.id),
        UserPropertyAccess(user_id=staff.id, property_id=p1.id),
    ])
    db.flush()

    r101 = Room(property_id=p1.id, room_number="101", floor_number=1)
    db.add(r101)
    db.flush()

    bed1 = Bed(room_id=r101.id, bed_number="101-A", status="OCCUPIED")
    bed2 = Bed(room_id=r101.id, bed_number="101-B", status="AVAILABLE")
    db.add_all([bed1, bed2])
    db.flush()

    res1 = Resident(
        user_id=res_user1.id,
        property_id=p1.id,
        room_id=r101.id,
        bed_id=bed1.id,
        monthly_rent=Decimal("5000.00"),
        security_deposit=Decimal("10000.00"),
        status="ACTIVE",
        check_in_date=date(2026, 1, 1),
    )
    res2 = Resident(
        user_id=res_user2.id,
        property_id=p2.id,
        monthly_rent=Decimal("6000.00"),
        security_deposit=Decimal("12000.00"),
        status="ACTIVE",
        check_in_date=date(2026, 1, 1),
    )
    db.add_all([res1, res2])
    db.commit()

    tokens = {
        "admin": create_access_token(str(admin.id), {"role": "SUPER_ADMIN"}),
        "pm1": create_access_token(str(pm1.id), {"role": "PROPERTY_MANAGER"}),
        "pm2": create_access_token(str(pm2.id), {"role": "PROPERTY_MANAGER"}),
        "staff": create_access_token(str(staff.id), {"role": "STAFF"}),
        "res1": create_access_token(str(res_user1.id), {"role": "RESIDENT"}),
        "res2": create_access_token(str(res_user2.id), {"role": "RESIDENT"}),
    }
    ids = {
        "p1": p1.id, "p2": p2.id,
        "res1": res1.id, "res2": res2.id,
        "bed1": bed1.id, "bed2": bed2.id,
        "res_user1": res_user1.id, "res_user2": res_user2.id,
    }
    db.close()
    return tokens, ids


def auth(token):
    return {"Authorization": f"Bearer {token}"}


# --------------------------------------------------------------------------
# Scenario 1 & 2: Create & Fetch an Invoice
# --------------------------------------------------------------------------
def test_create_and_fetch_invoice(client: TestClient):
    tokens, ids = setup_test_context(client.app.state.testing_session)

    # 1. Create invoice
    res = client.post(
        "/api/v1/invoices",
        headers=auth(tokens["pm1"]),
        json={
            "property_id": str(ids["p1"]),
            "resident_id": str(ids["res1"]),
            "billing_month": "2026-11",
            "invoice_type": "RENT",
            "amount": 5000.00,
            "due_date": "2026-11-10",
            "notes": "November rent",
        },
    )
    assert res.status_code == 201, res.text
    data = res.json()["data"]
    inv_id = data["id"]
    assert data["amount"] == 5000.00
    assert data["status"] == "PENDING"
    assert data["paid_amount"] == 0.00

    # 2. Fetch invoice as resident
    res_fetch = client.get(f"/api/v1/invoices/{inv_id}", headers=auth(tokens["res1"]))
    assert res_fetch.status_code == 200
    detail = res_fetch.json()["data"]
    assert detail["invoice_number"] == data["invoice_number"]
    assert detail["remaining_amount"] == 5000.00

    # 2b. Fetch via /invoices/my
    res_my = client.get("/api/v1/invoices/my", headers=auth(tokens["res1"]))
    assert res_my.status_code == 200
    my_items = res_my.json()["data"]
    assert any(item["id"] == inv_id for item in my_items)


# --------------------------------------------------------------------------
# Scenario 3, 4, 5, 6, 7: Demo Payment Flow & Settlement
# --------------------------------------------------------------------------
def test_demo_payment_flow_and_settlement(client: TestClient):
    tokens, ids = setup_test_context(client.app.state.testing_session)

    # Create invoice
    inv_res = client.post(
        "/api/v1/invoices",
        headers=auth(tokens["pm1"]),
        json={
            "property_id": str(ids["p1"]),
            "resident_id": str(ids["res1"]),
            "billing_month": "2026-12",
            "invoice_type": "RENT",
            "amount": 5000.00,
            "due_date": "2026-12-10",
        },
    )
    inv_id = inv_res.json()["data"]["id"]

    # 3. Create demo payment request
    req_res = client.post(
        "/api/v1/payments/requests",
        headers=auth(tokens["res1"]),
        json={
            "invoice_id": inv_id,
            "amount": 5000.00,
            "idempotency_key": "idemp-demo-req-12345",
        },
    )
    assert req_res.status_code == 201, req_res.text
    req_data = req_res.json()["data"]
    pay_id = req_data["payment_id"]
    order_id = req_data["gateway_order_id"]
    assert order_id.startswith("order_demo_")

    # 4. Complete successful demo payment via verify
    verify_res = client.post(
        "/api/v1/payments/verify",
        headers=auth(tokens["res1"]),
        json={
            "payment_id": pay_id,
            "razorpay_order_id": order_id,
            "razorpay_payment_id": f"pay_demo_{uuid.uuid4().hex[:10]}",
            "razorpay_signature": f"sig_demo_{uuid.uuid4().hex[:10]}",
        },
    )
    assert verify_res.status_code == 200, verify_res.text
    pay_status = verify_res.json()["data"]

    # 5. Verify invoice status is PAID
    assert pay_status["is_settled"] is True
    assert pay_status["status"] == "SUCCESS"

    inv_check = client.get(f"/api/v1/invoices/{inv_id}", headers=auth(tokens["res1"]))
    assert inv_check.json()["data"]["status"] == "PAID"
    assert inv_check.json()["data"]["remaining_amount"] == 0.00

    # 6. Verify payment record
    assert pay_status["payment_id"] == pay_id
    assert pay_status["amount"] == 5000.00

    # 7. Verify receipt is generated
    assert pay_status["receipt_id"] is not None
    assert pay_status["receipt_number"].startswith("RCT-")


# --------------------------------------------------------------------------
# Scenario 8: Download Receipt PDF
# --------------------------------------------------------------------------
def test_download_receipt_pdf(client: TestClient):
    tokens, ids = setup_test_context(client.app.state.testing_session)

    # Fast demo pay
    inv_res = client.post(
        "/api/v1/invoices",
        headers=auth(tokens["pm1"]),
        json={
            "property_id": str(ids["p1"]),
            "resident_id": str(ids["res1"]),
            "billing_month": "2027-01",
            "invoice_type": "RENT",
            "amount": 4500.00,
            "due_date": "2027-01-10",
        },
    )
    inv_id = inv_res.json()["data"]["id"]

    demo_pay = client.post(
        "/api/v1/payments/demo/pay",
        headers=auth(tokens["res1"]),
        json={"invoice_id": inv_id},
    )
    assert demo_pay.status_code == 200
    receipt_id = demo_pay.json()["data"]["receipt_id"]

    # Download PDF
    pdf_res = client.get(f"/api/v1/receipts/{receipt_id}/pdf", headers=auth(tokens["res1"]))
    assert pdf_res.status_code == 200
    assert pdf_res.headers["content-type"] == "application/pdf"
    assert pdf_res.content.startswith(b"%PDF-1.4")
    assert b"OFFICIAL PAYMENT RECEIPT" in pdf_res.content


# --------------------------------------------------------------------------
# Scenario 9: Failed Payment Handling
# --------------------------------------------------------------------------
def test_failed_payment_webhook(client: TestClient):
    tokens, ids = setup_test_context(client.app.state.testing_session)

    inv_res = client.post(
        "/api/v1/invoices",
        headers=auth(tokens["pm1"]),
        json={
            "property_id": str(ids["p1"]),
            "resident_id": str(ids["res1"]),
            "billing_month": "2027-02",
            "invoice_type": "RENT",
            "amount": 5000.00,
            "due_date": "2027-02-10",
        },
    )
    inv_id = inv_res.json()["data"]["id"]

    req_res = client.post(
        "/api/v1/payments/requests",
        headers=auth(tokens["res1"]),
        json={"invoice_id": inv_id, "amount": 5000.00, "idempotency_key": "idemp-fail-test"},
    )
    order_id = req_res.json()["data"]["gateway_order_id"]

    # Deliver payment.failed webhook
    import json
    payload = {
        "event": "payment.failed",
        "event_id": "evt_fail_123",
        "payload": {
            "payment": {
                "entity": {
                    "id": "pay_fail_123",
                    "order_id": order_id,
                    "error_description": "Payment declined by user bank",
                }
            }
        },
    }
    raw_body = json.dumps(payload).encode()
    hook_res = client.post(
        "/api/v1/payments/webhook/razorpay",
        content=raw_body,
        headers={"Content-Type": "application/json", "X-Razorpay-Signature": "demo_signature_valid"},
    )
    assert hook_res.status_code == 200

    # Invoice remains PENDING
    inv_check = client.get(f"/api/v1/invoices/{inv_id}", headers=auth(tokens["res1"]))
    assert inv_check.json()["data"]["status"] == "PENDING"


# --------------------------------------------------------------------------
# Scenario 10: Cancelled Payment Handling
# --------------------------------------------------------------------------
def test_cannot_pay_cancelled_invoice(client: TestClient):
    tokens, ids = setup_test_context(client.app.state.testing_session)

    # Create invoice and set status to CANCELLED in DB
    inv_res = client.post(
        "/api/v1/invoices",
        headers=auth(tokens["pm1"]),
        json={
            "property_id": str(ids["p1"]),
            "resident_id": str(ids["res1"]),
            "billing_month": "2027-03",
            "invoice_type": "RENT",
            "amount": 5000.00,
            "due_date": "2027-03-10",
        },
    )
    inv_id = inv_res.json()["data"]["id"]

    db = client.app.state.testing_session()
    inv = db.get(Invoice, uuid.UUID(inv_id))
    inv.status = "CANCELLED"
    db.commit()
    db.close()

    # Attempt to pay
    pay_res = client.post(
        "/api/v1/payments/demo/pay",
        headers=auth(tokens["res1"]),
        json={"invoice_id": inv_id},
    )
    assert pay_res.status_code == 409
    assert "not eligible for payment" in pay_res.text


# --------------------------------------------------------------------------
# Scenario 11 & 12: Partial Payment & Multiple Payments
# --------------------------------------------------------------------------
def test_partial_payment_and_multiple_payments(client: TestClient):
    tokens, ids = setup_test_context(client.app.state.testing_session)

    inv_res = client.post(
        "/api/v1/invoices",
        headers=auth(tokens["pm1"]),
        json={
            "property_id": str(ids["p1"]),
            "resident_id": str(ids["res1"]),
            "billing_month": "2027-04",
            "invoice_type": "RENT",
            "amount": 5000.00,
            "due_date": "2027-04-10",
        },
    )
    inv_id = inv_res.json()["data"]["id"]

    # 11. Partial payment 1: INR 2000
    pay1 = client.post(
        "/api/v1/payments/demo/pay",
        headers=auth(tokens["res1"]),
        json={"invoice_id": inv_id, "amount": 2000.00},
    )
    assert pay1.status_code == 200
    data1 = pay1.json()["data"]
    assert data1["invoice_status"] == "PARTIALLY_PAID"
    assert data1["paid_amount"] == 2000.00
    assert data1["remaining_balance"] == 3000.00

    # 12. Multiple payments: Payment 2: INR 3000 (Remaining balance)
    pay2 = client.post(
        "/api/v1/payments/demo/pay",
        headers=auth(tokens["res1"]),
        json={"invoice_id": inv_id, "amount": 3000.00},
    )
    assert pay2.status_code == 200
    data2 = pay2.json()["data"]
    assert data2["invoice_status"] == "PAID"
    assert data2["paid_amount"] == 5000.00
    assert data2["remaining_balance"] == 0.00

    # Attempt payment 3: rejected as fully settled
    pay3 = client.post(
        "/api/v1/payments/demo/pay",
        headers=auth(tokens["res1"]),
        json={"invoice_id": inv_id, "amount": 500.00},
    )
    assert pay3.status_code == 409


# --------------------------------------------------------------------------
# Scenario 13: Duplicate Payment Prevention
# --------------------------------------------------------------------------
def test_duplicate_payment_idempotency(client: TestClient):
    tokens, ids = setup_test_context(client.app.state.testing_session)

    inv_res = client.post(
        "/api/v1/invoices",
        headers=auth(tokens["pm1"]),
        json={
            "property_id": str(ids["p1"]),
            "resident_id": str(ids["res1"]),
            "billing_month": "2027-05",
            "invoice_type": "RENT",
            "amount": 5000.00,
            "due_date": "2027-05-10",
        },
    )
    inv_id = inv_res.json()["data"]["id"]

    # First request
    req1 = client.post(
        "/api/v1/payments/requests",
        headers=auth(tokens["res1"]),
        json={"invoice_id": inv_id, "amount": 5000.00, "idempotency_key": "idemp-key-unique-001"},
    )
    assert req1.status_code == 201

    # Second request with SAME idempotency key returns existing request safely
    req2 = client.post(
        "/api/v1/payments/requests",
        headers=auth(tokens["res1"]),
        json={"invoice_id": inv_id, "amount": 5000.00, "idempotency_key": "idemp-key-unique-001"},
    )
    assert req2.status_code in (200, 201)
    assert req2.json()["data"]["payment_id"] == req1.json()["data"]["payment_id"]

    # Third request with SAME idempotency key but DIFFERENT amount is rejected
    req3 = client.post(
        "/api/v1/payments/requests",
        headers=auth(tokens["res1"]),
        json={"invoice_id": inv_id, "amount": 2500.00, "idempotency_key": "idemp-key-unique-001"},
    )
    assert req3.status_code == 409


# --------------------------------------------------------------------------
# Scenario 14: Duplicate Webhook Prevention
# --------------------------------------------------------------------------
def test_duplicate_webhook_prevention(client: TestClient):
    tokens, ids = setup_test_context(client.app.state.testing_session)

    inv_res = client.post(
        "/api/v1/invoices",
        headers=auth(tokens["pm1"]),
        json={
            "property_id": str(ids["p1"]),
            "resident_id": str(ids["res1"]),
            "billing_month": "2027-06",
            "invoice_type": "RENT",
            "amount": 4000.00,
            "due_date": "2027-06-10",
        },
    )
    inv_id = inv_res.json()["data"]["id"]

    req_res = client.post(
        "/api/v1/payments/requests",
        headers=auth(tokens["res1"]),
        json={"invoice_id": inv_id, "amount": 4000.00, "idempotency_key": "idemp-wh-dupe"},
    )
    order_id = req_res.json()["data"]["gateway_order_id"]

    import json
    payload = {
        "event": "payment.captured",
        "event_id": "evt_captured_999",
        "payload": {
            "payment": {
                "entity": {
                    "id": "pay_capt_999",
                    "order_id": order_id,
                    "amount": 400000,
                    "currency": "INR",
                    "method": "UPI",
                }
            }
        },
    }
    raw = json.dumps(payload).encode()

    # First webhook: succeeds
    res1 = client.post(
        "/api/v1/payments/webhook/razorpay",
        content=raw,
        headers={"Content-Type": "application/json", "X-Razorpay-Signature": "demo_signature_ok"},
    )
    assert res1.status_code == 200

    # Second identical webhook: acknowledged idempotently without error or double-balance
    res2 = client.post(
        "/api/v1/payments/webhook/razorpay",
        content=raw,
        headers={"Content-Type": "application/json", "X-Razorpay-Signature": "demo_signature_ok"},
    )
    assert res2.status_code == 200
    assert "already processed" in res2.json()["message"]


# --------------------------------------------------------------------------
# Scenario 15: Invalid Gateway Signature
# --------------------------------------------------------------------------
def test_invalid_gateway_signature_rejected(client: TestClient):
    tokens, ids = setup_test_context(client.app.state.testing_session)

    inv_res = client.post(
        "/api/v1/invoices",
        headers=auth(tokens["pm1"]),
        json={
            "property_id": str(ids["p1"]),
            "resident_id": str(ids["res1"]),
            "billing_month": "2027-07",
            "invoice_type": "RENT",
            "amount": 5000.00,
            "due_date": "2027-07-10",
        },
    )
    inv_id = inv_res.json()["data"]["id"]

    req_res = client.post(
        "/api/v1/payments/requests",
        headers=auth(tokens["res1"]),
        json={"invoice_id": inv_id, "amount": 5000.00, "idempotency_key": "idemp-bad-sig"},
    )
    pay_id = req_res.json()["data"]["payment_id"]
    order_id = req_res.json()["data"]["gateway_order_id"]

    verify_res = client.post(
        "/api/v1/payments/verify",
        headers=auth(tokens["res1"]),
        json={
            "payment_id": pay_id,
            "razorpay_order_id": order_id,
            "razorpay_payment_id": "pay_test_bad",
            "razorpay_signature": "completely_invalid_signature_xyz",
        },
    )
    assert verify_res.status_code == 400
    assert "Invalid payment signature" in verify_res.text


# --------------------------------------------------------------------------
# Scenario 16, 17, 18: Security & Access Restrictions
# --------------------------------------------------------------------------
def test_security_and_property_restrictions(client: TestClient):
    tokens, ids = setup_test_context(client.app.state.testing_session)

    inv_res = client.post(
        "/api/v1/invoices",
        headers=auth(tokens["pm1"]),
        json={
            "property_id": str(ids["p1"]),
            "resident_id": str(ids["res1"]),
            "billing_month": "2027-08",
            "invoice_type": "RENT",
            "amount": 5000.00,
            "due_date": "2027-08-10",
        },
    )
    inv_id = inv_res.json()["data"]["id"]

    # 17. Resident 2 cannot access Resident 1's invoice
    res_other = client.get(f"/api/v1/invoices/{inv_id}", headers=auth(tokens["res2"]))
    assert res_other.status_code == 403

    # 18. Property Manager 2 (assigned to P2 only) cannot access P1's invoice
    pm_other = client.get(f"/api/v1/invoices/{inv_id}", headers=auth(tokens["pm2"]))
    assert pm_other.status_code == 403


# --------------------------------------------------------------------------
# Scenario 19: Manual Cash Payment Recording by Staff
# --------------------------------------------------------------------------
def test_manual_cash_payment_by_staff(client: TestClient):
    tokens, ids = setup_test_context(client.app.state.testing_session)

    inv_res = client.post(
        "/api/v1/invoices",
        headers=auth(tokens["pm1"]),
        json={
            "property_id": str(ids["p1"]),
            "resident_id": str(ids["res1"]),
            "billing_month": "2027-09",
            "invoice_type": "RENT",
            "amount": 5000.00,
            "due_date": "2027-09-10",
        },
    )
    inv_id = inv_res.json()["data"]["id"]

    # Staff records cash payment
    man_res = client.post(
        "/api/v1/payments/manual",
        headers=auth(tokens["staff"]),
        json={
            "invoice_id": inv_id,
            "amount": 5000.00,
            "payment_mode": "CASH",
            "reference_number": "RECEIPT-BOOK-042",
            "notes": "Collected cash at front office",
        },
    )
    assert man_res.status_code == 201, man_res.text
    data = man_res.json()["data"]
    assert data["payment_mode"] == "CASH"
    assert data["status"] == "PAID"
    assert data["invoice_status"] == "PAID"
    assert data["remaining_balance"] == 0.00
    assert data["receipt_number"].startswith("RCT-MAN-")


# --------------------------------------------------------------------------
# Scenario 20: Resident Check-Out and Bed Release
# --------------------------------------------------------------------------
def test_resident_checkout_and_bed_release(client: TestClient):
    tokens, ids = setup_test_context(client.app.state.testing_session)

    # Checkout resident 1 with damage deductions
    co_res = client.post(
        f"/api/v1/residents/{ids['res1']}/checkout",
        headers=auth(tokens["pm1"]),
        json={
            "damage_charges": 500.00,
            "damage_notes": "Wall repaint needed",
            "force_checkout": False,
        },
    )
    assert co_res.status_code == 200, co_res.text
    co_data = co_res.json()["data"]
    assert co_data["status"] == "CHECKED_OUT"
    assert co_data["bed_released"] is True
    assert co_data["security_deposit"] == 10000.00
    assert co_data["damage_charges"] == 500.00
    assert co_data["deposit_refund_amount"] == 9500.00

    # Verify bed status transitioned to AVAILABLE in DB
    db = client.app.state.testing_session()
    bed = db.get(Bed, ids["bed1"])
    assert bed.status == "AVAILABLE"
    res_rec = db.get(Resident, ids["res1"])
    assert res_rec.bed_id is None
    assert res_rec.status == "CHECKED_OUT"
    db.close()
