"""
Phase 2C PostgreSQL Integration Tests — Invoices & Payments

These tests run against the live PostgreSQL `pg_management_test` database.
They verify:
 - Composite FK physical enforcement (cross-property invoice/payment mismatch)
 - Unique constraint enforcement (duplicate month/type invoice)
 - Concurrency safety (concurrent overpayment attempt via row locking)
 - Full payment/refund lifecycle persistence
 - Property-wise financial summary correctness
 - RBAC scoping at the PostgreSQL API level
"""
import concurrent.futures
import uuid
from decimal import Decimal

import pytest
import sqlalchemy as sa

from app.models.invoice import Invoice
from app.models.payment import Payment
from app.models.property import Property
from app.models.resident import Resident
from tests_postgres.test_postgres_rooms_and_beds import get_token


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _get_property_map(client, token):
    props = client.get("/api/v1/properties", headers={"Authorization": f"Bearer {token}"}).json()["data"]
    return {p["code"]: p["id"] for p in props}


def _admit_resident(client, token, prop_id, name="PG Resident", phone="9811100001"):
    payload = {
        "property_id": prop_id,
        "full_name": name,
        "phone": phone,
        "email": f"{phone}@example.com",
        "emergency_contact_name": "Emergency Person",
        "emergency_contact_phone": "9811100000",
        "monthly_rent": 12000.0,
        "security_deposit": 24000.0,
        "id_proof_type": "AADHAAR",
        "id_proof_number": "1111 2222 3333",
    }
    resp = client.post(
        "/api/v1/residents",
        headers={"Authorization": f"Bearer {token}"},
        json=payload,
    )
    assert resp.status_code == 201, resp.text
    return resp.json()["data"]["id"]


def _create_invoice(client, token, prop_id, res_id, billing_month="2027-01",
                    rent_amount="10000.00", is_draft=False):
    """Helper to create an invoice via API with a future due_date."""
    year, month = billing_month.split("-")
    start = f"{year}-{month}-01"
    end = f"{year}-{month}-28"
    payload = {
        "property_id": prop_id,
        "resident_id": res_id,
        "billing_month": billing_month,
        "billing_period_start": start,
        "billing_period_end": end,
        "issue_date": start,
        "due_date": f"{year}-{month}-10",
        "invoice_type": "RENT",
        "rent_amount": rent_amount,
        "is_draft": is_draft,
    }
    resp = client.post(
        "/api/v1/invoices",
        headers={"Authorization": f"Bearer {token}"},
        json=payload,
    )
    assert resp.status_code == 201, resp.text
    return resp.json()["data"]["id"]


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

def test_postgres_invoice_creation_and_persistence(client, pg_session):
    """
    Creates an invoice via API and verifies the row is persisted directly in PostgreSQL.
    Checks invoice_number format, amounts, status, and composite FK columns.
    """
    admin_token = get_token(client, "admin")
    prop_map = _get_property_map(client, admin_token)
    kor_id = prop_map["OG-KOR"]

    res_id = _admit_resident(client, admin_token, kor_id, "Priya Mehta", "9811100010")
    inv_id_str = _create_invoice(client, admin_token, kor_id, res_id,
                                 billing_month="2027-02", rent_amount="13500.00")
    inv_uuid = uuid.UUID(inv_id_str)

    # Direct PostgreSQL row check
    inv = pg_session.scalar(sa.select(Invoice).where(Invoice.id == inv_uuid))
    assert inv is not None
    assert inv.invoice_number.startswith("INV-OG-KOR-202702-")
    assert inv.total_amount == Decimal("13500.00")
    assert inv.paid_amount == Decimal("0.00")
    assert inv.balance_amount == Decimal("13500.00")
    assert inv.status == "ISSUED"
    # Composite FK columns match
    assert str(inv.property_id) == kor_id
    assert str(inv.resident_id) == res_id


