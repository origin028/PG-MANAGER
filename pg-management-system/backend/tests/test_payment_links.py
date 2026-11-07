import hashlib
import json
import uuid
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
from unittest.mock import MagicMock, patch

import pytest
import sqlalchemy as sa

from app.core.config import settings
from app.core.security import create_access_token, get_password_hash
from app.models.invoice import Invoice
from app.models.payment import Payment
from app.models.payment_link import PaymentLink
from app.models.property import Company, Property
from app.models.resident import Resident
from app.models.role import Role
from app.models.room import Room
from app.models.user import User, UserPropertyAccess
from app.services.payment_link_service import hash_token


class FakeGateway:
    def __init__(self, *_):
        pass

    def create_order(self, amount, currency, receipt, notes):
        return {"order_id": "order_link_test", "amount": amount, "currency": currency, "status": "created"}


def seed_data(session_factory):
    db = session_factory()
    company = Company(name="C_Link", code=f"C_{uuid.uuid4().hex[:4]}")
    admin_role = Role(name="SUPER_ADMIN", display_name="Admin")
    resident_role = Role(name="RESIDENT", display_name="Resident")
    db.add_all((company, admin_role, resident_role))
    db.flush()

    def user(role, phone):
        u = User(
            company_id=company.id,
            role_id=role.id,
            phone=phone,
            full_name=f"User {phone}",
            password_hash=get_password_hash("pass"),
        )
        db.add(u)
        db.flush()
        return u

    admin = user(admin_role, "9900000001")
    resident_u1 = user(resident_role, "9900000002")
    resident_u2 = user(resident_role, "9900000003")

    prop = Property(
        company_id=company.id,
        name="Serenity PG",
        code=f"P_{uuid.uuid4().hex[:4]}",
        address_line1="Koramangala",
        pincode="560034",
    )
    db.add(prop)
    db.flush()

    room = Room(property_id=prop.id, room_number="204")
    db.add(room)
    db.flush()

    r1 = Resident(user_id=resident_u1.id, property_id=prop.id, room_id=room.id, check_in_date=date.today())
    r2 = Resident(user_id=resident_u2.id, property_id=prop.id, room_id=room.id, check_in_date=date.today())
    db.add_all((r1, r2))
    db.flush()

    inv = Invoice(
        property_id=prop.id,
        resident_id=r1.id,
        invoice_number="INV-LINK-01",
        billing_month="2026-10",
        amount=Decimal("150.00"),
        paid_amount=Decimal("0.00"),
        due_date=date.today(),
        status="PENDING",
    )
    db.add(inv)
    db.commit()

    token = lambda u, role: {
        "Authorization": "Bearer "
        + create_access_token(str(u.id), {"role": role.name, "company_id": str(company.id)})
    }
    res = {
        "company_id": company.id,
        "property_id": prop.id,
        "property_name": prop.name,
        "room_number": room.room_number,
        "admin_auth": token(admin, admin_role),
        "owner_auth": token(resident_u1, resident_role),
        "other_auth": token(resident_u2, resident_role),
        "invoice_id": inv.id,
        "resident_1_id": r1.id,
        "resident_2_id": r2.id,
    }
    db.close()
    return res


def test_payment_link_generation_and_authorization(client, monkeypatch):
    from app.main import app
    from app.services import payment_link_service

    monkeypatch.setattr(payment_link_service, "RazorpayGateway", FakeGateway)
    monkeypatch.setattr(settings, "RAZORPAY_KEY_ID", "rzp_id")
    monkeypatch.setattr(settings, "RAZORPAY_KEY_SECRET", "rzp_secret")
    ctx = seed_data(app.state.testing_session)

    # 1. Unauthenticated request rejected
    res_unauth = client.post(
        "/api/v1/payments/links",
        json={"invoice_id": str(ctx["invoice_id"]), "amount": "100.00", "idempotency_key": "key-link-001"},
    )
    assert res_unauth.status_code == 401

    # 2. Resident trying to generate payment link for another resident's invoice rejected (403)
    res_other = client.post(
        "/api/v1/payments/links",
        json={"invoice_id": str(ctx["invoice_id"]), "amount": "100.00", "idempotency_key": "key-link-002"},
        headers=ctx["other_auth"],
    )
    assert res_other.status_code == 403

    # 3. Legitimate resident generates payment link
    res_owner = client.post(
        "/api/v1/payments/links",
        json={"invoice_id": str(ctx["invoice_id"]), "amount": "100.00", "idempotency_key": "key-link-003"},
        headers=ctx["owner_auth"],
    )
    assert res_owner.status_code == 201
    data = res_owner.json()["data"]
    assert "payment_url" in data
    assert data["payment_url"].startswith(settings.PAYMENT_LINK_BASE_URL.rstrip("/"))

    raw_token = data["payment_url"].split("/")[-1]
    # Check that database stores only the hash
    db = app.state.testing_session()
    link = db.get(PaymentLink, uuid.UUID(data["link_id"]))
    assert link.token_hash == hash_token(raw_token)
    assert link.token_hash != raw_token
    db.close()


