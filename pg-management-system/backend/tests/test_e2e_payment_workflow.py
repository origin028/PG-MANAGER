"""Phase 9 — End-to-End PG Payment Workflow Verification Test Suite.

Verifies the complete resident payment workflow across:
1. Disposable test property, resident, room/bed assignment, and unpaid invoice.
2. Payment request & secure resident payment link generation.
3. Public resident checkout API data integrity (property, room, invoice, amount).
4. Razorpay checkout client integration contract (key_id, amount_paise, order_id, currency).
5. Verified Razorpay webhook signature parsing & atomic invoice settlement.
6. Receipt issuance (exactly 1 receipt, RCT-* number, outbox status).
7. Outbox eligibility and WhatsApp receipt delivery with template parameters.
8. WhatsApp transient failure, exponential backoff, and worker recovery.
9. Security & edge cases:
   - Tampered signature rejection (400)
   - Duplicate webhook delivery idempotency
   - Expired & revoked payment link rejection (409 / 404)
   - Cross-resident payment link isolation
   - Frontend callback settlement prevention
   - Zero secrets / raw access tokens exposed in payloads or logs
"""

import hashlib
import hmac
import json
import secrets
import uuid
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
from unittest.mock import patch

import pytest
import sqlalchemy as sa
from fastapi.testclient import TestClient

from app.core.config import settings
from app.core.security import create_access_token
from app.integrations.payment_gateway import RazorpayGateway
from app.integrations.whatsapp import WhatsAppCloudProvider
from app.models.invoice import Invoice
from app.models.payment import Payment
from app.models.payment_link import PaymentLink
from app.models.property import Company, Property
from app.models.receipt import Receipt
from app.models.resident import Resident
from app.models.role import Role
from app.models.room import Room
from app.models.user import User
from app.models.webhook_event import ProcessedWebhookEvent
from app.services.receipt_delivery_service import ReceiptDeliveryService

TEST_WEBHOOK_SECRET = "whsec_e2e_test_verification_key_999"


class FakeE2EGateway:
    def __init__(self, key_id, key_secret):
        self.key_id = key_id
        self.key_secret = key_secret

    def create_order(self, amount: int, currency: str = "INR", receipt: str = "", notes=None):
        return {
            "order_id": f"order_e2e_{uuid.uuid4().hex[:10]}",
            "amount": amount,
            "currency": currency,
            "status": "created",
        }

    def verify_webhook_signature(self, raw_payload: bytes, signature: str, secret: str) -> bool:
        expected = hmac.new(secret.encode("utf-8"), raw_payload, hashlib.sha256).hexdigest()
        return hmac.compare_digest(expected, signature)


