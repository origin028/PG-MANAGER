import uuid
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal

import pytest

from app.core.security import create_access_token, get_password_hash
from app.models.invoice import Invoice
from app.models.payment import Payment
from app.models.property import Company, Property
from app.models.resident import Resident
from app.models.role import Role
from app.models.room import Room
from app.models.user import User, UserPropertyAccess
from app.services.payment_reservation_service import PaymentReservationService


class FakeGateway:
    def __init__(self, *_):
        pass

    def create_order(self, amount, currency, receipt, notes):
        return {"order_id": "order_test", "amount": amount, "currency": currency, "status": "created"}


def seed(session_factory):
    db = session_factory()
    company = Company(name="C", code="C")
    admin_role = Role(name="SUPER_ADMIN", display_name="Admin")
    resident_role = Role(name="RESIDENT", display_name="Resident")
    staff_role = Role(name="STAFF", display_name="Staff")
    db.add_all((company, admin_role, resident_role, staff_role))
    db.flush()

    def user(role, n):
        u = User(
            company_id=company.id,
            role_id=role.id,
            phone=f"90000000{n:02d}",
            full_name=f"User {n}",
            password_hash=get_password_hash("x"),
        )
        db.add(u)
        db.flush()
        return u

    admin = user(admin_role, 1)
    owner = user(resident_role, 2)
    other = user(resident_role, 3)
    staff = user(staff_role, 4)

    p1 = Property(company_id=company.id, name="P1", code="P1", address_line1="x", pincode="1")
    p2 = Property(company_id=company.id, name="P2", code="P2", address_line1="y", pincode="2")
    db.add_all((p1, p2))
    db.flush()

    # Staff assigned only to P2
    upa = UserPropertyAccess(user_id=staff.id, property_id=p2.id)
    db.add(upa)
    db.flush()

    room = Room(property_id=p1.id, room_number="1")
    db.add(room)
    db.flush()

    r1 = Resident(user_id=owner.id, property_id=p1.id, room_id=room.id, check_in_date=date.today())
    r2 = Resident(user_id=other.id, property_id=p1.id, room_id=room.id, check_in_date=date.today())
    db.add_all((r1, r2))
    db.flush()

    inv = Invoice(
        property_id=p1.id,
        resident_id=r1.id,
        invoice_number="I1",
        billing_month="2026-10",
        amount=Decimal("100.00"),
        paid_amount=Decimal("25.00"),
        due_date=date.today(),
    )
    db.add(inv)
    db.commit()

    token = lambda u, role: {
        "Authorization": "Bearer "
        + create_access_token(str(u.id), {"role": role.name, "company_id": str(company.id)})
    }
    result = {
        "inv": inv.id,
        "admin": token(admin, admin_role),
        "owner": token(owner, resident_role),
        "other": token(other, resident_role),
        "staff_p2": token(staff, staff_role),
        "p1_id": p1.id,
        "p2_id": p2.id,
        "owner_resident_id": r1.id,
    }
    db.close()
    return result


def test_payment_request_success_and_authorization(client, monkeypatch):
    from app.main import app
    from app.api.v1.endpoints import payments
    from app.core.config import settings

    monkeypatch.setattr(payments, "RazorpayGateway", FakeGateway)
    monkeypatch.setattr(settings, "RAZORPAY_KEY_ID", "id")
    monkeypatch.setattr(settings, "RAZORPAY_KEY_SECRET", "secret")
    ctx = seed(app.state.testing_session)
    inv = ctx["inv"]

    # Unauthenticated rejected
    assert client.post(
        "/api/v1/payments/requests",
        json={"invoice_id": str(inv), "amount": "75.00", "idempotency_key": "req-key-auth-001"},
    ).status_code == 401

    # Unauthorized resident rejected
    assert client.post(
        "/api/v1/payments/requests",
        json={"invoice_id": str(inv), "amount": "75.00", "idempotency_key": "req-key-auth-002"},
        headers=ctx["other"],
    ).status_code == 403

    # Authorized resident succeeds
    response = client.post(
        "/api/v1/payments/requests",
        json={"invoice_id": str(inv), "amount": "75.00", "idempotency_key": "req-key-auth-003"},
        headers=ctx["owner"],
    )
    assert response.status_code == 201 and response.json()["data"]["gateway_order_id"] == "order_test"
    db = app.state.testing_session()
    payment = db.query(Payment).one()
    assert payment.status == "PENDING" and payment.amount == Decimal("75.00")
    db.close()


