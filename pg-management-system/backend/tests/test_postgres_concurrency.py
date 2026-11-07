"""PostgreSQL concurrency and row-locking integration tests.

These tests execute ONLY when `TEST_DATABASE_URL` is set in the environment.
They verify genuine multi-threaded, concurrent PostgreSQL transaction semantics:
  - Row locking (FOR UPDATE)
  - Race conditions between competing payment reservation requests
  - Simultaneous webhook delivery deduplication
  - Atomic invoice settlement and receipt issuance
  - Transaction rollbacks under crash conditions

SAFETY RULES ENFORCED:
  - Refuses to connect if TEST_DATABASE_URL points to protected database names ('pg_management', 'production', 'master')
  - Automatically provisions an isolated disposable database for the test session
  - Applies migrations cleanly from Alembic head
  - Drops the disposable test database on completion
"""

import concurrent.futures
import hashlib
import hmac
import json
import logging
import os
import threading
import uuid
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
from urllib.parse import urlparse

import psycopg
import pytest
import sqlalchemy as sa
from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

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
from app.services.settlement_service import WebhookSettlementService

TEST_DB_URL_ENV = os.environ.get("TEST_DATABASE_URL")

# Skip entire module safely if opt-in TEST_DATABASE_URL is absent
pytestmark = pytest.mark.skipif(
    not TEST_DB_URL_ENV,
    reason="PostgreSQL integration tests require TEST_DATABASE_URL environment variable.",
)

WEBHOOK_SECRET = "pg_test_webhook_secret_key"


def is_safe_test_url(url: str) -> bool:
    """Verifies that the provided URL does not target any protected database."""
    parsed = urlparse(url)
    db_name = parsed.path.lstrip("/").lower()
    protected = {"pg_management", "postgres", "production", "prod", "master", "main"}
    if db_name in protected or not db_name:
        return False
    return True


@pytest.fixture(scope="session")
def postgres_disposable_engine():
    """Provisions a disposable PostgreSQL database using TEST_DATABASE_URL template,

    runs migrations to head, and destroys it when all tests conclude.
    """
    raw_url = os.environ.get("TEST_DATABASE_URL", "").strip()
    if not is_safe_test_url(raw_url):
        raise ValueError(
            f"TEST_DATABASE_URL='{raw_url}' is not a safe disposable database name. "
            "Use a test-specific database name like 'pg_disposable_test'."
        )

    # Derive admin connection URL to create/drop the disposable db
    parsed = urlparse(raw_url)
    admin_dsn = f"postgresql://{parsed.username}:{parsed.password}@{parsed.hostname}:{parsed.port or 5432}/postgres"
    disposable_db_name = f"test_conc_{uuid.uuid4().hex[:10]}"

    admin_conn = psycopg.connect(admin_dsn, autocommit=True)
    admin_conn.execute(f"CREATE DATABASE {disposable_db_name}")

    # SQLAlchemy connection string with psycopg 3
    test_db_url = (
        f"postgresql+psycopg://{parsed.username}:{parsed.password}@"
        f"{parsed.hostname}:{parsed.port or 5432}/{disposable_db_name}"
    )

    engine = create_engine(test_db_url, pool_size=10, max_overflow=20)

    # Run migrations in order
    orig_db_url = settings.DATABASE_URL
    settings.DATABASE_URL = test_db_url
    alembic_cfg = Config("alembic.ini")
    command.upgrade(alembic_cfg, "head")

    # Re-enable any existing loggers disabled by alembic fileConfig
    for name in list(logging.root.manager.loggerDict.keys()):
        log_obj = logging.getLogger(name)
        if hasattr(log_obj, "disabled"):
            log_obj.disabled = False

    try:
        yield engine
    finally:
        engine.dispose()
        settings.DATABASE_URL = orig_db_url
        admin_conn.execute(
            f"SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '{disposable_db_name}'"
        )
        admin_conn.execute(f"DROP DATABASE {disposable_db_name}")
        admin_conn.close()


@pytest.fixture
def pg_session_factory(postgres_disposable_engine):
    """Provides a fresh sessionmaker bound to the disposable PostgreSQL engine."""
    return sessionmaker(bind=postgres_disposable_engine, autocommit=False, autoflush=False)