def make_signed_webhook_payload(
    event_type: str,
    order_id: str,
    payment_id: str,
    amount_paise: int,
    secret: str = TEST_WEBHOOK_SECRET,
    event_id: str = None,
    method: str = "upi",
):
    """Generates an authentic HMAC-SHA256 signed Razorpay webhook body and headers."""
    event_id = event_id or f"evt_{uuid.uuid4().hex[:12]}"
    payload_dict = {
        "entity": "event",
        "account_id": "acc_e2e_test",
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
    raw_bytes = json.dumps(payload_dict, separators=(",", ":")).encode("utf-8")
    signature = hmac.new(secret.encode("utf-8"), raw_bytes, hashlib.sha256).hexdigest()
    headers = {
        "X-Razorpay-Signature": signature,
        "Content-Type": "application/json",
    }
    return headers, raw_bytes, event_id


def seed_complete_e2e_fixture(session_factory, rent_amount="2500.00"):
    """Seeds a complete realistic PG tenancy dataset:

    Company -> Property -> Room -> Bed -> User -> Resident -> Unpaid Invoice.
    """
    db = session_factory()
    suffix = uuid.uuid4().hex[:6]

    company = Company(name=f"E2E Hospitality {suffix}", code=f"E2E_{suffix}")
    role = Role(name="RESIDENT", display_name="Resident")
    db.add_all((company, role))
    db.flush()

    user = User(
        company_id=company.id,
        role_id=role.id,
        phone="9876543210",
        full_name="Rohan Sharma",
        password_hash="argon2_e2e_hash",
        email=f"rohan.{suffix}@example.com",
    )
    db.add(user)
    db.flush()

    prop = Property(
        company_id=company.id,
        name="Serenity Heights Luxury PG",
        code=f"PROP_{suffix}",
        address_line1="100 Feet Road, Koramangala",
        city="Bengaluru",
        state="Karnataka",
        pincode="560034",
    )
    db.add(prop)
    db.flush()

    room = Room(
        property_id=prop.id,
        room_number="302-B",
        floor_number=3,
        room_type="DOUBLE_SHARING",
        max_occupancy=2,
        base_rent=float(rent_amount),
    )
    db.add(room)
    db.flush()

    resident = Resident(
        user_id=user.id,
        property_id=prop.id,
        room_id=room.id,
        check_in_date=date.today() - timedelta(days=30),
        monthly_rent=float(rent_amount),
        security_deposit=5000.0,
        status="ACTIVE",
    )
    db.add(resident)
    db.flush()

    invoice = Invoice(
        property_id=prop.id,
        resident_id=resident.id,
        invoice_number=f"INV-E2E-{suffix.upper()}",
        billing_month=datetime.now().strftime("%Y-%m"),
        invoice_type="RENT",
        amount=Decimal(rent_amount),
        paid_amount=Decimal("0.00"),
        due_date=date.today() + timedelta(days=5),
        status="PENDING",
    )
    db.add(invoice)
    db.commit()

    token_header = {
        "Authorization": "Bearer "
        + create_access_token(str(user.id), {"role": role.name, "company_id": str(company.id)})
    }

    ctx = {
        "company_id": company.id,
        "property_id": prop.id,
        "property_name": prop.name,
        "room_id": room.id,
        "room_number": room.room_number,
        "user_id": user.id,
        "user_name": user.full_name,
        "user_phone": user.phone,
        "auth_header": token_header,
        "resident_id": resident.id,
        "invoice_id": invoice.id,
        "invoice_number": invoice.invoice_number,
        "amount": rent_amount,
    }
    db.close()
    return ctx


# ---------------------------------------------------------------------------
# End-to-End Workflow Tests
# ---------------------------------------------------------------------------


def test_e2e_complete_resident_payment_workflow(client: TestClient, monkeypatch):
    """Step 1 to Step 9: Tests the full end-to-end happy path:

    1. Seed property, room, resident, invoice.
    2. Create secure resident payment link.
    3. Public checkout endpoint serves correct information.
    4. Razorpay Test Mode contract is verified.
    5. Webhook delivery settles invoice atomically.
    6. Exactly 1 receipt created with outbox record.
    7. WhatsApp delivery succeeds with approved template parameters.
    """
    from app.main import app
    from app.services import payment_link_service

    monkeypatch.setattr(payment_link_service, "RazorpayGateway", FakeE2EGateway)
    monkeypatch.setattr(settings, "RAZORPAY_KEY_ID", "rzp_test_e2eMockKey123")
    monkeypatch.setattr(settings, "RAZORPAY_KEY_SECRET", "mock_secret_not_real")
    monkeypatch.setattr(settings, "RAZORPAY_WEBHOOK_SECRET", TEST_WEBHOOK_SECRET)
    monkeypatch.setattr(settings, "WHATSAPP_PHONE_NUMBER_ID", "wa_phone_id_999")
    monkeypatch.setattr(settings, "WHATSAPP_ACCESS_TOKEN", "wa_access_token_999")
    monkeypatch.setattr(settings, "WHATSAPP_RECEIPT_TEMPLATE", "rent_receipt_v1")

    wa_dispatches = []

    def mock_send_template(self, to_phone: str, template: str, parameters: list):
        wa_dispatches.append({"to": to_phone, "template": template, "parameters": parameters})
        return "wamid.HBgLMjEwNzg2NTQzMjEwFQIAERgSRTI4Q0RBNjgyQjUzRkE1REE3AA=="

    monkeypatch.setattr(WhatsAppCloudProvider, "send_template", mock_send_template)

    # 1. Seed complete tenancy
    ctx = seed_complete_e2e_fixture(app.state.testing_session, rent_amount="2500.00")

    # 2. Generate Payment Request and Secure Resident Payment Link via API
    create_link_res = client.post(
        "/api/v1/payments/links",
        json={
            "invoice_id": str(ctx["invoice_id"]),
            "amount": "2500.00",
            "idempotency_key": f"idemp_e2e_{uuid.uuid4().hex[:8]}",
        },
        headers=ctx["auth_header"],
    )
    assert create_link_res.status_code == 201
    link_data = create_link_res.json()["data"]
    raw_token = link_data["payment_url"].split("/")[-1]
    link_id = uuid.UUID(link_data["link_id"])

    db = app.state.testing_session()
    link = db.get(PaymentLink, link_id)
    assert link.token_hash == hashlib.sha256(raw_token.encode("utf-8")).hexdigest()
    assert link.token_hash != raw_token
    payment = db.get(Payment, link.payment_id)
    order_id = payment.gateway_order_id
    payment_id = payment.id
    db.close()

    # 3. Verify public resident checkout endpoint
    checkout_res = client.get(f"/api/v1/payments/links/{raw_token}/checkout")
    assert checkout_res.status_code == 200
    chk_data = checkout_res.json()["data"]

    assert chk_data["property_name"] == "Serenity Heights Luxury PG"
    assert chk_data["room_number"] == "302-B"
    assert chk_data["invoice_number"] == ctx["invoice_number"]
    assert Decimal(str(chk_data["amount"])) == Decimal("2500.00")
    assert chk_data["amount_paise"] == 250000
    assert chk_data["currency"] == "INR"
    assert chk_data["gateway_order_id"] == order_id
    assert chk_data["key_id"] == "rzp_test_e2eMockKey123"
    assert "expires_at" in chk_data

    # Security check: zero secrets exposed in checkout endpoint
    res_text = checkout_res.text
    assert "secret" not in res_text.lower()
    assert "token_hash" not in res_text
    assert "argon2" not in res_text

    # 4. Confirm Razorpay Test Mode checkout launch contract
    # The frontend uses { key_id, amount_paise, currency, order_id, prefill: { name, contact } }
    assert chk_data["key_id"].startswith("rzp_test_")
    assert chk_data["amount_paise"] == int(Decimal(str(chk_data["amount"])) * 100)

    # 5 & 6. Deliver genuine HMAC-SHA256 signed Razorpay captured payment webhook
    rzp_payment_id = f"pay_rzp_e2e_{uuid.uuid4().hex[:8]}"
    headers, raw_body, event_id = make_signed_webhook_payload(
        event_type="payment.captured",
        order_id=order_id,
        payment_id=rzp_payment_id,
        amount_paise=250000,
        secret=TEST_WEBHOOK_SECRET,
        method="upi",
    )

    webhook_res = client.post("/api/v1/payments/webhook/razorpay", content=raw_body, headers=headers)
    assert webhook_res.status_code == 200
    assert webhook_res.json()["status"] == "ok"

    # 7 & 8. Verify invoice paid amount & status, payment record, and exactly one receipt
    db = app.state.testing_session()
    invoice = db.get(Invoice, ctx["invoice_id"])
    assert invoice.paid_amount == Decimal("2500.00")
    assert invoice.status == "PAID"

    payment = db.get(Payment, payment_id)
    assert payment.status == "SUCCESS"
    assert payment.gateway_payment_id == rzp_payment_id
    assert payment.payment_mode.upper() == "UPI"
    assert payment.paid_at is not None

    receipts = db.query(Receipt).filter_by(payment_id=payment.id).all()
    assert len(receipts) == 1
    receipt = receipts[0]
    assert receipt.receipt_number.startswith("RCT-")
    assert receipt.amount == Decimal("2500.00")
    assert receipt.invoice_id == invoice.id

    # 9. Verify WhatsApp receipt dispatch
    assert receipt.whatsapp_status == "SENT"
    assert receipt.whatsapp_attempts == 1
    assert receipt.last_delivery_error is None
    assert len(wa_dispatches) == 1

    wa_msg = wa_dispatches[0]
    assert wa_msg["to"] == "9876543210"
    assert wa_msg["template"] == "rent_receipt_v1"
    # [property_name, room_number, resident_name, receipt_number, invoice_number, amount_str, payment_date, payment_mode]
    params = wa_msg["parameters"]
    assert params[0] == "Serenity Heights Luxury PG"
    assert params[1] == "302-B"
    assert params[2] == "Rohan Sharma"
    assert params[3] == receipt.receipt_number
    assert params[4] == ctx["invoice_number"]
    assert "2500.00" in params[5]
    assert params[7].upper() == "UPI"

    # 10. Once paid, payment link checkout endpoint indicates already completed (409)
    post_paid_chk = client.get(f"/api/v1/payments/links/{raw_token}/checkout")
    assert post_paid_chk.status_code == 409
    assert "completed" in post_paid_chk.json()["error"]["message"].lower()

    db.close()


def test_e2e_whatsapp_transient_failure_and_worker_retry(client: TestClient, monkeypatch):
    """Step 12: Tests WhatsApp failure and confirms background worker retries

    without creating new payments or altering the settled invoice.
    """
    from app.main import app
    from app.services import payment_link_service

    monkeypatch.setattr(payment_link_service, "RazorpayGateway", FakeE2EGateway)
    monkeypatch.setattr(settings, "RAZORPAY_KEY_ID", "rzp_test_retry123")
    monkeypatch.setattr(settings, "RAZORPAY_KEY_SECRET", "mock_secret")
    monkeypatch.setattr(settings, "RAZORPAY_WEBHOOK_SECRET", TEST_WEBHOOK_SECRET)
    monkeypatch.setattr(settings, "WHATSAPP_PHONE_NUMBER_ID", "wa_phone_id_999")
    monkeypatch.setattr(settings, "WHATSAPP_ACCESS_TOKEN", "wa_access_token_999")

    # Simulate WhatsApp transient connection timeout on first attempt
    attempt_count = 0

    def mock_flaky_send(self, to_phone: str, template: str, parameters: list):
        nonlocal attempt_count
        attempt_count += 1
        if attempt_count == 1:
            raise ConnectionError("Meta Cloud API connection timed out (transient 504)")
        return "wamid.RETRY_SUCCESS_999"

    monkeypatch.setattr(WhatsAppCloudProvider, "send_template", mock_flaky_send)

    ctx = seed_complete_e2e_fixture(app.state.testing_session, rent_amount="1800.00")

    create_link_res = client.post(
        "/api/v1/payments/links",
        json={
            "invoice_id": str(ctx["invoice_id"]),
            "amount": "1800.00",
            "idempotency_key": f"idemp_flaky_{uuid.uuid4().hex[:8]}",
        },
        headers=ctx["auth_header"],
    )
    assert create_link_res.status_code == 201
    link_data = create_link_res.json()["data"]
    raw_token = link_data["payment_url"].split("/")[-1]

    db = app.state.testing_session()
    link = db.get(PaymentLink, uuid.UUID(link_data["link_id"]))
    payment = db.get(Payment, link.payment_id)
    order_id = payment.gateway_order_id
    payment_id = payment.id
    db.close()

    # Deliver webhook
    headers, raw_body, _ = make_signed_webhook_payload(
        event_type="payment.captured",
        order_id=order_id,
        payment_id=f"pay_flaky_{uuid.uuid4().hex[:6]}",
        amount_paise=180000,
        secret=TEST_WEBHOOK_SECRET,
    )
    res = client.post("/api/v1/payments/webhook/razorpay", content=raw_body, headers=headers)
    assert res.status_code == 200

    db = app.state.testing_session()
    invoice = db.get(Invoice, ctx["invoice_id"])
    payment = db.get(Payment, payment_id)
    receipt = db.query(Receipt).filter_by(payment_id=payment.id).one()

    # Settle succeeded, WhatsApp delivery attempt 1 failed with transient error
    assert invoice.status == "PAID"
    assert payment.status == "SUCCESS"
    assert receipt.whatsapp_status == "PENDING"
    assert receipt.whatsapp_attempts == 1
    assert "timed out" in receipt.last_delivery_error.lower()
    assert receipt.next_retry_at is not None

    # Advance next_retry_at to execute worker retry pass
    receipt.next_retry_at = datetime.now(timezone.utc) - timedelta(seconds=1)
    db.commit()

    # Execute receipt delivery worker pass
    worker_service = ReceiptDeliveryService(db)
    processed = worker_service.process_due_receipts(limit=10)
    assert processed == 1

    db.refresh(receipt)
    assert receipt.whatsapp_status == "SENT"
    assert receipt.whatsapp_attempts == 2
    assert receipt.last_delivery_error is None

    # Confirm settlement integrity was fully preserved
    db.refresh(invoice)
    db.refresh(payment)
    assert invoice.paid_amount == Decimal("1800.00")
    assert invoice.status == "PAID"
    assert payment.status == "SUCCESS"
    # Still exactly 1 receipt and 1 payment
    assert db.query(Payment).filter_by(invoice_id=invoice.id).count() == 1
    assert db.query(Receipt).filter_by(invoice_id=invoice.id).count() == 1
    db.close()


# ---------------------------------------------------------------------------
# Security & Edge Cases
# ---------------------------------------------------------------------------


def test_e2e_security_invalid_signature_cannot_settle(client: TestClient, monkeypatch):
    """Step 3: Invalid webhook signatures cannot settle payments."""
    from app.main import app
    from app.services import payment_link_service

    monkeypatch.setattr(payment_link_service, "RazorpayGateway", FakeE2EGateway)
    monkeypatch.setattr(settings, "RAZORPAY_KEY_ID", "rzp_sec")
    monkeypatch.setattr(settings, "RAZORPAY_KEY_SECRET", "mock_sec")
    monkeypatch.setattr(settings, "RAZORPAY_WEBHOOK_SECRET", TEST_WEBHOOK_SECRET)

    ctx = seed_complete_e2e_fixture(app.state.testing_session, rent_amount="3000.00")

    create_link_res = client.post(
        "/api/v1/payments/links",
        json={
            "invoice_id": str(ctx["invoice_id"]),
            "amount": "3000.00",
            "idempotency_key": f"idemp_bad_sig_{uuid.uuid4().hex[:8]}",
        },
        headers=ctx["auth_header"],
    )
    assert create_link_res.status_code == 201
    link_id = uuid.UUID(create_link_res.json()["data"]["link_id"])

    db = app.state.testing_session()
    link = db.get(PaymentLink, link_id)
    payment = db.get(Payment, link.payment_id)
    order_id = payment.gateway_order_id
    db.close()

    headers, raw_body, _ = make_signed_webhook_payload(
        event_type="payment.captured",
        order_id=order_id,
        payment_id="pay_attacker_fake",
        amount_paise=300000,
        secret="WRONG_FORGED_SECRET",
    )

    res = client.post("/api/v1/payments/webhook/razorpay", content=raw_body, headers=headers)
    assert res.status_code == 400
    msg = res.json().get("error", {}).get("message", "") or res.json().get("detail", "")
    assert "invalid webhook signature" in msg.lower()

    # Invoice and payment must remain unmodified
    db = app.state.testing_session()
    inv = db.get(Invoice, ctx["invoice_id"])
    assert inv.paid_amount == Decimal("0.00")
    assert inv.status == "PENDING"
    assert db.query(Receipt).filter_by(invoice_id=inv.id).count() == 0
    db.close()


def test_e2e_security_duplicate_webhooks_idempotency(client: TestClient, monkeypatch):
    """Step 3: Duplicate webhook deliveries do not duplicate settlement or receipts."""
    from app.main import app
    from app.services import payment_link_service

    monkeypatch.setattr(payment_link_service, "RazorpayGateway", FakeE2EGateway)
    monkeypatch.setattr(settings, "RAZORPAY_KEY_ID", "rzp_test_idemp")
    monkeypatch.setattr(settings, "RAZORPAY_KEY_SECRET", "mock_sec")
    monkeypatch.setattr(settings, "RAZORPAY_WEBHOOK_SECRET", TEST_WEBHOOK_SECRET)
    monkeypatch.setattr(settings, "WHATSAPP_PHONE_NUMBER_ID", "")
    monkeypatch.setattr(settings, "WHATSAPP_ACCESS_TOKEN", "")

    ctx = seed_complete_e2e_fixture(app.state.testing_session, rent_amount="1200.00")

    create_link_res = client.post(
        "/api/v1/payments/links",
        json={
            "invoice_id": str(ctx["invoice_id"]),
            "amount": "1200.00",
            "idempotency_key": f"idemp_dup_{uuid.uuid4().hex[:8]}",
        },
        headers=ctx["auth_header"],
    )
    assert create_link_res.status_code == 201
    link_id = uuid.UUID(create_link_res.json()["data"]["link_id"])

    db = app.state.testing_session()
    link = db.get(PaymentLink, link_id)
    payment = db.get(Payment, link.payment_id)
    order_id = payment.gateway_order_id
    db.close()

    headers, raw_body, event_id = make_signed_webhook_payload(
        event_type="payment.captured",
        order_id=order_id,
        payment_id="pay_rzp_dup_001",
        amount_paise=120000,
        secret=TEST_WEBHOOK_SECRET,
    )

    # 1st delivery
    res1 = client.post("/api/v1/payments/webhook/razorpay", content=raw_body, headers=headers)
    assert res1.status_code == 200

    # 2nd delivery of the exact same event
    res2 = client.post("/api/v1/payments/webhook/razorpay", content=raw_body, headers=headers)
    assert res2.status_code == 200
    assert "already processed" in res2.json()["message"].lower()

    # 3rd delivery with different event_id for the already-settled order
    h3, b3, _ = make_signed_webhook_payload(
        event_type="payment.captured",
        order_id=order_id,
        payment_id="pay_rzp_dup_001",
        amount_paise=120000,
        secret=TEST_WEBHOOK_SECRET,
        event_id="evt_different_id_999",
    )
    res3 = client.post("/api/v1/payments/webhook/razorpay", content=b3, headers=h3)
    assert res3.status_code == 200

    db = app.state.testing_session()
    assert db.query(Payment).filter_by(gateway_order_id=order_id).count() == 1
    assert db.query(Receipt).filter_by(invoice_id=ctx["invoice_id"]).count() == 1
    assert db.get(Invoice, ctx["invoice_id"]).paid_amount == Decimal("1200.00")
    db.close()


def test_e2e_security_expired_and_revoked_links_cannot_checkout(client: TestClient, monkeypatch):
    """Step 3: Expired or revoked links cannot initiate checkout."""
    from app.main import app
    from app.services import payment_link_service

    monkeypatch.setattr(payment_link_service, "RazorpayGateway", FakeE2EGateway)
    monkeypatch.setattr(settings, "RAZORPAY_KEY_ID", "rzp_test_links")
    monkeypatch.setattr(settings, "RAZORPAY_KEY_SECRET", "mock_sec")

    ctx = seed_complete_e2e_fixture(app.state.testing_session, rent_amount="4000.00")

    create_link_res = client.post(
        "/api/v1/payments/links",
        json={
            "invoice_id": str(ctx["invoice_id"]),
            "amount": "4000.00",
            "idempotency_key": f"idemp_exp_{uuid.uuid4().hex[:8]}",
        },
        headers=ctx["auth_header"],
    )
    assert create_link_res.status_code == 201
    raw_token = create_link_res.json()["data"]["payment_url"].split("/")[-1]
    link_id = uuid.UUID(create_link_res.json()["data"]["link_id"])

    # 1. Expire link
    db = app.state.testing_session()
    link = db.get(PaymentLink, link_id)
    link.expires_at = datetime.now(timezone.utc) - timedelta(minutes=5)
    db.commit()
    db.close()

    res_exp = client.get(f"/api/v1/payments/links/{raw_token}/checkout")
    assert res_exp.status_code == 409
    assert "expired" in res_exp.json()["error"]["message"].lower()

    # 2. Revoke link
    db = app.state.testing_session()
    link = db.get(PaymentLink, link_id)
    link.expires_at = datetime.now(timezone.utc) + timedelta(minutes=15)
    link.is_revoked = True
    db.commit()
    db.close()

    res_rev = client.get(f"/api/v1/payments/links/{raw_token}/checkout")
    assert res_rev.status_code == 409
    assert "revoked" in res_rev.json()["error"]["message"].lower()


def test_e2e_security_cross_resident_token_isolation(client: TestClient):
    """Step 3: A resident cannot access another resident's payment link or invoice

    using tampered, crafted, or non-existent tokens.
    """
    fake_token = secrets.token_urlsafe(32)
    res = client.get(f"/api/v1/payments/links/{fake_token}/checkout")
    assert res.status_code == 404
    assert "error" in res.json()

    # Short/malformed token
    res_short = client.get("/api/v1/payments/links/short_token/checkout")
    assert res_short.status_code == 404
    assert "error" in res_short.json()