def test_payment_request_validation_and_gateway_errors(client, monkeypatch):
    from app.main import app
    from app.api.v1.endpoints import payments
    from app.core.config import settings

    ctx = seed(app.state.testing_session)
    inv, admin = ctx["inv"], ctx["admin"]

    for amount in ("0", "-1", "75.01"):
        assert client.post(
            "/api/v1/payments/requests",
            json={"invoice_id": str(inv), "amount": amount, "idempotency_key": f"req-key-val-{amount}"},
            headers=admin,
        ).status_code in (409, 422)

    assert client.post(
        "/api/v1/payments/requests",
        json={
            "invoice_id": "00000000-0000-0000-0000-000000000000",
            "amount": "1",
            "idempotency_key": "req-key-val-notfound",
        },
        headers=admin,
    ).status_code == 404

    # Missing gateway configuration returns 503
    monkeypatch.setattr(settings, "RAZORPAY_KEY_ID", "")
    monkeypatch.setattr(settings, "RAZORPAY_KEY_SECRET", "")
    assert client.post(
        "/api/v1/payments/requests",
        json={"invoice_id": str(inv), "amount": "1", "idempotency_key": "req-key-gate-unconf"},
        headers=admin,
    ).status_code == 503

    # Gateway call failure returns 502 and creates no pending payment
    class BrokenGateway:
        def __init__(self, *_):
            pass

        def create_order(self, *_):
            raise RuntimeError("down")

    monkeypatch.setattr(payments, "RazorpayGateway", BrokenGateway)
    monkeypatch.setattr(settings, "RAZORPAY_KEY_ID", "id")
    monkeypatch.setattr(settings, "RAZORPAY_KEY_SECRET", "secret")
    assert client.post(
        "/api/v1/payments/requests",
        json={"invoice_id": str(inv), "amount": "1", "idempotency_key": "req-key-gate-broken"},
        headers=admin,
    ).status_code == 502

    db = app.state.testing_session()
    assert db.query(Payment).count() == 0
    db.close()


def test_payment_request_rejects_paid_and_cancelled_invoices(client, monkeypatch):
    from app.main import app
    from app.api.v1.endpoints import payments
    from app.core.config import settings

    monkeypatch.setattr(payments, "RazorpayGateway", FakeGateway)
    monkeypatch.setattr(settings, "RAZORPAY_KEY_ID", "id")
    monkeypatch.setattr(settings, "RAZORPAY_KEY_SECRET", "secret")
    ctx = seed(app.state.testing_session)
    inv, admin = ctx["inv"], ctx["admin"]

    db = app.state.testing_session()
    invoice = db.get(Invoice, inv)
    invoice.status = "PAID"
    db.commit()
    db.close()
    assert client.post(
        "/api/v1/payments/requests",
        json={"invoice_id": str(inv), "amount": "1", "idempotency_key": "req-key-inv-paid"},
        headers=admin,
    ).status_code == 409

    db = app.state.testing_session()
    invoice = db.get(Invoice, inv)
    invoice.status = "CANCELLED"
    db.commit()
    db.close()
    assert client.post(
        "/api/v1/payments/requests",
        json={"invoice_id": str(inv), "amount": "1", "idempotency_key": "req-key-inv-canc"},
        headers=admin,
    ).status_code == 409


def test_payment_request_response_has_no_gateway_secrets(client, monkeypatch):
    from app.main import app
    from app.api.v1.endpoints import payments
    from app.core.config import settings

    monkeypatch.setattr(payments, "RazorpayGateway", FakeGateway)
    monkeypatch.setattr(settings, "RAZORPAY_KEY_ID", "public-id")
    monkeypatch.setattr(settings, "RAZORPAY_KEY_SECRET", "private-secret")
    ctx = seed(app.state.testing_session)
    inv, admin = ctx["inv"], ctx["admin"]

    response = client.post(
        "/api/v1/payments/requests",
        json={"invoice_id": str(inv), "amount": "1", "idempotency_key": "req-key-secret-chk"},
        headers=admin,
    )
    assert response.status_code == 201
    assert "private-secret" not in response.text and "RAZORPAY_KEY_SECRET" not in response.text