def test_public_payment_link_checkout_details(client, monkeypatch):
    from app.main import app
    from app.services import payment_link_service

    monkeypatch.setattr(payment_link_service, "RazorpayGateway", FakeGateway)
    monkeypatch.setattr(settings, "RAZORPAY_KEY_ID", "rzp_public_key_123")
    monkeypatch.setattr(settings, "RAZORPAY_KEY_SECRET", "rzp_secret_456")
    ctx = seed_data(app.state.testing_session)

    res = client.post(
        "/api/v1/payments/links",
        json={"invoice_id": str(ctx["invoice_id"]), "amount": "80.00", "idempotency_key": "key-checkout-001"},
        headers=ctx["owner_auth"],
    )
    assert res.status_code == 201
    payment_url = res.json()["data"]["payment_url"]
    raw_token = payment_url.split("/")[-1]

    # Public checkout query (unauthenticated)
    res_pub = client.get(f"/api/v1/payments/links/{raw_token}/checkout")
    assert res_pub.status_code == 200
    pub_data = res_pub.json()["data"]

    # Verify exposed fields
    assert pub_data["property_name"] == ctx["property_name"]
    assert pub_data["room_number"] == ctx["room_number"]
    assert Decimal(str(pub_data["amount"])) == Decimal("80.00")
    assert pub_data["amount_paise"] == 8000
    assert pub_data["currency"] == "INR"
    assert pub_data["key_id"] == "rzp_public_key_123"
    assert pub_data["gateway_order_id"] == "order_link_test"

    # Verify NO secrets or database IDs are leaked
    assert "rzp_secret_456" not in res_pub.text
    assert str(ctx["invoice_id"]) not in res_pub.text
    assert str(ctx["resident_1_id"]) not in res_pub.text


def test_payment_link_expired_and_revoked(client, monkeypatch):
    from app.main import app
    from app.services import payment_link_service

    monkeypatch.setattr(payment_link_service, "RazorpayGateway", FakeGateway)
    monkeypatch.setattr(settings, "RAZORPAY_KEY_ID", "rzp_id")
    monkeypatch.setattr(settings, "RAZORPAY_KEY_SECRET", "rzp_secret")
    ctx = seed_data(app.state.testing_session)

    res = client.post(
        "/api/v1/payments/links",
        json={"invoice_id": str(ctx["invoice_id"]), "amount": "50.00", "idempotency_key": "key-exp-001"},
        headers=ctx["owner_auth"],
    )
    raw_token = res.json()["data"]["payment_url"].split("/")[-1]
    link_id = uuid.UUID(res.json()["data"]["link_id"])

    # 1. Expired link
    db = app.state.testing_session()
    link = db.get(PaymentLink, link_id)
    link.expires_at = datetime.now(timezone.utc) - timedelta(minutes=5)
    db.commit()
    db.close()

    res_exp = client.get(f"/api/v1/payments/links/{raw_token}/checkout")
    assert res_exp.status_code == 409
    assert "expired" in res_exp.json()["error"]["message"].lower()

    # 2. Revoked link
    db = app.state.testing_session()
    link = db.get(PaymentLink, link_id)
    link.expires_at = datetime.now(timezone.utc) + timedelta(minutes=15)
    link.is_revoked = True
    db.commit()
    db.close()

    res_rev = client.get(f"/api/v1/payments/links/{raw_token}/checkout")
    assert res_rev.status_code == 409
    assert "revoked" in res_rev.json()["error"]["message"].lower()

    # 3. Invalid token
    res_inv = client.get("/api/v1/payments/links/nonexistenttoken123/checkout")
    assert res_inv.status_code == 404


