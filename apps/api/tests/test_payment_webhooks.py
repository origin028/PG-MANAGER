import hashlib
import hmac
import json
import uuid
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
from unittest.mock import patch

import pytest
import sqlalchemy as sa

from app.core.config import settings
from app.models.invoice import Invoice
from app.models.payment import Payment
from app.models.property import Company, Property
from app.models.receipt import Receipt
from app.models.resident import Resident
from app.models.role import Role
from app.models.room import Room
from app.models.user import User
from app.models.webhook_event import ProcessedWebhookEvent


WEBHOOK_SECRET = "test_webhook_secret_12345"


def make_webhook_headers_and_body(event_type: str, order_id: str, payment_id: str, amount_paise: int, currency: str = "INR", event_id: str = None, method: str = "upi", secret: str = WEBHOOK_SECRET):
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
                    "currency": currency,
                    "status": "captured" if event_type == "payment.captured" else "failed",
                    "order_id": order_id,
                    "method": method,
                    "error_description": "Payment failed" if event_type == "payment.failed" else None,
                }
            }
        },
        "created_at": int(datetime.now().timestamp()),
        "event_id": event_id,
    }
    raw_body = json.dumps(payload_dict, separators=(",", ":")).encode("utf-8")
    sig = hmac.new(secret.encode("utf-8"), raw_body, hashlib.sha256).hexdigest()
    headers = {
        "X-Razorpay-Signature": sig,
        "Content-Type": "application/json",
    }
    return headers, raw_body, event_id


def seed_payment(session_factory, invoice_amount="100.00", initial_paid="0.00", payment_amount="100.00", order_id="order_webhook_test_1"):
    db = session_factory()
    company = Company(name="C_WH", code="C_WH")
    role = Role(name="RESIDENT", display_name="Resident")
    db.add_all((company, role))
    db.flush()

    user = User(company_id=company.id, role_id=role.id, phone=f"9100000{uuid.uuid4().hex[:3]}", full_name="Resident WH", password_hash="hash")
    db.add(user)
    db.flush()

    p = Property(company_id=company.id, name="Property WH", code=f"P_{uuid.uuid4().hex[:4]}", address_line1="wh", pincode="560001")
    db.add(p)
    db.flush()

    room = Room(property_id=p.id, room_number="101")
    db.add(room)
    db.flush()

    resident = Resident(user_id=user.id, property_id=p.id, room_id=room.id, check_in_date=date.today())
    db.add(resident)
    db.flush()

    invoice = Invoice(
        property_id=p.id,
        resident_id=resident.id,
        invoice_number=f"INV-{uuid.uuid4().hex[:8].upper()}",
        billing_month="2026-10",
        amount=Decimal(invoice_amount),
        paid_amount=Decimal(initial_paid),
        due_date=date.today(),
        status="PENDING",
    )
    db.add(invoice)
    db.flush()

    payment = Payment(
        property_id=p.id,
        invoice_id=invoice.id,
        resident_id=resident.id,
        payment_number=f"PAY-{uuid.uuid4().hex[:10].upper()}",
        amount=Decimal(payment_amount),
        payment_mode="UPI",
        gateway_order_id=order_id,
        status="PENDING",
        idempotency_key=f"idemp-{uuid.uuid4().hex[:10]}",
        reservation_expires_at=datetime.now(timezone.utc) + timedelta(minutes=15),
    )
    db.add(payment)
    db.commit()

    res = {
        "company_id": company.id,
        "property_id": p.id,
        "invoice_id": invoice.id,
        "resident_id": resident.id,
        "payment_id": payment.id,
        "order_id": order_id,
    }
    db.close()
    return res