def test_payment_request_missing_or_invalid_idempotency_key_rejected(client):
    from app.main import app

    ctx = seed(app.state.testing_session)
    inv, admin = ctx["inv"], ctx["admin"]

    # Missing idempotency_key
    res = client.post(
        "/api/v1/payments/requests",
        json={"invoice_id": str(inv), "amount": "10.00"},
        headers=admin,
    )
    assert res.status_code == 422

    # Too short (< 8 chars)
    res_short = client.post(
        "/api/v1/payments/requests",
        json={"invoice_id": str(inv), "amount": "10.00", "idempotency_key": "short"},
        headers=admin,
    )
    assert res_short.status_code == 422

    # Too long (> 128 chars)
    res_long = client.post(
        "/api/v1/payments/requests",
        json={"invoice_id": str(inv), "amount": "10.00", "idempotency_key": "k" * 129},
        headers=admin,
    )
    assert res_long.status_code == 422


def test_payment_request_idempotency_reuse_same_payload(client, monkeypatch):
    from app.main import app
    from app.api.v1.endpoints import payments
    from app.core.config import settings

    call_count = {"orders": 0}

    class CountingGateway:
        def __init__(self, *_):
            pass

        def create_order(self, amount, currency, receipt, notes):
            call_count["orders"] += 1
            return {"order_id": f"order_{call_count['orders']}", "amount": amount, "currency": currency, "status": "created"}

    monkeypatch.setattr(payments, "RazorpayGateway", CountingGateway)
    monkeypatch.setattr(settings, "RAZORPAY_KEY_ID", "id")
    monkeypatch.setattr(settings, "RAZORPAY_KEY_SECRET", "secret")
    ctx = seed(app.state.testing_session)
    inv, owner = ctx["inv"], ctx["owner"]

    key = "idempotency-key-reuse-001"
    # First request
    res1 = client.post(
        "/api/v1/payments/requests",
        json={"invoice_id": str(inv), "amount": "20.00", "idempotency_key": key},
        headers=owner,
    )
    assert res1.status_code == 201
    data1 = res1.json()["data"]
    first_payment_id = data1["payment_id"]
    first_order_id = data1["gateway_order_id"]
    assert call_count["orders"] == 1

    # Second request with identical key and amount reuses existing payment and creates NO new order
    res2 = client.post(
        "/api/v1/payments/requests",
        json={"invoice_id": str(inv), "amount": "20.00", "idempotency_key": key},
        headers=owner,
    )
    assert res2.status_code == 201
    data2 = res2.json()["data"]
    assert data2["payment_id"] == first_payment_id
    assert data2["gateway_order_id"] == first_order_id
    assert call_count["orders"] == 1

    db = app.state.testing_session()
    assert db.query(Payment).count() == 1
    db.close()


def test_payment_request_same_key_different_amount_rejected(client, monkeypatch):
    from app.main import app
    from app.api.v1.endpoints import payments
    from app.core.config import settings

    monkeypatch.setattr(payments, "RazorpayGateway", FakeGateway)
    monkeypatch.setattr(settings, "RAZORPAY_KEY_ID", "id")
    monkeypatch.setattr(settings, "RAZORPAY_KEY_SECRET", "secret")
    ctx = seed(app.state.testing_session)
    inv, owner = ctx["inv"], ctx["owner"]

    key = "idempotency-key-diff-amt-001"
    res1 = client.post(
        "/api/v1/payments/requests",
        json={"invoice_id": str(inv), "amount": "20.00", "idempotency_key": key},
        headers=owner,
    )
    assert res1.status_code == 201

    # Same key with different amount on same invoice should return 409
    res2 = client.post(
        "/api/v1/payments/requests",
        json={"invoice_id": str(inv), "amount": "30.00", "idempotency_key": key},
        headers=owner,
    )
    assert res2.status_code == 409