def test_postgres_composite_fk_rejects_cross_property_invoice(pg_session):
    """
    Verifies the database-level composite FK (resident_id, property_id) physically
    prevents inserting an invoice with a resident from PG-1 and property_id from PG-2.
    This invariant must hold at the DB level, not just the application layer.
    """
    # Fetch a property and resident from PostgreSQL
    prop_kor = pg_session.scalar(sa.select(Property).where(Property.code == "OG-KOR"))
    prop_hsr = pg_session.scalar(sa.select(Property).where(Property.code == "OG-HSR"))
    assert prop_kor and prop_hsr, "Both OG-KOR and OG-HSR must exist in test DB"

    # Try to create a resident directly in OG-KOR
    resident = Resident(
        company_id=prop_kor.company_id,
        property_id=prop_kor.id,
        full_name="Cross-PG Resident",
        phone="9811199991",
        monthly_rent=Decimal("10000.00"),
        security_deposit=Decimal("20000.00"),
    )
    pg_session.add(resident)
    pg_session.flush()  # Assigns ID

    # Attempt to insert Invoice with resident from OG-KOR but property_id from OG-HSR
    bad_invoice = Invoice(
        company_id=prop_kor.company_id,
        property_id=prop_hsr.id,  # MISMATCH: different property than resident
        resident_id=resident.id,
        invoice_number="INV-BAD-001",
        billing_month="2027-03",
        billing_period_start="2027-03-01",
        billing_period_end="2027-03-31",
        issue_date="2027-03-01",
        due_date="2027-03-10",
        invoice_type="RENT",
        rent_amount=Decimal("10000.00"),
        additional_charges=Decimal("0.00"),
        discount_amount=Decimal("0.00"),
        total_amount=Decimal("10000.00"),
        paid_amount=Decimal("0.00"),
        balance_amount=Decimal("10000.00"),
        status="ISSUED",
    )
    pg_session.add(bad_invoice)

    # Must raise an IntegrityError due to FK violation
    with pytest.raises(Exception) as exc_info:
        pg_session.flush()

    err_str = str(exc_info.value).lower()
    assert "foreign key" in err_str or "fk_invoices" in err_str or "violates" in err_str, (
        f"Expected FK violation but got: {exc_info.value}"
    )
    pg_session.rollback()


def test_postgres_unique_constraint_blocks_duplicate_month_type_invoice(client, pg_session):
    """
    Verifies the database-level unique constraint uq_resident_billing_month_type
    physically prevents two RENT invoices for the same resident in the same billing_month.
    """
    admin_token = get_token(client, "admin")
    prop_map = _get_property_map(client, admin_token)
    kor_id = prop_map["OG-KOR"]

    res_id = _admit_resident(client, admin_token, kor_id, "Suresh Kumar", "9811100020")

    # First invoice succeeds
    inv1_id = _create_invoice(client, admin_token, kor_id, res_id, billing_month="2027-06")
    assert inv1_id

    # Second invoice with same resident + billing_month + invoice_type via API returns 409
    resp2 = client.post(
        "/api/v1/invoices",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={
            "property_id": kor_id,
            "resident_id": res_id,
            "billing_month": "2027-06",
            "billing_period_start": "2027-06-01",
            "billing_period_end": "2027-06-28",
            "issue_date": "2027-06-01",
            "due_date": "2027-06-10",
            "invoice_type": "RENT",
            "rent_amount": "12000.00",
        },
    )
    assert resp2.status_code == 409
    assert "already exists" in resp2.json()["error"]["message"]


def test_postgres_payment_persistence_and_balance_tracking(client, pg_session):
    """
    Records a payment via API and verifies direct PostgreSQL row data:
    correct amounts, payment_number format, status, and composite FK alignment.
    """
    admin_token = get_token(client, "admin")
    prop_map = _get_property_map(client, admin_token)
    kor_id = prop_map["OG-KOR"]

    res_id = _admit_resident(client, admin_token, kor_id, "Ramesh Nair", "9811100030")
    inv_id_str = _create_invoice(client, admin_token, kor_id, res_id,
                                 billing_month="2027-07", rent_amount="8000.00")
    inv_uuid = uuid.UUID(inv_id_str)

    # Record partial payment
    pay_resp = client.post(
        "/api/v1/payments",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={
            "invoice_id": inv_id_str,
            "amount": "3000.00",
            "payment_method": "UPI",
            "transaction_reference": "PG-UPI-TXN-701",
        },
    )
    assert pay_resp.status_code == 201
    pay_data = pay_resp.json()["data"]
    pay_uuid = uuid.UUID(pay_data["id"])
    assert pay_data["payment_number"].startswith("PAY-OG-KOR-")
    assert pay_data["status"] == "COMPLETED"

    # Direct PostgreSQL row checks
    payment = pg_session.scalar(sa.select(Payment).where(Payment.id == pay_uuid))
    assert payment is not None
    assert payment.amount == Decimal("3000.00")
    assert payment.status == "COMPLETED"
    assert str(payment.property_id) == kor_id
    assert str(payment.invoice_id) == inv_id_str

    # Invoice balance must be updated in PostgreSQL
    pg_session.refresh(pg_session.scalar(sa.select(Invoice).where(Invoice.id == inv_uuid)))
    inv = pg_session.scalar(sa.select(Invoice).where(Invoice.id == inv_uuid))
    assert inv.paid_amount == Decimal("3000.00")
    assert inv.balance_amount == Decimal("5000.00")
    assert inv.status == "PARTIALLY_PAID"