def test_webhook_missing_or_invalid_signature_rejected(client, monkeypatch):
    monkeypatch.setattr(settings, "RAZORPAY_WEBHOOK_SECRET", WEBHOOK_SECRET)
    headers, raw_body, _ = make_webhook_headers_and_body(
        event_type="payment.captured",
        order_id="order_sig_test",
        payment_id="pay_sig_test",
        amount_paise=10000,
    )

    # 1. Missing signature header
    res_no_sig = client.post("/api/v1/payments/webhook/razorpay", content=raw_body)
    assert res_no_sig.status_code == 400
    msg = res_no_sig.json().get("error", {}).get("message", "") or res_no_sig.json().get("detail", "")
    assert "Missing" in msg

    # 2. Invalid signature
    res_bad_sig = client.post(
        "/api/v1/payments/webhook/razorpay",
        content=raw_body,
        headers={"X-Razorpay-Signature": "invalidsignaturehash", "Content-Type": "application/json"},
    )
    assert res_bad_sig.status_code == 400
    msg_bad = res_bad_sig.json().get("error", {}).get("message", "") or res_bad_sig.json().get("detail", "")
    assert "Invalid webhook signature" in msg_bad


def test_webhook_valid_successful_payment_settlement(client, monkeypatch):
    from app.main import app

    monkeypatch.setattr(settings, "RAZORPAY_WEBHOOK_SECRET", WEBHOOK_SECRET)
    ctx = seed_payment(app.state.testing_session, invoice_amount="100.00", payment_amount="100.00", order_id="order_success_1")

    headers, raw_body, evt_id = make_webhook_headers_and_body(
        event_type="payment.captured",
        order_id=ctx["order_id"],
        payment_id="pay_rzp_12345",
        amount_paise=10000,
        currency="INR",
        method="upi",
    )

    response = client.post("/api/v1/payments/webhook/razorpay", content=raw_body, headers=headers)
    assert response.status_code == 200
    assert response.json()["status"] == "ok"

    db = app.state.testing_session()
    payment = db.get(Payment, ctx["payment_id"])
    assert payment.status == "SUCCESS"
    assert payment.gateway_payment_id == "pay_rzp_12345"
    assert payment.paid_at is not None

    invoice = db.get(Invoice, ctx["invoice_id"])
    assert invoice.paid_amount == Decimal("100.00")
    assert invoice.status == "PAID"

    # Exactly one receipt created
    receipts = db.query(Receipt).filter_by(payment_id=payment.id).all()
    assert len(receipts) == 1
    receipt = receipts[0]
    assert receipt.amount == Decimal("100.00")
    assert receipt.receipt_number.startswith("RCT-")
    assert receipt.whatsapp_status == "PENDING"

    # Event ID recorded
    assert db.query(ProcessedWebhookEvent).filter_by(event_id=evt_id).count() == 1
    db.close()


def test_webhook_wrong_order_payment_amount_or_currency_rejected(client, monkeypatch):
    from app.main import app

    monkeypatch.setattr(settings, "RAZORPAY_WEBHOOK_SECRET", WEBHOOK_SECRET)
    ctx = seed_payment(app.state.testing_session, invoice_amount="100.00", payment_amount="100.00", order_id="order_chk_1")

    # 1. Non-existent order ID
    h1, b1, _ = make_webhook_headers_and_body(
        event_type="payment.captured",
        order_id="order_non_existent",
        payment_id="pay_non_exist",
        amount_paise=10000,
    )
    res1 = client.post("/api/v1/payments/webhook/razorpay", content=b1, headers=h1)
    assert res1.status_code == 400
    msg1 = res1.json().get("error", {}).get("message", "") or res1.json().get("detail", "")
    assert "No payment request found" in msg1

    # 2. Amount mismatch (expected 100.00, received 50.00)
    h2, b2, _ = make_webhook_headers_and_body(
        event_type="payment.captured",
        order_id=ctx["order_id"],
        payment_id="pay_mismatch_amt",
        amount_paise=5000,
    )
    res2 = client.post("/api/v1/payments/webhook/razorpay", content=b2, headers=h2)
    assert res2.status_code == 400
    msg2 = res2.json().get("error", {}).get("message", "") or res2.json().get("detail", "")
    assert "Amount mismatch" in msg2

    # 3. Currency mismatch (USD instead of INR)
    h3, b3, _ = make_webhook_headers_and_body(
        event_type="payment.captured",
        order_id=ctx["order_id"],
        payment_id="pay_mismatch_curr",
        amount_paise=10000,
        currency="USD",
    )
    res3 = client.post("/api/v1/payments/webhook/razorpay", content=b3, headers=h3)
    assert res3.status_code == 400
    msg3 = res3.json().get("error", {}).get("message", "") or res3.json().get("detail", "")
    assert "Unsupported currency" in msg3

    # Invoice and payment remain untouched
    db = app.state.testing_session()
    payment = db.get(Payment, ctx["payment_id"])
    assert payment.status == "PENDING"
    assert db.query(Receipt).count() == 0
    db.close()