def test_payment_request_same_key_different_invoice_rejected(client, monkeypatch):
    from app.main import app
    from app.api.v1.endpoints import payments
    from app.core.config import settings

    monkeypatch.setattr(payments, "RazorpayGateway", FakeGateway)
    monkeypatch.setattr(settings, "RAZORPAY_KEY_ID", "id")
    monkeypatch.setattr(settings, "RAZORPAY_KEY_SECRET", "secret")
    ctx = seed(app.state.testing_session)
    inv1, owner, admin = ctx["inv"], ctx["owner"], ctx["admin"]

    # Create a second invoice for the same resident
    db = app.state.testing_session()
    inv2 = Invoice(
        property_id=ctx["p1_id"],
        resident_id=ctx["owner_resident_id"],
        invoice_number="I2",
        billing_month="2026-11",
        amount=Decimal("100.00"),
        paid_amount=Decimal("0.00"),
        due_date=date.today(),
    )
    db.add(inv2)
    db.commit()
    inv2_id = inv2.id
    db.close()

    key = "idempotency-key-diff-inv-001"
    res1 = client.post(
        "/api/v1/payments/requests",
        json={"invoice_id": str(inv1), "amount": "20.00", "idempotency_key": key},
        headers=owner,
    )
    assert res1.status_code == 201

    # Request with same key on second invoice should safely succeed (idempotency key scoped per invoice in schema)
    # or reject if system requires globally unique keys. Let's verify behavior:
    # Notice: payments table unique constraint is UniqueConstraint("invoice_id", "idempotency_key")
    # endpoint searches: sa.select(Payment).where(Payment.invoice_id == invoice.id, Payment.idempotency_key == payload.idempotency_key)
    # So different invoice with same key creates its own payment for inv2 safely without collision or leakage.
    res2 = client.post(
        "/api/v1/payments/requests",
        json={"invoice_id": str(inv2_id), "amount": "20.00", "idempotency_key": key},
        headers=owner,
    )
    assert res2.status_code == 201
    assert res2.json()["data"]["payment_id"] != res1.json()["data"]["payment_id"]


def test_active_pending_reservations_reduce_available_balance(client, monkeypatch):
    from app.main import app
    from app.api.v1.endpoints import payments
    from app.core.config import settings

    monkeypatch.setattr(payments, "RazorpayGateway", FakeGateway)
    monkeypatch.setattr(settings, "RAZORPAY_KEY_ID", "id")
    monkeypatch.setattr(settings, "RAZORPAY_KEY_SECRET", "secret")
    ctx = seed(app.state.testing_session)
    inv, owner = ctx["inv"], ctx["owner"]

    # Invoice: total 100, paid 25. Outstanding = 75.
    # Reserve 50
    res1 = client.post(
        "/api/v1/payments/requests",
        json={"invoice_id": str(inv), "amount": "50.00", "idempotency_key": "req-key-res-50"},
        headers=owner,
    )
    assert res1.status_code == 201

    # Attempting to reserve another 30 exceeds 75 (50 active reservation + 30 = 80 > 75)
    res2 = client.post(
        "/api/v1/payments/requests",
        json={"invoice_id": str(inv), "amount": "30.00", "idempotency_key": "req-key-res-30"},
        headers=owner,
    )
    assert res2.status_code == 409
    body2 = res2.json()
    error_msg = body2.get("error", {}).get("message", "") or body2.get("detail", "")
    assert "exceeds" in error_msg.lower()

    # Remaining 25 should succeed
    res3 = client.post(
        "/api/v1/payments/requests",
        json={"invoice_id": str(inv), "amount": "25.00", "idempotency_key": "req-key-res-25"},
        headers=owner,
    )
    assert res3.status_code == 201


def test_expired_reservations_no_longer_reduce_available_balance(client, monkeypatch):
    from app.main import app
    from app.api.v1.endpoints import payments
    from app.core.config import settings

    monkeypatch.setattr(payments, "RazorpayGateway", FakeGateway)
    monkeypatch.setattr(settings, "RAZORPAY_KEY_ID", "id")
    monkeypatch.setattr(settings, "RAZORPAY_KEY_SECRET", "secret")
    ctx = seed(app.state.testing_session)
    inv, owner = ctx["inv"], ctx["owner"]

    # Create pending reservation for 70
    res1 = client.post(
        "/api/v1/payments/requests",
        json={"invoice_id": str(inv), "amount": "70.00", "idempotency_key": "req-key-to-expire"},
        headers=owner,
    )
    assert res1.status_code == 201

    # Manually expire reservation timestamp in database
    db = app.state.testing_session()
    payment = db.query(Payment).filter_by(idempotency_key="req-key-to-expire").one()
    payment.reservation_expires_at = datetime.now(timezone.utc) - timedelta(minutes=5)
    db.commit()
    db.close()

    # Since the reservation is in the past, Payment.reservation_expires_at > now excludes it.
    # New request for 75 should now succeed
    res2 = client.post(
        "/api/v1/payments/requests",
        json={"invoice_id": str(inv), "amount": "75.00", "idempotency_key": "req-key-after-expire"},
        headers=owner,
    )
    assert res2.status_code == 201


