import hashlib
import hmac
import json
import uuid
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal

import pytest
import sqlalchemy as sa

from app.core.config import settings
from app.integrations.whatsapp import WhatsAppCloudProvider
from app.models.invoice import Invoice
from app.models.payment import Payment
from app.models.property import Company, Property
from app.models.receipt import Receipt
from app.models.resident import Resident
from app.models.role import Role
from app.models.room import Room
from app.models.user import User
from app.services.receipt_delivery_service import ReceiptDeliveryService


WEBHOOK_SECRET = "test_webhook_secret_receipts"


def make_webhook_headers_and_body(event_type: str, order_id: str, payment_id: str, amount_paise: int, event_id: str = None, method: str = "upi"):
    event_id = event_id or f"evt_{uuid.uuid4().hex[:12]}"
    payload_dict = {
        "entity": "event",
        "account_id": "acc_123456",
        "event": event_type,
        "contains": ["payment"],
        "payload": {
            "payment": {
                "entity": {
                    "id": payment_id,
                    "entity": "payment",
                    "amount": amount_paise,
                    "currency": "INR",
                    "status": "captured" if event_type == "payment.captured" else "failed",
                    "order_id": order_id,
                    "method": method,
                }
            }
        },
        "created_at": int(datetime.now().timestamp()),
        "event_id": event_id,
    }
    raw_body = json.dumps(payload_dict, separators=(",", ":")).encode("utf-8")
    sig = hmac.new(WEBHOOK_SECRET.encode("utf-8"), raw_body, hashlib.sha256).hexdigest()
    headers = {
        "X-Razorpay-Signature": sig,
        "Content-Type": "application/json",
    }
    return headers, raw_body, event_id


def seed_settled_receipt_data(session_factory, phone="9800000001", amount="150.00", order_id="order_rcpt_001"):
    db = session_factory()
    company = Company(name="C_Receipts", code=f"C_{uuid.uuid4().hex[:4]}")
    role = Role(name="RESIDENT", display_name="Resident")
    db.add_all((company, role))
    db.flush()

    user = User(
        company_id=company.id,
        role_id=role.id,
        phone=phone,
        full_name="Alice Wonder",
        password_hash="pwd_hash",
    )
    db.add(user)
    db.flush()

    prop = Property(
        company_id=company.id,
        name="Maple Leaf PG",
        code=f"P_{uuid.uuid4().hex[:4]}",
        address_line1="HSR Layout",
        pincode="560102",
    )
    db.add(prop)
    db.flush()

    room = Room(property_id=prop.id, room_number="401")
    db.add(room)
    db.flush()

    resident = Resident(user_id=user.id, property_id=prop.id, room_id=room.id, check_in_date=date.today())
    db.add(resident)
    db.flush()

    invoice = Invoice(
        property_id=prop.id,
        resident_id=resident.id,
        invoice_number=f"INV-RCPT-{uuid.uuid4().hex[:4].upper()}",
        billing_month="2026-10",
        amount=Decimal(amount),
        paid_amount=Decimal("0.00"),
        due_date=date.today(),
        status="PENDING",
    )
    db.add(invoice)
    db.flush()

    payment = Payment(
        property_id=prop.id,
        invoice_id=invoice.id,
        resident_id=resident.id,
        payment_number=f"PAY-RCPT-{uuid.uuid4().hex[:6].upper()}",
        amount=Decimal(amount),
        payment_mode="UPI",
        gateway_order_id=order_id,
        status="PENDING",
        idempotency_key=f"idemp-rcpt-{uuid.uuid4().hex[:8]}",
        reservation_expires_at=datetime.now(timezone.utc) + timedelta(minutes=15),
    )
    db.add(payment)
    db.commit()

    ctx = {
        "company_id": company.id,
        "property_id": prop.id,
        "property_name": prop.name,
        "room_number": room.room_number,
        "user_name": user.full_name,
        "user_phone": user.phone,
        "resident_id": resident.id,
        "invoice_id": invoice.id,
        "invoice_number": invoice.invoice_number,
        "payment_id": payment.id,
        "order_id": order_id,
        "amount": amount,
    }
    db.close()
    return ctx