def test_payment_link_already_paid_invoice(client, monkeypatch):
    from app.main import app
    from app.services import payment_link_service

    monkeypatch.setattr(payment_link_service, "RazorpayGateway", FakeGateway)
    monkeypatch.setattr(settings, "RAZORPAY_KEY_ID", "rzp_id")
    monkeypatch.setattr(settings, "RAZORPAY_KEY_SECRET", "rzp_secret")
    ctx = seed_data(app.state.testing_session)

    res = client.post(
        "/api/v1/payments/links",
        json={"invoice_id": str(ctx["invoice_id"]), "amount": "50.00", "idempotency_key": "key-paid-001"},
        headers=ctx["owner_auth"],
    )
    raw_token = res.json()["data"]["payment_url"].split("/")[-1]

    # Settle payment to SUCCESS / invoice to PAID
    db = app.state.testing_session()
    invoice = db.get(Invoice, ctx["invoice_id"])
    invoice.status = "PAID"
    invoice.paid_amount = invoice.amount
    payment = db.query(Payment).filter_by(invoice_id=invoice.id).one()
    payment.status = "SUCCESS"
    db.commit()
    db.close()

    res_check = client.get(f"/api/v1/payments/links/{raw_token}/checkout")
    assert res_check.status_code == 409
    assert "already been completed" in res_check.json()["error"]["message"].lower()


def test_payment_link_tampering_prevented(client, monkeypatch):
    from app.main import app
    from app.services import payment_link_service

    monkeypatch.setattr(payment_link_service, "RazorpayGateway", FakeGateway)
    monkeypatch.setattr(settings, "RAZORPAY_KEY_ID", "rzp_id")
    monkeypatch.setattr(settings, "RAZORPAY_KEY_SECRET", "rzp_secret")
    ctx = seed_data(app.state.testing_session)

    # Attempting to exceed invoice balance
    res = client.post(
        "/api/v1/payments/links",
        json={"invoice_id": str(ctx["invoice_id"]), "amount": "9999.00", "idempotency_key": "key-tamper-001"},
        headers=ctx["owner_auth"],
    )
    assert res.status_code == 409
    assert "exceeds" in res.json()["error"]["message"].lower()


def test_whatsapp_dispatch_success_with_template_parameters(client, monkeypatch):
    from app.main import app
    from app.services import payment_link_service
    from app.integrations.whatsapp import WhatsAppCloudProvider

    monkeypatch.setattr(payment_link_service, "RazorpayGateway", FakeGateway)
    monkeypatch.setattr(settings, "RAZORPAY_KEY_ID", "rzp_id")
    monkeypatch.setattr(settings, "RAZORPAY_KEY_SECRET", "rzp_secret")
    monkeypatch.setattr(settings, "WHATSAPP_PHONE_NUMBER_ID", "123456789")
    monkeypatch.setattr(settings, "WHATSAPP_ACCESS_TOKEN", "wa_token_secret")
    monkeypatch.setattr(settings, "WHATSAPP_PAYMENT_TEMPLATE", "rent_payment_due_v1")

    sent_calls = []

    def fake_send_template(self, to_phone: str, template: str, parameters: list[str]):
        sent_calls.append({"to": to_phone, "template": template, "params": parameters})
        return "wamid_test_12345"

    monkeypatch.setattr(WhatsAppCloudProvider, "send_template", fake_send_template)

    ctx = seed_data(app.state.testing_session)

    res = client.post(
        "/api/v1/payments/links",
        json={
            "invoice_id": str(ctx["invoice_id"]),
            "amount": "120.00",
            "idempotency_key": "key-wa-001",
            "send_whatsapp": True,
        },
        headers=ctx["admin_auth"],
    )
    assert res.status_code == 201
    data = res.json()["data"]
    assert data["whatsapp_sent"] is True
    assert data["whatsapp_message_id"] == "wamid_test_12345"

    # Verify template parameters
    assert len(sent_calls) == 1
    call = sent_calls[0]
    assert call["to"] == "9900000002"
    assert call["template"] == "rent_payment_due_v1"
    # [property_name, room_number, amount, link_url]
    assert call["params"][0] == "Serenity PG"
    assert call["params"][1] == "204"
    assert "120.00" in call["params"][2]
    assert data["payment_url"] == call["params"][3]