def test_partial_payments_calculate_remaining_balance_correctly(client, monkeypatch):
    from app.main import app
    from app.api.v1.endpoints import payments
    from app.core.config import settings

    monkeypatch.setattr(payments, "RazorpayGateway", FakeGateway)
    monkeypatch.setattr(settings, "RAZORPAY_KEY_ID", "id")
    monkeypatch.setattr(settings, "RAZORPAY_KEY_SECRET", "secret")
    ctx = seed(app.state.testing_session)
    inv, owner = ctx["inv"], ctx["owner"]

    # Initial: 100 total, 25 paid => 75 remaining
    # Update invoice paid_amount to 60 => 40 remaining
    db = app.state.testing_session()
    invoice = db.get(Invoice, inv)
    invoice.paid_amount = Decimal("60.00")
    db.commit()
    db.close()

    # Requesting 40.01 exceeds
    res_fail = client.post(
        "/api/v1/payments/requests",
        json={"invoice_id": str(inv), "amount": "40.01", "idempotency_key": "req-partial-fail"},
        headers=owner,
    )
    assert res_fail.status_code == 409

    # Requesting exact remaining 40.00 succeeds
    res_ok = client.post(
        "/api/v1/payments/requests",
        json={"invoice_id": str(inv), "amount": "40.00", "idempotency_key": "req-partial-ok"},
        headers=owner,
    )
    assert res_ok.status_code == 201


def test_different_keys_cannot_reserve_more_than_outstanding(client, monkeypatch):
    from app.main import app
    from app.api.v1.endpoints import payments
    from app.core.config import settings

    monkeypatch.setattr(payments, "RazorpayGateway", FakeGateway)
    monkeypatch.setattr(settings, "RAZORPAY_KEY_ID", "id")
    monkeypatch.setattr(settings, "RAZORPAY_KEY_SECRET", "secret")
    ctx = seed(app.state.testing_session)
    inv, owner = ctx["inv"], ctx["owner"]

    # Total remaining: 75
    # First client reserves 40
    res1 = client.post(
        "/api/v1/payments/requests",
        json={"invoice_id": str(inv), "amount": "40.00", "idempotency_key": "req-key-res-p1"},
        headers=owner,
    )
    assert res1.status_code == 201

    # Second client reserves 35 (40 + 35 = 75)
    res2 = client.post(
        "/api/v1/payments/requests",
        json={"invoice_id": str(inv), "amount": "35.00", "idempotency_key": "req-key-res-p2"},
        headers=owner,
    )
    assert res2.status_code == 201

    # Third client tries even 0.01 with another key => rejected
    res3 = client.post(
        "/api/v1/payments/requests",
        json={"invoice_id": str(inv), "amount": "0.01", "idempotency_key": "req-key-res-p3"},
        headers=owner,
    )
    assert res3.status_code == 409


def test_historical_payment_rows_with_null_reservation_idempotency_remain_readable(client):
    from app.main import app
    from app.models.payment import Payment

    ctx = seed(app.state.testing_session)
    inv = ctx["inv"]
    db = app.state.testing_session()

    # Insert a historical payment row with NULL idempotency_key and reservation_expires_at
    hist = Payment(
        property_id=ctx["p1_id"],
        invoice_id=inv,
        resident_id=ctx["owner_resident_id"],
        payment_number=f"PAY-HISTORICAL-{uuid.uuid4().hex[:10].upper()}",
        amount=Decimal("25.00"),
        payment_mode="CASH",
        status="SUCCESS",
        idempotency_key=None,
        reservation_expires_at=None,
    )
    db.add(hist)
    db.commit()
    hist_id = hist.id
    db.close()

    # Query through listing API
    response = client.get(f"/api/v1/payments?property_id={ctx['p1_id']}", headers=ctx["admin"])
    assert response.status_code == 200
    items = response.json()["data"]["items"]
    found = [p for p in items if p["id"] == str(hist_id)]
    assert len(found) == 1
    assert found[0]["amount"] == 25.0
    assert found[0]["status"] == "SUCCESS"