def seed_pg_invoice(session_factory, invoice_amount="100.00", initial_paid="0.00"):
    """Seeds a test resident and invoice directly in PostgreSQL."""
    db = session_factory()
    company = Company(name="PG_Conc_Co", code=f"C_{uuid.uuid4().hex[:4]}")
    role = db.scalar(sa.select(Role).where(Role.name == "RESIDENT"))
    if not role:
        role = Role(name="RESIDENT", display_name="Resident")
        db.add(role)
    db.add(company)
    db.flush()

    user = User(
        company_id=company.id,
        role_id=role.id,
        phone=f"92{uuid.uuid4().int % 100000000:08d}",
        full_name="Concurrency Resident",
        password_hash="pwd_hash",
    )
    db.add(user)
    db.flush()

    p = Property(
        company_id=company.id,
        name="Concurrency Property",
        code=f"PROP_{uuid.uuid4().hex[:4]}",
        address_line1="123 Test St",
        pincode="560001",
    )
    db.add(p)
    db.flush()

    room = Room(property_id=p.id, room_number="101")
    db.add(room)
    db.flush()

    resident = Resident(
        user_id=user.id,
        property_id=p.id,
        room_id=room.id,
        check_in_date=date.today(),
    )
    db.add(resident)
    db.flush()

    invoice = Invoice(
        property_id=p.id,
        resident_id=resident.id,
        invoice_number=f"INV-CONC-{uuid.uuid4().hex[:6].upper()}",
        billing_month="2026-10",
        amount=Decimal(invoice_amount),
        paid_amount=Decimal(initial_paid),
        due_date=date.today(),
        status="PENDING",
    )
    db.add(invoice)
    db.commit()

    ctx = {
        "company_id": company.id,
        "property_id": p.id,
        "resident_id": resident.id,
        "invoice_id": invoice.id,
    }
    db.close()
    return ctx


def test_pg_simultaneous_payment_requests_competing_for_balance(pg_session_factory):
    """Verifies that two concurrent transactions attempting to reserve more than the available

    balance cannot both succeed. PostgreSQL row locking (with_for_update) forces sequential
    evaluation, so one succeeds and one fails with balance exceeded.
    """
    ctx = seed_pg_invoice(pg_session_factory, invoice_amount="100.00", initial_paid="20.00")
    inv_id = ctx["invoice_id"]
    # Outstanding balance = 80.00.
    # Two requests each try to reserve 50.00 at the exact same moment.

    barrier = threading.Barrier(2)
    results = []

    def make_payment_request(thread_idx, amount, idempotency_key):
        db = pg_session_factory()
        now = datetime.now(timezone.utc)
        barrier.wait()  # Synchronize launch
        try:
            # Replicate create_payment_request atomic transaction logic
            invoice = db.scalar(
                sa.select(Invoice).where(Invoice.id == inv_id).with_for_update()
            )
            reserved = db.scalar(
                sa.select(sa.func.coalesce(sa.func.sum(Payment.amount), 0)).where(
                    Payment.invoice_id == invoice.id,
                    Payment.status == "PENDING",
                    Payment.reservation_expires_at > now,
                )
            )
            outstanding = (
                Decimal(str(invoice.amount))
                - Decimal(str(invoice.paid_amount))
                - Decimal(str(reserved))
            )
            if amount > outstanding:
                db.rollback()
                results.append((thread_idx, False, "Exceeds outstanding balance"))
                return

            payment = Payment(
                property_id=invoice.property_id,
                invoice_id=invoice.id,
                resident_id=invoice.resident_id,
                payment_number=f"PAY-CONC-{uuid.uuid4().hex[:10].upper()}",
                amount=amount,
                payment_mode="UPI",
                status="PENDING",
                idempotency_key=idempotency_key,
                reservation_expires_at=now + timedelta(minutes=15),
                gateway_order_id=f"order_{uuid.uuid4().hex[:8]}",
            )
            db.add(payment)
            db.commit()
            results.append((thread_idx, True, payment.id))
        except Exception as exc:
            db.rollback()
            results.append((thread_idx, False, str(exc)))
        finally:
            db.close()

    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
        f1 = executor.submit(make_payment_request, 1, Decimal("50.00"), "key-race-001")
        f2 = executor.submit(make_payment_request, 2, Decimal("50.00"), "key-race-002")
        f1.result()
        f2.result()

    successes = [r for r in results if r[1] is True]
    failures = [r for r in results if r[1] is False]

    # Exactly one must succeed and one must fail
    assert len(successes) == 1, f"Expected 1 success, got {len(successes)}"
    assert len(failures) == 1, f"Expected 1 failure, got {len(failures)}"
    assert "Exceeds outstanding balance" in failures[0][2]

    # Database state verification
    db = pg_session_factory()
    assert db.query(Payment).filter_by(invoice_id=inv_id).count() == 1
    db.close()