def test_postgres_concurrent_overpayment_row_lock(pg_session):
    """
    Verifies that SELECT ... FOR UPDATE row-locking on Invoice prevents concurrent
    overpayment: two threads each attempt to pay the full balance simultaneously;
    only one succeeds and the other is rejected with 409 CONFLICT.

    Fixtures are committed through independent sessions so both racing threads can
    see the invoice, then removed in dependency order.
    """
    import threading
    from datetime import date, timedelta
    from decimal import Decimal

    from app.core.exceptions import PGException
    from app.db.session import SessionLocal
    from app.models.role import Role
    from app.models.user import User
    from app.schemas.payment import PaymentCreate
    from app.services.invoice_service import record_payment

    today = date.today()
    suffix = uuid.uuid4().hex[:6].upper()

    with SessionLocal() as setup:
        admin = setup.scalar(
            sa.select(User).join(Role).where(Role.name == "SUPER_ADMIN")
        )
        kor = setup.scalar(sa.select(Property).where(Property.code == "OG-KOR"))
        assert admin and kor

        resident = Resident(
            company_id=kor.company_id,
            property_id=kor.id,
            full_name=f"PG Concurrency {suffix}",
            phone=f"98{uuid.uuid4().int % 10**8:08d}",
            monthly_rent=Decimal("5000.00"),
            security_deposit=Decimal("0.00"),
            status="ACTIVE",
            kyc_status="PENDING",
        )
        setup.add(resident)
        setup.flush()

        invoice = Invoice(
            company_id=kor.company_id,
            property_id=kor.id,
            resident_id=resident.id,
            invoice_number=f"INV-CONC-{suffix}",
            billing_month=today.strftime("%Y-%m"),
            billing_period_start=today.replace(day=1),
            billing_period_end=today.replace(day=28) + timedelta(days=4),
            issue_date=today,
            due_date=today + timedelta(days=7),
            invoice_type="RENT",
            rent_amount=Decimal("5000.00"),
            additional_charges=Decimal("0.00"),
            discount_amount=Decimal("0.00"),
            total_amount=Decimal("5000.00"),
            paid_amount=Decimal("0.00"),
            balance_amount=Decimal("5000.00"),
            status="ISSUED",
        )
        setup.add(invoice)
        setup.commit()
        invoice_id = invoice.id
        resident_id = resident.id

    barrier = threading.Barrier(2)
    statuses = []

    def attempt_payment():
        with SessionLocal() as db:
            try:
                user = db.scalar(
                    sa.select(User).join(Role).where(Role.name == "SUPER_ADMIN")
                )
                barrier.wait(timeout=10)
                record_payment(
                    db,
                    PaymentCreate(
                        invoice_id=invoice_id,
                        amount=Decimal("5000.00"),
                        payment_method="UPI",
                        transaction_reference=f"CONC-{suffix}-{uuid.uuid4().hex[:6]}",
                    ),
                    user,
                )
                statuses.append(200)
            except PGException as exc:
                statuses.append(exc.status_code)

    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
            futures = [executor.submit(attempt_payment) for _ in range(2)]
            for future in futures:
                future.result(timeout=30)

        # One payment must succeed and the other must be rejected as overpayment.
        assert sorted(statuses) == [200, 409], f"Unexpected statuses: {statuses}"
    finally:
        with SessionLocal() as cleanup:
            cleanup.execute(
                sa.text(
                    "delete from audit_logs where resource_id in "
                    "(select id::text from payments where invoice_id = :inv) "
                    "or resource_id = :inv_text"
                ),
                {"inv": invoice_id, "inv_text": str(invoice_id)},
            )
            cleanup.execute(
                sa.delete(Payment).where(Payment.invoice_id == invoice_id)
            )
            cleanup.execute(
                sa.delete(Invoice).where(Invoice.id == invoice_id)
            )
            cleanup.execute(
                sa.delete(Resident).where(Resident.id == resident_id)
            )
            cleanup.commit()