def test_webhook_duplicate_delivery_is_safe_and_idempotent(client, monkeypatch):
    from app.main import app

    monkeypatch.setattr(settings, "RAZORPAY_WEBHOOK_SECRET", WEBHOOK_SECRET)
    ctx = seed_payment(app.state.testing_session, invoice_amount="100.00", payment_amount="100.00", order_id="order_dup_1")

    headers, raw_body, evt_id = make_webhook_headers_and_body(
        event_type="payment.captured",
        order_id=ctx["order_id"],
        payment_id="pay_dup_test_1",
        amount_paise=10000,
        event_id="evt_duplicate_delivery_123",
    )

    # First delivery
    res1 = client.post("/api/v1/payments/webhook/razorpay", content=raw_body, headers=headers)
    assert res1.status_code == 200

    # Second delivery with exact same webhook payload and event_id
    res2 = client.post("/api/v1/payments/webhook/razorpay", content=raw_body, headers=headers)
    assert res2.status_code == 200
    assert "already processed" in res2.json()["message"]

    db = app.state.testing_session()
    # No duplicate receipts or payments
    assert db.query(Receipt).count() == 1
    assert db.query(Payment).filter_by(id=ctx["payment_id"]).one().status == "SUCCESS"
    assert db.query(Invoice).filter_by(id=ctx["invoice_id"]).one().paid_amount == Decimal("100.00")
    db.close()


def test_webhook_multiple_events_for_same_payment(client, monkeypatch):
    from app.main import app

    monkeypatch.setattr(settings, "RAZORPAY_WEBHOOK_SECRET", WEBHOOK_SECRET)
    ctx = seed_payment(app.state.testing_session, invoice_amount="100.00", payment_amount="100.00", order_id="order_multi_evt_1")

    # First event: payment.captured (settles payment)
    h1, b1, _ = make_webhook_headers_and_body(
        event_type="payment.captured",
        order_id=ctx["order_id"],
        payment_id="pay_multi_1",
        amount_paise=10000,
        event_id="evt_cap_01",
    )
    res1 = client.post("/api/v1/payments/webhook/razorpay", content=b1, headers=h1)
    assert res1.status_code == 200

    # Second event: order.paid (different event type for the same order)
    h2, b2, _ = make_webhook_headers_and_body(
        event_type="order.paid",
        order_id=ctx["order_id"],
        payment_id="pay_multi_1",
        amount_paise=10000,
        event_id="evt_ord_02",
    )
    res2 = client.post("/api/v1/payments/webhook/razorpay", content=b2, headers=h2)
    assert res2.status_code == 200
    assert "acknowledged" in res2.json()["message"]

    # Third event: late payment.failed delivered after capture must NOT overwrite SUCCESS
    h3, b3, _ = make_webhook_headers_and_body(
        event_type="payment.failed",
        order_id=ctx["order_id"],
        payment_id="pay_multi_1",
        amount_paise=10000,
        event_id="evt_fail_03",
    )
    res3 = client.post("/api/v1/payments/webhook/razorpay", content=b3, headers=h3)
    assert res3.status_code == 200

    db = app.state.testing_session()
    payment = db.get(Payment, ctx["payment_id"])
    assert payment.status == "SUCCESS"
    assert db.query(Receipt).count() == 1
    db.close()