def test_whatsapp_configuration_or_provider_failure(client, monkeypatch):
    from app.main import app
    from app.services import payment_link_service
    from app.integrations.whatsapp import WhatsAppCloudProvider

    monkeypatch.setattr(payment_link_service, "RazorpayGateway", FakeGateway)
    monkeypatch.setattr(settings, "RAZORPAY_KEY_ID", "rzp_id")
    monkeypatch.setattr(settings, "RAZORPAY_KEY_SECRET", "rzp_secret")
    # Unconfigured WhatsApp credentials
    monkeypatch.setattr(settings, "WHATSAPP_PHONE_NUMBER_ID", "")
    monkeypatch.setattr(settings, "WHATSAPP_ACCESS_TOKEN", "")

    ctx = seed_data(app.state.testing_session)

    # When WhatsApp is not configured, requesting WhatsApp delivery raises 503 error and fails safely
    res = client.post(
        "/api/v1/payments/links",
        json={
            "invoice_id": str(ctx["invoice_id"]),
            "amount": "100.00",
            "idempotency_key": "key-wa-fail-001",
            "send_whatsapp": True,
        },
        headers=ctx["admin_auth"],
    )
    assert res.status_code == 503
    assert "not configured" in res.json().get("error", {}).get("message", "").lower() or "not configured" in res.json().get("detail", "").lower()

    # Payment link was rolled back
    db = app.state.testing_session()
    assert db.query(PaymentLink).count() == 0
    db.close()


def test_payment_link_retry_idempotency_without_duplicate_payment(client, monkeypatch):
    from app.main import app
    from app.services import payment_link_service

    monkeypatch.setattr(payment_link_service, "RazorpayGateway", FakeGateway)
    monkeypatch.setattr(settings, "RAZORPAY_KEY_ID", "rzp_id")
    monkeypatch.setattr(settings, "RAZORPAY_KEY_SECRET", "rzp_secret")
    ctx = seed_data(app.state.testing_session)

    # First request
    res1 = client.post(
        "/api/v1/payments/links",
        json={"invoice_id": str(ctx["invoice_id"]), "amount": "90.00", "idempotency_key": "key-retry-idemp"},
        headers=ctx["owner_auth"],
    )
    assert res1.status_code == 201
    pay_id1 = res1.json()["data"]["payment_id"]

    # Second retry with identical idempotency key and amount reuses existing payment
    res2 = client.post(
        "/api/v1/payments/links",
        json={"invoice_id": str(ctx["invoice_id"]), "amount": "90.00", "idempotency_key": "key-retry-idemp"},
        headers=ctx["owner_auth"],
    )
    assert res2.status_code == 201
    pay_id2 = res2.json()["data"]["payment_id"]

    assert pay_id1 == pay_id2

    db = app.state.testing_session()
    # Exactly one payment record created
    assert db.query(Payment).filter_by(invoice_id=ctx["invoice_id"]).count() == 1
    db.close()


def test_payment_link_base_url_configuration(client, monkeypatch):
    """Verifies that PAYMENT_LINK_BASE_URL is respected when generating resident payment links."""
    from app.main import app
    from app.services import payment_link_service

    monkeypatch.setattr(payment_link_service, "RazorpayGateway", FakeGateway)
    monkeypatch.setattr(settings, "RAZORPAY_KEY_ID", "rzp_id")
    monkeypatch.setattr(settings, "RAZORPAY_KEY_SECRET", "rzp_secret")
    monkeypatch.setattr(settings, "PAYMENT_LINK_BASE_URL", "https://checkout.example.com/pay")
    ctx = seed_data(app.state.testing_session)

    res = client.post(
        "/api/v1/payments/links",
        json={"invoice_id": str(ctx["invoice_id"]), "amount": "99.00", "idempotency_key": "key-cfg-test-url"},
        headers=ctx["owner_auth"],
    )
    assert res.status_code == 201
    payment_url = res.json()["data"]["payment_url"]
    assert payment_url.startswith("https://checkout.example.com/pay/")