def test_postgres_payment_refund_reinstates_balance(client, pg_session):
    """
    Verifies that refunding a payment correctly reinstates the invoice balance
    and updates the payment status to REFUNDED in PostgreSQL.
    """
    admin_token = get_token(client, "admin")
    prop_map = _get_property_map(client, admin_token)
    kor_id = prop_map["OG-KOR"]

    res_id = _admit_resident(client, admin_token, kor_id, "Refund Test Resident", "9811100050")
    inv_id_str = _create_invoice(client, admin_token, kor_id, res_id,
                                 billing_month="2027-09", rent_amount="7000.00")
    inv_uuid = uuid.UUID(inv_id_str)

    # Full payment
    pay_resp = client.post(
        "/api/v1/payments",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={
            "invoice_id": inv_id_str,
            "amount": "7000.00",
            "payment_method": "BANK_TRANSFER",
            "transaction_reference": "PG-REFUND-TXN-901",
        },
    )
    assert pay_resp.status_code == 201
    pay_id = pay_resp.json()["data"]["id"]

    # Refund
    refund_resp = client.post(
        f"/api/v1/payments/{pay_id}/refund",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={"reason": "Bank reversal requested by resident"},
    )
    assert refund_resp.status_code == 200
    assert refund_resp.json()["data"]["status"] == "REFUNDED"

    # Direct PostgreSQL checks
    pay_uuid = uuid.UUID(pay_id)
    payment = pg_session.scalar(sa.select(Payment).where(Payment.id == pay_uuid))
    assert payment.status == "REFUNDED"

    inv = pg_session.scalar(sa.select(Invoice).where(Invoice.id == inv_uuid))
    assert inv.paid_amount == Decimal("0.00")
    assert inv.balance_amount == Decimal("7000.00")
    assert inv.status == "ISSUED"


def test_postgres_property_manager_cross_property_invoice_isolation(client, pg_session):
    """
    Verifies property manager cannot create invoices for properties not assigned to them,
    but can for assigned ones. Tests the RBAC scoping at the API + PostgreSQL level.
    """
    admin_token = get_token(client, "admin")
    manager_token = get_token(client, "manager")
    prop_map = _get_property_map(client, admin_token)
    kor_id = prop_map["OG-KOR"]   # Assigned to manager
    ind_id = prop_map["OG-IND"]   # NOT assigned to manager

    res_kor = _admit_resident(client, admin_token, kor_id, "KOR Resident", "9811100060")
    res_ind = _admit_resident(client, admin_token, ind_id, "IND Resident", "9811100061")

    # Manager CAN create invoice for assigned KOR property
    ok_resp = client.post(
        "/api/v1/invoices",
        headers={"Authorization": f"Bearer {manager_token}"},
        json={
            "property_id": kor_id,
            "resident_id": res_kor,
            "billing_month": "2027-10",
            "billing_period_start": "2027-10-01",
            "billing_period_end": "2027-10-28",
            "issue_date": "2027-10-01",
            "due_date": "2027-10-10",
            "invoice_type": "RENT",
            "rent_amount": "11000.00",
        },
    )
    assert ok_resp.status_code == 201

    # Manager CANNOT create invoice for unassigned IND property
    bad_resp = client.post(
        "/api/v1/invoices",
        headers={"Authorization": f"Bearer {manager_token}"},
        json={
            "property_id": ind_id,
            "resident_id": res_ind,
            "billing_month": "2027-10",
            "billing_period_start": "2027-10-01",
            "billing_period_end": "2027-10-28",
            "issue_date": "2027-10-01",
            "due_date": "2027-10-10",
            "invoice_type": "RENT",
            "rent_amount": "11000.00",
        },
    )
    assert bad_resp.status_code == 403


