"""Overdue marking and rent reminders."""
from datetime import date, timedelta
from typing import Optional

import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.core.logging import logger
from app.db.session import SessionLocal
from app.integrations.email import get_email_provider
from app.models.invoice import Invoice
from app.models.resident import Resident


def run_payment_reminders(db: Session, today: Optional[date] = None, upcoming_days: int = 3) -> dict:
    """Marks past-due invoices OVERDUE, then emails residents with overdue or soon-due invoices."""
    today = today or date.today()
    overdue_rows = db.execute(
        sa.update(Invoice)
        .where(Invoice.status.in_(("PENDING", "PARTIALLY_PAID")), Invoice.due_date < today)
        .values(status="OVERDUE")
    )
    db.commit()

    invoices = db.scalars(
        sa.select(Invoice).where(
            sa.or_(
                Invoice.status == "OVERDUE",
                sa.and_(
                    Invoice.status.in_(("PENDING", "PARTIALLY_PAID")),
                    Invoice.due_date <= today + timedelta(days=upcoming_days),
                ),
            )
        )
    ).all()

    provider = get_email_provider()
    sent = failed = 0
    for inv in invoices:
        resident = db.get(Resident, inv.resident_id)
        email = resident.user.email if resident and resident.user else None
        if not email or resident.status == "CHECKED_OUT":
            continue
        balance = float(inv.amount) - float(inv.paid_amount)
        overdue = inv.due_date < today
        subject = "Rent overdue" if overdue else "Rent due soon"
        body = (
            f"Hello {resident.user.full_name},\n\n"
            f"Your rent invoice {inv.invoice_number} for {inv.billing_month} "
            f"({'was due on' if overdue else 'is due on'} {inv.due_date:%d %b %Y}) has a balance of INR {balance:,.2f}.\n"
            "Please pay via the resident app.\n"
        )
        try:
            provider.send_email(email, subject, body)
            sent += 1
        except Exception as exc:  # one bad address must not stop the batch
            failed += 1
            logger.warning("reminder to invoice %s failed: %s", inv.invoice_number, type(exc).__name__)
    logger.info("reminders: marked_overdue=%d sent=%d failed=%d", overdue_rows.rowcount, sent, failed)
    return {"status": "SUCCESS", "marked_overdue": overdue_rows.rowcount, "reminders_sent": sent, "failed": failed}


def send_payment_reminders_job() -> dict:
    with SessionLocal() as db:
        return run_payment_reminders(db)