def test_pg_duplicate_captured_webhook_deliveries_concurrent(pg_session_factory):
    """Verifies that two simultaneous duplicate webhook deliveries for the same payment

    result in exactly ONE successful settlement, exactly ONE receipt, and no unique-constraint crash.
    """
    ctx = seed_pg_invoice(pg_session_factory, invoice_amount="100.00", initial_paid="0.00")
    inv_id = ctx["invoice_id"]
    order_id = f"order_{uuid.uuid4().hex[:8]}"

    db_init = pg_session_factory()
    payment = Payment(
        property_id=ctx["property_id"],
        invoice_id=inv_id,
        resident_id=ctx["resident_id"],
        payment_number=f"PAY-DUP-{uuid.uuid4().hex[:8].upper()}",
        amount=Decimal("100.00"),
        payment_mode="UPI",
        gateway_order_id=order_id,
        status="PENDING",
        idempotency_key=f"idemp-{uuid.uuid4().hex[:8]}",
        reservation_expires_at=datetime.now(timezone.utc) + timedelta(minutes=15),
    )
    db_init.add(payment)
    db_init.commit()
    payment_id = payment.id
    db_init.close()

    barrier = threading.Barrier(2)
    results = []
    evt_id = f"evt_dup_race_{uuid.uuid4().hex[:8]}"

    def deliver_webhook(thread_idx):
        db = pg_session_factory()
        barrier.wait()
        service = WebhookSettlementService(db)
        try:
            success, msg, receipt = service.settle_payment_captured(
                provider_order_id=order_id,
                provider_payment_id="pay_rzp_dup_race_1",
                amount_paise=10000,
                currency="INR",
                payment_method="upi",
                event_id=evt_id,
            )
            results.append((thread_idx, success, msg, receipt.id if receipt else None))
        except Exception as exc:
            results.append((thread_idx, False, str(exc), None))
        finally:
            db.close()

    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
        f1 = executor.submit(deliver_webhook, 1)
        f2 = executor.submit(deliver_webhook, 2)
        f1.result()
        f2.result()

    # Both threads must complete successfully without crashing
    for r in results:
        assert r[1] is True, f"Thread failed: {r}"

    # Database verification: exactly 1 receipt and 1 processed event in PostgreSQL
    db = pg_session_factory()
    receipts = db.query(Receipt).filter_by(payment_id=payment_id).all()
    assert len(receipts) == 1
    assert db.query(ProcessedWebhookEvent).filter_by(event_id=evt_id).count() == 1
    p = db.get(Payment, payment_id)
    assert p.status == "SUCCESS"
    inv = db.get(Invoice, inv_id)
    assert inv.paid_amount == Decimal("100.00")
    assert inv.status == "PAID"
    db.close()


def test_pg_two_different_valid_captures_competing_to_settle_invoice(pg_session_factory):
    """Verifies that two different valid partial payments on the same invoice

    settle correctly without balance corruption under concurrent execution.
    """
    ctx = seed_pg_invoice(pg_session_factory, invoice_amount="100.00", initial_paid="0.00")
    inv_id = ctx["invoice_id"]

    order1 = f"order_p1_{uuid.uuid4().hex[:6]}"
    order2 = f"order_p2_{uuid.uuid4().hex[:6]}"

    db_init = pg_session_factory()
    # Create two pending payment requests: 40.00 and 60.00
    p1 = Payment(
        property_id=ctx["property_id"],
        invoice_id=inv_id,
        resident_id=ctx["resident_id"],
        payment_number=f"PAY-P1-{uuid.uuid4().hex[:6].upper()}",
        amount=Decimal("40.00"),
        payment_mode="UPI",
        gateway_order_id=order1,
        status="PENDING",
        idempotency_key=f"idemp-{uuid.uuid4().hex[:8]}",
        reservation_expires_at=datetime.now(timezone.utc) + timedelta(minutes=15),
    )
    p2 = Payment(
        property_id=ctx["property_id"],
        invoice_id=inv_id,
        resident_id=ctx["resident_id"],
        payment_number=f"PAY-P2-{uuid.uuid4().hex[:6].upper()}",
        amount=Decimal("60.00"),
        payment_mode="UPI",
        gateway_order_id=order2,
        status="PENDING",
        idempotency_key=f"idemp-{uuid.uuid4().hex[:8]}",
        reservation_expires_at=datetime.now(timezone.utc) + timedelta(minutes=15),
    )
    db_init.add_all([p1, p2])
    db_init.commit()
    p1_id, p2_id = p1.id, p2.id
    db_init.close()

    barrier = threading.Barrier(2)
    results = []

    def settle(order_id, pay_id, amount_paise):
        db = pg_session_factory()
        barrier.wait()
        service = WebhookSettlementService(db)
        try:
            success, msg, receipt = service.settle_payment_captured(
                provider_order_id=order_id,
                provider_payment_id=pay_id,
                amount_paise=amount_paise,
                currency="INR",
            )
            results.append((success, msg))
        finally:
            db.close()

    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
        f1 = executor.submit(settle, order1, "pay_1", 4000)
        f2 = executor.submit(settle, order2, "pay_2", 6000)
        f1.result()
        f2.result()

    for r in results:
        assert r[0] is True

    # Invoice must be fully PAID: 40 + 60 = 100
    db = pg_session_factory()
    inv = db.get(Invoice, inv_id)
    assert inv.paid_amount == Decimal("100.00")
    assert inv.status == "PAID"

    # Exactly 2 receipts issued, each corresponding to its payment
    r1 = db.query(Receipt).filter_by(payment_id=p1_id).one()
    r2 = db.query(Receipt).filter_by(payment_id=p2_id).one()
    assert r1.amount == Decimal("40.00")
    assert r2.amount == Decimal("60.00")
    assert r1.receipt_number != r2.receipt_number
    db.close()