def test_webhook_pending_and_failed_events_do_not_settle_invoice(client, monkeypatch):
    from app.main import app

    monkeypatch.setattr(settings, "RAZORPAY_WEBHOOK_SECRET", WEBHOOK_SECRET)
    ctx = seed_payment(app.state.testing_session, invoice_amount="100.00", payment_amount="100.00", order_id="order_fail_test_1")

    # Send payment.failed event
    headers, raw_body, _ = make_webhook_headers_and_body(
        event_type="payment.failed",
        order_id=ctx["order_id"],
        payment_id="pay_failed_rzp_1",
        amount_paise=10000,
    )
    res = client.post("/api/v1/payments/webhook/razorpay", content=raw_body, headers=headers)
    assert res.status_code == 200

    db = app.state.testing_session()
    payment = db.get(Payment, ctx["payment_id"])
    assert payment.status == "FAILED"

    invoice = db.get(Invoice, ctx["invoice_id"])
    assert invoice.paid_amount == Decimal("0.00")
    assert invoice.status == "PENDING"
    assert db.query(Receipt).count() == 0
    db.close()


def test_webhook_partial_payment_invoice_calculations(client, monkeypatch):
    from app.main import app

    monkeypatch.setattr(settings, "RAZORPAY_WEBHOOK_SECRET", WEBHOOK_SECRET)
    # Total invoice 100, payment request for 40
    ctx = seed_payment(app.state.testing_session, invoice_amount="100.00", initial_paid="0.00", payment_amount="40.00", order_id="order_partial_1")

    headers, raw_body, _ = make_webhook_headers_and_body(
        event_type="payment.captured",
        order_id=ctx["order_id"],
        payment_id="pay_partial_rzp_1",
        amount_paise=4000,
    )
    res = client.post("/api/v1/payments/webhook/razorpay", content=raw_body, headers=headers)
    assert res.status_code == 200

    db = app.state.testing_session()
    invoice = db.get(Invoice, ctx["invoice_id"])
    assert invoice.paid_amount == Decimal("40.00")
    assert invoice.status == "PARTIALLY_PAID"

    receipt = db.query(Receipt).filter_by(payment_id=ctx["payment_id"]).one()
    assert receipt.amount == Decimal("40.00")
    db.close()


def test_webhook_expired_reservation_genuine_late_payment_success(client, monkeypatch):
    from app.main import app

    monkeypatch.setattr(settings, "RAZORPAY_WEBHOOK_SECRET", WEBHOOK_SECRET)
    ctx = seed_payment(app.state.testing_session, invoice_amount="100.00", payment_amount="100.00", order_id="order_late_1")

    # Payment reservation expired by background service earlier
    db = app.state.testing_session()
    payment = db.get(Payment, ctx["payment_id"])
    payment.status = "EXPIRED"
    payment.reservation_expires_at = datetime.now(timezone.utc) - timedelta(minutes=10)
    db.commit()
    db.close()

    # Razorpay sends payment.captured anyway (user completed payment late)
    headers, raw_body, _ = make_webhook_headers_and_body(
        event_type="payment.captured",
        order_id=ctx["order_id"],
        payment_id="pay_late_success_rzp",
        amount_paise=10000,
    )
    res = client.post("/api/v1/payments/webhook/razorpay", content=raw_body, headers=headers)
    assert res.status_code == 200

    # Must be reconciled as SUCCESS, not silently dropped
    db = app.state.testing_session()
    payment = db.get(Payment, ctx["payment_id"])
    assert payment.status == "SUCCESS"
    assert payment.gateway_payment_id == "pay_late_success_rzp"

    invoice = db.get(Invoice, ctx["invoice_id"])
    assert invoice.paid_amount == Decimal("100.00")
    assert invoice.status == "PAID"
    assert db.query(Receipt).filter_by(payment_id=payment.id).count() == 1
    db.close()