def test_receipt_dispatch_after_verified_successful_settlement(client, monkeypatch):
    from app.main import app

    monkeypatch.setattr(settings, "RAZORPAY_WEBHOOK_SECRET", WEBHOOK_SECRET)
    monkeypatch.setattr(settings, "WHATSAPP_PHONE_NUMBER_ID", "123456")
    monkeypatch.setattr(settings, "WHATSAPP_ACCESS_TOKEN", "wa_token")
    monkeypatch.setattr(settings, "WHATSAPP_RECEIPT_TEMPLATE", "rent_receipt_v1")

    dispatched = []

    def mock_send_template(self, to_phone: str, template: str, parameters: list[str]):
        dispatched.append({"to": to_phone, "template": template, "parameters": parameters})
        return "wamid_receipt_success_001"

    monkeypatch.setattr(WhatsAppCloudProvider, "send_template", mock_send_template)

    ctx = seed_settled_receipt_data(app.state.testing_session, amount="150.00", order_id="ord_auto_rcpt")

    headers, raw_body, _ = make_webhook_headers_and_body(
        event_type="payment.captured",
        order_id=ctx["order_id"],
        payment_id="pay_rzp_auto_rcpt",
        amount_paise=15000,
        method="upi",
    )

    res = client.post("/api/v1/payments/webhook/razorpay", content=raw_body, headers=headers)
    assert res.status_code == 200

    db = app.state.testing_session()
    receipt = db.query(Receipt).filter_by(payment_id=ctx["payment_id"]).one()
    assert receipt.whatsapp_status == "SENT"
    assert receipt.whatsapp_attempts == 1
    assert receipt.last_delivery_error is None

    # Check template parameters match exactly
    assert len(dispatched) == 1
    call = dispatched[0]
    assert call["to"] == ctx["user_phone"]
    assert call["template"] == "rent_receipt_v1"
    # [property_name, room_number, resident_name, receipt_number, invoice_number, amount_str, payment_date, payment_mode]
    assert call["parameters"][0] == "Maple Leaf PG"
    assert call["parameters"][1] == "401"
    assert call["parameters"][2] == "Alice Wonder"
    assert call["parameters"][3] == receipt.receipt_number
    assert call["parameters"][4] == ctx["invoice_number"]
    assert "150.00" in call["parameters"][5]
    assert call["parameters"][7] == "UPI"
    db.close()


def test_no_receipt_dispatch_for_invalid_signature_pending_or_failed(client, monkeypatch):
    from app.main import app

    monkeypatch.setattr(settings, "RAZORPAY_WEBHOOK_SECRET", WEBHOOK_SECRET)
    dispatched = []
    monkeypatch.setattr(WhatsAppCloudProvider, "send_template", lambda *args, **kwargs: dispatched.append(args))

    ctx = seed_settled_receipt_data(app.state.testing_session, amount="100.00", order_id="ord_fail_check")

    # 1. Invalid signature webhook
    h1, b1, _ = make_webhook_headers_and_body("payment.captured", ctx["order_id"], "pay_fail_1", 10000)
    h1["X-Razorpay-Signature"] = "invalid_sig"
    client.post("/api/v1/payments/webhook/razorpay", content=b1, headers=h1)

    # 2. Failed payment event
    h2, b2, _ = make_webhook_headers_and_body("payment.failed", ctx["order_id"], "pay_fail_2", 10000)
    client.post("/api/v1/payments/webhook/razorpay", content=b2, headers=h2)

    assert len(dispatched) == 0
    db = app.state.testing_session()
    assert db.query(Receipt).count() == 0
    db.close()


def test_whatsapp_transient_failure_followed_by_successful_worker_retry(client, monkeypatch):
    from app.main import app

    monkeypatch.setattr(settings, "RAZORPAY_WEBHOOK_SECRET", WEBHOOK_SECRET)
    monkeypatch.setattr(settings, "WHATSAPP_PHONE_NUMBER_ID", "123456")
    monkeypatch.setattr(settings, "WHATSAPP_ACCESS_TOKEN", "wa_token")

    attempt_counter = {"count": 0}

    def flaky_send_template(self, to_phone, template, parameters):
        attempt_counter["count"] += 1
        if attempt_counter["count"] == 1:
            raise ConnectionError("Transient network timeout to Meta Graph API")
        return "wamid_retry_success_999"

    monkeypatch.setattr(WhatsAppCloudProvider, "send_template", flaky_send_template)

    ctx = seed_settled_receipt_data(app.state.testing_session, amount="200.00", order_id="ord_retry_flow")

    headers, raw_body, _ = make_webhook_headers_and_body(
        event_type="payment.captured",
        order_id=ctx["order_id"],
        payment_id="pay_retry_001",
        amount_paise=20000,
    )

    # 1. Webhook delivers - initial inline delivery attempt fails with transient error
    res = client.post("/api/v1/payments/webhook/razorpay", content=raw_body, headers=headers)
    assert res.status_code == 200

    db = app.state.testing_session()
    receipt = db.query(Receipt).filter_by(payment_id=ctx["payment_id"]).one()
    # Settlement succeeded, receipt persisted, delivery status remains PENDING with retry scheduled
    assert receipt.whatsapp_status == "PENDING"
    assert receipt.whatsapp_attempts == 1
    assert "Transient network timeout" in receipt.last_delivery_error
    assert receipt.next_retry_at is not None

    # Fast-forward retry schedule to now
    receipt.next_retry_at = datetime.now(timezone.utc) - timedelta(seconds=1)
    db.commit()

    # 2. Worker executes delivery pass
    service = ReceiptDeliveryService(db)
    sent = service.process_due_receipts()
    assert sent == 1

    db.refresh(receipt)
    assert receipt.whatsapp_status == "SENT"
    assert receipt.whatsapp_attempts == 2
    assert receipt.last_delivery_error is None
    assert receipt.next_retry_at is None
    db.close()