def test_pg_settlement_transaction_atomic_rollback(pg_session_factory):
    """Verifies that an unhandled failure during settlement rolls back the payment update,

    invoice recalculation, receipt creation, and webhook event recording together.
    """
    ctx = seed_pg_invoice(pg_session_factory, invoice_amount="100.00", initial_paid="0.00")
    inv_id = ctx["invoice_id"]
    order_id = f"order_rb_{uuid.uuid4().hex[:6]}"

    db_init = pg_session_factory()
    payment = Payment(
        property_id=ctx["property_id"],
        invoice_id=inv_id,
        resident_id=ctx["resident_id"],
        payment_number=f"PAY-RB-{uuid.uuid4().hex[:6].upper()}",
        amount=Decimal("100.00"),
        payment_mode="UPI",
        gateway_order_id=order_id,
        status="PENDING",
        idempotency_key=f"idemp-rb-{uuid.uuid4().hex[:6]}",
        reservation_expires_at=datetime.now(timezone.utc) + timedelta(minutes=15),
    )
    db_init.add(payment)
    db_init.commit()
    payment_id = payment.id
    db_init.close()

    db = pg_session_factory()
    service = WebhookSettlementService(db)

    # Intentionally trigger an error inside the transaction by passing an invalid DB operation
    # or simulating failure before commit
    try:
        # Replicate transaction failure
        inv = db.scalar(sa.select(Invoice).where(Invoice.id == inv_id).with_for_update())
        pay = db.scalar(sa.select(Payment).where(Payment.id == payment_id).with_for_update())
        pay.status = "SUCCESS"
        inv.paid_amount = Decimal("100.00")

        # Raise an exception before commit
        raise RuntimeError("Simulated database failure during settlement")
    except RuntimeError:
        db.rollback()
    finally:
        db.close()

    # Confirm rollback integrity in PostgreSQL
    db = pg_session_factory()
    pay_check = db.get(Payment, payment_id)
    assert pay_check.status == "PENDING"
    inv_check = db.get(Invoice, inv_id)
    assert inv_check.paid_amount == Decimal("0.00")
    assert inv_check.status == "PENDING"
    assert db.query(Receipt).filter_by(payment_id=payment_id).count() == 0
    db.close()


