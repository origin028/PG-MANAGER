from datetime import date

import sqlalchemy as sa
from fastapi.testclient import TestClient

from app.models.invoice import Invoice
from app.models.resident import Resident
from app.tasks.invoice_jobs import generate_monthly_invoices
from app.tasks.reminder_jobs import run_payment_reminders
from tests.test_phase3_payment_completion import setup_test_context


def test_monthly_invoices_created_once_and_idempotent(client: TestClient):
    factory = client.app.state.testing_session
    setup_test_context(factory)
    with factory() as db:
        first = generate_monthly_invoices(db, "2026-03")
        # Only res1 has a bed; res2 has none and must not be billed.
        assert first["generated_count"] == 1
        again = generate_monthly_invoices(db, "2026-03")
        assert again["generated_count"] == 0 and again["skipped"] >= 1
        inv = db.scalars(sa.select(Invoice).where(Invoice.billing_month == "2026-03")).one()
        assert float(inv.amount) == 5000.0
        assert inv.due_date == date(2026, 3, 5) and inv.status == "PENDING"


def test_resident_not_billed_before_check_in_or_after_checkout(client: TestClient):
    factory = client.app.state.testing_session
    setup_test_context(factory)
    with factory() as db:
        r = db.scalars(sa.select(Resident).where(Resident.bed_id.is_not(None))).one()
        assert generate_monthly_invoices(db, "2025-12")["generated_count"] == 0  # before 2026-01-01 check-in
        r.actual_check_out_date = date(2026, 2, 10)
        db.commit()
        assert generate_monthly_invoices(db, "2026-04")["generated_count"] == 0  # left before April


def test_reminders_mark_overdue_and_send_email(client: TestClient):
    from app.integrations.email import DevMockEmailProvider

    factory = client.app.state.testing_session
    setup_test_context(factory)
    DevMockEmailProvider.clear()
    with factory() as db:
        generate_monthly_invoices(db, "2026-03")
        result = run_payment_reminders(db, today=date(2026, 3, 20))
        assert result["marked_overdue"] == 1 and result["reminders_sent"] == 1
        inv = db.scalars(sa.select(Invoice)).one()
        assert inv.status == "OVERDUE"
    assert DevMockEmailProvider.get_last_email("user5@example.com")["subject"] == "Rent overdue"