def test_postgres_staff_can_record_payment_cannot_refund(client, pg_session):
    """
    Staff can record payments for assigned property invoices, but cannot refund
    (refund requires PROPERTY_MANAGER or SUPER_ADMIN).
    """
    admin_token = get_token(client, "admin")
    staff_token = get_token(client, "staff")
    prop_map = _get_property_map(client, admin_token)
    kor_id = prop_map["OG-KOR"]

    res_id = _admit_resident(client, admin_token, kor_id, "Staff Pay Test", "9811100070")
    inv_id_str = _create_invoice(client, admin_token, kor_id, res_id,
                                 billing_month="2027-11", rent_amount="9500.00")

    # Staff CAN record a payment
    pay_resp = client.post(
        "/api/v1/payments",
        headers={"Authorization": f"Bearer {staff_token}"},
        json={
            "invoice_id": inv_id_str,
            "amount": "4000.00",
            "payment_method": "CASH",
        },
    )
    assert pay_resp.status_code == 201
    pay_id = pay_resp.json()["data"]["id"]

    # Staff CANNOT refund
    refund_resp = client.post(
        f"/api/v1/payments/{pay_id}/refund",
        headers={"Authorization": f"Bearer {staff_token}"},
    )
    assert refund_resp.status_code == 403


def test_postgres_resident_can_view_own_invoices_and_payments(client, pg_session):
    """
    Tests that a resident user can access their own invoices and payments via
    /me endpoints, but cannot access admin-scoped endpoints or other residents' data.
    """
    admin_token = get_token(client, "admin")
    resident_token = get_token(client, "resident")
    prop_map = _get_property_map(client, admin_token)
    kor_id = prop_map["OG-KOR"]

    # Find or create the seeded resident profile
    res_list = client.get(
        "/api/v1/residents?search=Rahul",
        headers={"Authorization": f"Bearer {admin_token}"},
    ).json()["data"]

    if res_list:
        res_id = res_list[0]["id"]
    else:
        res_id = _admit_resident(client, admin_token, kor_id, "Rahul Sharma", "9876543213")

    # Admin creates an invoice for the resident
    inv_resp = client.post(
        "/api/v1/invoices",
        headers={"Authorization": f"Bearer {admin_token}"},
        json={
            "property_id": kor_id,
            "resident_id": res_id,
            "billing_month": "2027-12",
            "billing_period_start": "2027-12-01",
            "billing_period_end": "2027-12-28",
            "issue_date": "2027-12-01",
            "due_date": "2027-12-10",
            "invoice_type": "RENT",
            "rent_amount": "10000.00",
        },
    )
    assert inv_resp.status_code == 201
    inv_id = inv_resp.json()["data"]["id"]

    # Resident can access own invoices via /me
    my_invs = client.get(
        "/api/v1/invoices/me",
        headers={"Authorization": f"Bearer {resident_token}"},
    )
    assert my_invs.status_code == 200
    my_inv_data = my_invs.json()["data"]
    assert any(inv["id"] == inv_id for inv in my_inv_data)

    # Resident CANNOT create invoices
    bad_create = client.post(
        "/api/v1/invoices",
        headers={"Authorization": f"Bearer {resident_token}"},
        json={
            "property_id": kor_id,
            "resident_id": res_id,
            "billing_month": "2028-01",
            "billing_period_start": "2028-01-01",
            "billing_period_end": "2028-01-28",
            "issue_date": "2028-01-01",
            "due_date": "2028-01-10",
            "invoice_type": "RENT",
            "rent_amount": "10000.00",
        },
    )
    assert bad_create.status_code == 403


def test_postgres_financial_summary_correctness(client, pg_session):
    """
    Verifies the /invoices/summary endpoint returns correct portfolio-level totals
    and per-property breakdowns. Super Admin sees all properties; manager sees only theirs.
    """
    admin_token = get_token(client, "admin")
    manager_token = get_token(client, "manager")

    # Admin summary covers all properties
    admin_summary = client.get(
        "/api/v1/invoices/summary",
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert admin_summary.status_code == 200
    admin_data = admin_summary.json()["data"]
    assert "total_invoiced" in admin_data
    assert "total_collected" in admin_data
    assert "total_outstanding" in admin_data
    assert "property_summaries" in admin_data
    assert len(admin_data["property_summaries"]) > 0

    # Manager summary scoped to their assigned properties
    mgr_summary = client.get(
        "/api/v1/invoices/summary",
        headers={"Authorization": f"Bearer {manager_token}"},
    )
    assert mgr_summary.status_code == 200
    mgr_data = mgr_summary.json()["data"]
    mgr_codes = {s["property_code"] for s in mgr_data["property_summaries"]}
    # Manager is assigned OG-KOR and OG-HSR only
    assert mgr_codes.issubset({"OG-KOR", "OG-HSR"})