def test_webhook_rollback_on_receipt_failure(client, monkeypatch):
    from app.main import app
    from app.services.settlement_service import WebhookSettlementService

    monkeypatch.setattr(settings, "RAZORPAY_WEBHOOK_SECRET", WEBHOOK_SECRET)
    ctx = seed_payment(app.state.testing_session, invoice_amount="100.00", payment_amount="100.00", order_id="order_rollback_1")

    headers, raw_body, _ = make_webhook_headers_and_body(
        event_type="payment.captured",
        order_id=ctx["order_id"],
        payment_id="pay_rollback_rzp",
        amount_paise=10000,
    )

    # Force an exception during receipt creation / commit
    original_add = client.app.dependency_overrides

    def raise_db_error(*args, **kwargs):
        raise RuntimeError("Database failure during receipt persistence")

    with patch.object(Receipt, "__init__", side_effect=RuntimeError("Receipt creation crash")):
        with pytest.raises(RuntimeError, match="Receipt creation crash"):
            settlement_service = WebhookSettlementService(app.state.testing_session())
            settlement_service.settle_payment_captured(
                provider_order_id=ctx["order_id"],
                provider_payment_id="pay_rollback_rzp",
                amount_paise=10000,
                currency="INR",
            )

    # Confirm database state was not committed
    db = app.state.testing_session()
    payment = db.get(Payment, ctx["payment_id"])
    assert payment.status == "PENDING"
    invoice = db.get(Invoice, ctx["invoice_id"])
    assert invoice.paid_amount == Decimal("0.00")
    assert db.query(Receipt).count() == 0
    db.close()


def test_webhook_cross_property_association_mismatch(client, monkeypatch):
    from app.main import app

    monkeypatch.setattr(settings, "RAZORPAY_WEBHOOK_SECRET", WEBHOOK_SECRET)
    ctx = seed_payment(app.state.testing_session, invoice_amount="100.00", payment_amount="100.00", order_id="order_cross_prop")

    # Create a secondary property and reassign invoice to it, creating a mismatch
    db = app.state.testing_session()
    p2 = Property(company_id=ctx["company_id"], name="Prop 2", code="P2_X", address_line1="p2", pincode="560002")
    db.add(p2)
    db.flush()
    invoice = db.get(Invoice, ctx["invoice_id"])
    invoice.property_id = p2.id
    db.commit()
    db.close()

    headers, raw_body, _ = make_webhook_headers_and_body(
        event_type="payment.captured",
        order_id=ctx["order_id"],
        payment_id="pay_cross_prop",
        amount_paise=10000,
    )
    res = client.post("/api/v1/payments/webhook/razorpay", content=raw_body, headers=headers)
    assert res.status_code == 400
    msg = res.json().get("error", {}).get("message", "") or res.json().get("detail", "")
    assert "Property mismatch" in msg

    db = app.state.testing_session()
    assert db.get(Payment, ctx["payment_id"]).status == "PENDING"
    assert db.query(Receipt).count() == 0
    db.close()


def test_webhook_route_registration_and_openapi_schema(client):
    from app.api.v1.endpoints.payments import router as payments_router
    from app.main import app

    # 1. Assert endpoint exists in payments module router
    endpoint_paths = {
        route.path: route.methods
        for route in payments_router.routes
        if hasattr(route, "path")
    }
    assert "/webhook/razorpay" in endpoint_paths
    assert "POST" in endpoint_paths["/webhook/razorpay"]

    # 2. Assert OpenAPI schema documents the endpoint correctly
    openapi_schema = app.openapi()
    assert "/api/v1/payments/webhook/razorpay" in openapi_schema["paths"]
    path_item = openapi_schema["paths"]["/api/v1/payments/webhook/razorpay"]
    assert "post" in path_item
    assert "Payments & Ledger" in path_item["post"].get("tags", [])
    assert path_item["post"]["operationId"] == "handle_razorpay_webhook_api_v1_payments_webhook_razorpay_post"

    # 3. Assert no ghost/legacy routes exist in the OpenAPI paths
    assert "/api/v1/payments/me" not in openapi_schema["paths"]
    assert "/api/v1/payments/{payment_id}/refund" not in openapi_schema["paths"]

    # 4. Assert live routing through TestClient dispatches to webhook handler
    response = client.post("/api/v1/payments/webhook/razorpay")
    # Missing signature returns 400 with expected error structure (not 404 or 405)
    assert response.status_code == 400
    assert "Missing required X-Razorpay-Signature header" in response.text