def test_whatsapp_permanent_failure_does_not_retry_indefinitely(client, monkeypatch):
    from app.main import app

    monkeypatch.setattr(settings, "RAZORPAY_WEBHOOK_SECRET", WEBHOOK_SECRET)
    monkeypatch.setattr(settings, "WHATSAPP_PHONE_NUMBER_ID", "123456")
    monkeypatch.setattr(settings, "WHATSAPP_ACCESS_TOKEN", "wa_token")

    def permanent_fail_send(self, to_phone, template, parameters):
        raise ValueError("Invalid phone number: User is not a valid WhatsApp user")

    monkeypatch.setattr(WhatsAppCloudProvider, "send_template", permanent_fail_send)

    ctx = seed_settled_receipt_data(app.state.testing_session, amount="50.00", order_id="ord_perm_fail")

    headers, raw_body, _ = make_webhook_headers_and_body(
        event_type="payment.captured",
        order_id=ctx["order_id"],
        payment_id="pay_perm_001",
        amount_paise=5000,
    )

    client.post("/api/v1/payments/webhook/razorpay", content=raw_body, headers=headers)

    db = app.state.testing_session()
    receipt = db.query(Receipt).filter_by(payment_id=ctx["payment_id"]).one()
    # Classified as permanent failure: status marked FAILED, no future retries scheduled
    assert receipt.whatsapp_status == "FAILED"
    assert receipt.next_retry_at is None
    assert "not a valid whatsapp user" in receipt.last_delivery_error.lower()

    # Worker pass skips it
    service = ReceiptDeliveryService(db)
    assert service.process_due_receipts() == 0
    db.close()


def test_duplicate_webhook_and_duplicate_worker_execution_idempotency(client, monkeypatch):
    from app.main import app

    monkeypatch.setattr(settings, "RAZORPAY_WEBHOOK_SECRET", WEBHOOK_SECRET)
    monkeypatch.setattr(settings, "WHATSAPP_PHONE_NUMBER_ID", "123456")
    monkeypatch.setattr(settings, "WHATSAPP_ACCESS_TOKEN", "wa_token")

    send_count = {"count": 0}

    def counting_send(self, *args, **kwargs):
        send_count["count"] += 1
        return "wamid_dup_check_01"

    monkeypatch.setattr(WhatsAppCloudProvider, "send_template", counting_send)

    ctx = seed_settled_receipt_data(app.state.testing_session, amount="75.00", order_id="ord_dup_rcpt")

    headers, raw_body, evt_id = make_webhook_headers_and_body(
        event_type="payment.captured",
        order_id=ctx["order_id"],
        payment_id="pay_dup_001",
        amount_paise=7500,
        event_id="evt_receipt_dup_1",
    )

    # First webhook delivery
    res1 = client.post("/api/v1/payments/webhook/razorpay", content=raw_body, headers=headers)
    assert res1.status_code == 200
    assert send_count["count"] == 1

    # Second webhook delivery with identical event_id
    res2 = client.post("/api/v1/payments/webhook/razorpay", content=raw_body, headers=headers)
    assert res2.status_code == 200
    # WhatsApp template NOT sent a second time
    assert send_count["count"] == 1

    # Running worker batch pass on settled receipt
    db = app.state.testing_session()
    service = ReceiptDeliveryService(db)
    assert service.process_due_receipts() == 0
    assert send_count["count"] == 1
    db.close()


def test_whatsapp_failure_never_rolls_back_payment_or_invoice_settlement(client, monkeypatch):
    from app.main import app

    monkeypatch.setattr(settings, "RAZORPAY_WEBHOOK_SECRET", WEBHOOK_SECRET)
    monkeypatch.setattr(settings, "WHATSAPP_PHONE_NUMBER_ID", "123456")
    monkeypatch.setattr(settings, "WHATSAPP_ACCESS_TOKEN", "wa_token")

    def crashing_send(self, *args, **kwargs):
        raise RuntimeError("Severe infrastructure failure in WhatsApp provider client")

    monkeypatch.setattr(WhatsAppCloudProvider, "send_template", crashing_send)

    ctx = seed_settled_receipt_data(app.state.testing_session, amount="300.00", order_id="ord_crash_test")

    headers, raw_body, _ = make_webhook_headers_and_body(
        event_type="payment.captured",
        order_id=ctx["order_id"],
        payment_id="pay_crash_001",
        amount_paise=30000,
    )

    res = client.post("/api/v1/payments/webhook/razorpay", content=raw_body, headers=headers)
    assert res.status_code == 200

    db = app.state.testing_session()
    payment = db.get(Payment, ctx["payment_id"])
    assert payment.status == "SUCCESS"

    invoice = db.get(Invoice, ctx["invoice_id"])
    assert invoice.paid_amount == Decimal("300.00")
    assert invoice.status == "PAID"

    receipt = db.query(Receipt).filter_by(payment_id=payment.id).one()
    assert receipt.amount == Decimal("300.00")
    assert receipt.whatsapp_status == "PENDING"
    assert "Severe infrastructure failure" in receipt.last_delivery_error
    db.close()