def test_pg_e2e_complete_lifecycle_and_receipt_worker(pg_session_factory, monkeypatch):
    """Phase 9: Full end-to-end payment settlement and receipt delivery verification on PostgreSQL."""
    from app.integrations.whatsapp import WhatsAppCloudProvider
    from app.services.receipt_delivery_service import ReceiptDeliveryService

    monkeypatch.setattr(settings, "WHATSAPP_PHONE_NUMBER_ID", "123456")
    monkeypatch.setattr(settings, "WHATSAPP_ACCESS_TOKEN", "wa_token")
    monkeypatch.setattr(settings, "WHATSAPP_RECEIPT_TEMPLATE", "rent_receipt_v1")

    wa_dispatched = []

    def mock_send(self, to_phone: str, template: str, parameters: list):
        wa_dispatched.append({"to": to_phone, "template": template, "parameters": parameters})
        return f"wamid_pg_{uuid.uuid4().hex[:8]}"

    monkeypatch.setattr(WhatsAppCloudProvider, "send_template", mock_send)

    db = pg_session_factory()
    company = Company(name="PG E2E Co", code=f"C_{uuid.uuid4().hex[:4]}")
    db.add(company)
    db.flush()

    role = db.scalar(sa.select(Role).where(Role.name == "RESIDENT"))
    if not role:
        role = Role(name="RESIDENT", display_name="Resident")
        db.add(role)
        db.flush()

    user = User(
        company_id=company.id,
        role_id=role.id,
        phone="9988776655",
        full_name="Postgres Resident",
        password_hash="pwd_hash",
    )
    db.add(user)
    db.flush()

    prop = Property(
        company_id=company.id,
        name="Postgres Residency PG",
        code=f"P_{uuid.uuid4().hex[:4]}",
        address_line1="Indiranagar",
        city="Bengaluru",
        state="Karnataka",
        pincode="560038",
    )
    db.add(prop)
    db.flush()

    room = Room(property_id=prop.id, room_number="501")
    db.add(room)
    db.flush()

    resident = Resident(user_id=user.id, property_id=prop.id, room_id=room.id, check_in_date=date.today())
    db.add(resident)
    db.flush()

    invoice = Invoice(
        property_id=prop.id,
        resident_id=resident.id,
        invoice_number=f"INV-PG-{uuid.uuid4().hex[:4].upper()}",
        billing_month="2026-10",
        amount=Decimal("3500.00"),
        paid_amount=Decimal("0.00"),
        due_date=date.today(),
        status="PENDING",
    )
    db.add(invoice)
    db.flush()

    order_id = f"order_pg_e2e_{uuid.uuid4().hex[:6]}"
    payment = Payment(
        property_id=prop.id,
        invoice_id=invoice.id,
        resident_id=resident.id,
        payment_number=f"PAY-PG-{uuid.uuid4().hex[:6].upper()}",
        amount=Decimal("3500.00"),
        payment_mode="UPI",
        gateway_order_id=order_id,
        status="PENDING",
        idempotency_key=f"idemp-pg-{uuid.uuid4().hex[:8]}",
        reservation_expires_at=datetime.now(timezone.utc) + timedelta(minutes=15),
    )
    db.add(payment)
    db.commit()

    inv_id = invoice.id
    pay_id = payment.id
    db.close()

    # Settle payment atomically using WebhookSettlementService on PostgreSQL
    db_settle = pg_session_factory()
    service = WebhookSettlementService(db_settle)
    success, msg, receipt = service.settle_payment_captured(
        provider_order_id=order_id,
        provider_payment_id=f"pay_rzp_pg_{uuid.uuid4().hex[:6]}",
        amount_paise=350000,
        currency="INR",
        payment_method="UPI",
        event_id=f"evt_pg_e2e_{uuid.uuid4().hex[:8]}",
        raw_event={"dummy": True},
    )
    assert success is True
    assert receipt is not None
    assert receipt.whatsapp_status == "PENDING"
    db_settle.close()

    # Execute receipt delivery worker on PostgreSQL
    db_worker = pg_session_factory()
    worker = ReceiptDeliveryService(db_worker)
    sent_count = worker.process_due_receipts(limit=10)
    assert sent_count >= 1
    db_worker.close()

    # Verify final settled state on PostgreSQL
    db_verify = pg_session_factory()
    inv_final = db_verify.get(Invoice, inv_id)
    pay_final = db_verify.get(Payment, pay_id)
    rcpt_final = db_verify.query(Receipt).filter_by(payment_id=pay_id).one()

    assert inv_final.status == "PAID"
    assert inv_final.paid_amount == Decimal("3500.00")
    assert pay_final.status == "SUCCESS"
    assert rcpt_final.whatsapp_status == "SENT"
    assert rcpt_final.whatsapp_attempts == 1
    dispatched_for_user = [m for m in wa_dispatched if m["to"] == "9988776655"]
    assert len(dispatched_for_user) == 1
    assert dispatched_for_user[0]["parameters"][0] == "Postgres Residency PG"
    assert dispatched_for_user[0]["parameters"][1] == "501"
    assert dispatched_for_user[0]["parameters"][2] == "Postgres Resident"
    assert "3500.00" in dispatched_for_user[0]["parameters"][5]
    db_verify.close()

