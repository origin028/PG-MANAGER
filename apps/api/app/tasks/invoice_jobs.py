"""Monthly rent invoicing. Idempotent: safe to run any number of times for the same month."""
import calendar
import uuid
from datetime import date
from decimal import Decimal
from typing import Optional

import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.logging import logger
from app.db.session import SessionLocal
from app.models.invoice import Invoice
from app.models.property import Property
from app.models.resident import Resident


def _due_date(billing_month: str) -> date:
    year, month = (int(x) for x in billing_month.split("-"))
    return date(year, month, min(settings.RENT_DUE_DAY, calendar.monthrange(year, month)[1]))


def generate_monthly_invoices(db: Session, billing_month: str) -> dict:
    """Creates one RENT invoice per active resident for ``billing_month`` (YYYY-MM)."""
    year, month = (int(x) for x in billing_month.split("-"))  # validates format
    month_start, month_end = date(year, month, 1), date(year, month, calendar.monthrange(year, month)[1])

    residents = db.scalars(
        sa.select(Resident)
        .join(Property, Property.id == Resident.property_id)
        .where(
            Resident.status.in_(("ACTIVE", "NOTICE_PERIOD")),
            Resident.monthly_rent > 0,
            Resident.bed_id.is_not(None),
        )
    ).all()
    created = skipped = 0
    for r in residents:
        # Do not bill before the resident joined or after they left.
        if r.check_in_date and r.check_in_date > month_end:
            skipped += 1
            continue
        if r.actual_check_out_date and r.actual_check_out_date < month_start:
            skipped += 1
            continue
        exists = db.scalar(
            sa.select(Invoice.id).where(
                Invoice.resident_id == r.id,
                Invoice.billing_month == billing_month,
                Invoice.invoice_type == "RENT",
            )
        )
        if exists:
            skipped += 1
            continue
        db.add(
            Invoice(
                property_id=r.property_id,
                resident_id=r.id,
                invoice_number=f"INV-{billing_month.replace('-', '')}-{uuid.uuid4().hex[:8].upper()}",
                billing_month=billing_month,
                invoice_type="RENT",
                amount=Decimal(str(r.monthly_rent)),
                paid_amount=Decimal("0.00"),
                due_date=_due_date(billing_month),
                status="PENDING",
                notes="Auto-generated monthly rent",
            )
        )
        created += 1
    db.commit()
    logger.info("monthly invoices %s: created=%d skipped=%d", billing_month, created, skipped)
    return {"status": "SUCCESS", "cycle": billing_month, "generated_count": created, "skipped": skipped}


def generate_monthly_invoices_job(billing_month: Optional[str] = None) -> dict:
    billing_month = billing_month or date.today().strftime("%Y-%m")
    with SessionLocal() as db:
        return generate_monthly_invoices(db, billing_month)