def test_payment_reservation_service_expire_due(client):
    from app.main import app

    ctx = seed(app.state.testing_session)
    inv = ctx["inv"]
    db = app.state.testing_session()
    now = datetime.now(timezone.utc)

    # 1. Overdue pending payment
    p_overdue = Payment(
        property_id=ctx["p1_id"],
        invoice_id=inv,
        resident_id=ctx["owner_resident_id"],
        payment_number=f"PAY-OVERDUE-{uuid.uuid4().hex[:10].upper()}",
        amount=Decimal("10.00"),
        payment_mode="UPI",
        status="PENDING",
        idempotency_key="key-overdue-1",
        reservation_expires_at=now - timedelta(minutes=5),
    )
    # 2. Future pending payment (not due yet)
    p_future = Payment(
        property_id=ctx["p1_id"],
        invoice_id=inv,
        resident_id=ctx["owner_resident_id"],
        payment_number=f"PAY-FUTURE-{uuid.uuid4().hex[:10].upper()}",
        amount=Decimal("15.00"),
        payment_mode="UPI",
        status="PENDING",
        idempotency_key="key-future-1",
        reservation_expires_at=now + timedelta(minutes=10),
    )
    # 3. Successful payment that had past reservation_expires_at
    p_success = Payment(
        property_id=ctx["p1_id"],
        invoice_id=inv,
        resident_id=ctx["owner_resident_id"],
        payment_number=f"PAY-SUCCESS-{uuid.uuid4().hex[:10].upper()}",
        amount=Decimal("20.00"),
        payment_mode="UPI",
        status="SUCCESS",
        idempotency_key="key-success-1",
        reservation_expires_at=now - timedelta(minutes=5),
    )
    # 4. Pending payment with no reservation expiry (NULL)
    p_null_expiry = Payment(
        property_id=ctx["p1_id"],
        invoice_id=inv,
        resident_id=ctx["owner_resident_id"],
        payment_number=f"PAY-NULLEXP-{uuid.uuid4().hex[:10].upper()}",
        amount=Decimal("5.00"),
        payment_mode="UPI",
        status="PENDING",
        idempotency_key="key-null-1",
        reservation_expires_at=None,
    )
    db.add_all([p_overdue, p_future, p_success, p_null_expiry])
    db.commit()

    service = PaymentReservationService(db)

    # First run expires only overdue pending
    expired_count = service.expire_due(now=now)
    assert expired_count == 1

    db.refresh(p_overdue)
    db.refresh(p_future)
    db.refresh(p_success)
    db.refresh(p_null_expiry)

    assert p_overdue.status == "EXPIRED"
    assert p_future.status == "PENDING"
    assert p_success.status == "SUCCESS"
    assert p_null_expiry.status == "PENDING"

    # Repeated run is safe (idempotent), expires 0 additional records
    repeat_count = service.expire_due(now=now)
    assert repeat_count == 0
    db.close()


def test_property_manager_or_staff_cannot_pay_another_property_invoice(client, monkeypatch):
    from app.main import app
    from app.api.v1.endpoints import payments
    from app.core.config import settings

    monkeypatch.setattr(payments, "RazorpayGateway", FakeGateway)
    monkeypatch.setattr(settings, "RAZORPAY_KEY_ID", "id")
    monkeypatch.setattr(settings, "RAZORPAY_KEY_SECRET", "secret")
    ctx = seed(app.state.testing_session)
    # Staff is assigned only to property P2, but invoice is in property P1
    inv, staff_p2 = ctx["inv"], ctx["staff_p2"]

    response = client.post(
        "/api/v1/payments/requests",
        json={"invoice_id": str(inv), "amount": "10.00", "idempotency_key": "req-key-staff-diff-prop"},
        headers=staff_p2,
    )
    assert response.status_code == 403
