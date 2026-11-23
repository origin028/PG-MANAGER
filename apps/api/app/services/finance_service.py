"""Month-by-month finance for the owner's Finance page.

All figures are for one calendar month in the PG's timezone and scoped to the owner's
company (optionally one property). Money is Decimal end to end; the API returns floats.

Definitions (shown to the owner in the app, keep them in sync):
- collected:        payments that succeeded with paid_at in the month (any bill type)
- spent:            expenses dated in the month
- profit:           collected - spent;  margin = profit / collected
- billed:           bills (invoices) for that billing month, excluding cancelled
- collection_rate:  share of that month's billed amount already paid
- unpaid_now:       amount still unpaid on bills up to and including that month
- residents:        living there at the end of the month (or today, for the current month)
- joined / left:    check-in / move-out dates inside the month
- revenue_per_bed:  collected / residents at month end
"""
import uuid
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from decimal import ROUND_HALF_UP, Decimal
from typing import Optional

import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.models.bed import Bed
from app.models.deposit_ledger import DEPOSIT_RECEIVED, DEPOSIT_REFUNDED, DepositLedgerEntry
from app.models.expense import Expense
from app.models.invoice import Invoice
from app.models.payment import Payment
from app.models.property import Property
from app.models.resident import Resident
from app.models.room import Room
from app.services.meal_service import tz

PAID = ("SUCCESS", "PAID")
OPEN = ("PENDING", "PARTIALLY_PAID", "OVERDUE")
NOT_LIVING = ("PENDING_APPROVAL", "REJECTED")
ZERO = Decimal("0")


def _d(v) -> Decimal:
    return Decimal(str(v or 0))


def _money(v: Decimal) -> float:
    return float(v.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP))


def month_bounds(month: date) -> tuple[date, date]:
    start = month.replace(day=1)
    nxt = (start + timedelta(days=32)).replace(day=1)
    return start, nxt  # [start, nxt)


def previous_month(month: date) -> date:
    return (month.replace(day=1) - timedelta(days=1)).replace(day=1)


@dataclass
class Scope:
    company_id: uuid.UUID
    property_ids: list[uuid.UUID]


def scope_for(db: Session, company_id: uuid.UUID, property_id: Optional[uuid.UUID]) -> Scope:
    ids = list(db.scalars(sa.select(Property.id).where(Property.company_id == company_id)))
    if property_id is not None:
        ids = [i for i in ids if i == property_id]
    return Scope(company_id, ids)


def month_summary(db: Session, scope: Scope, month: date, today: Optional[date] = None) -> dict:
    zone = tz()
    today = today or datetime.now(zone).date()
    start, end = month_bounds(month)
    start_dt, end_dt = datetime.combine(start, time.min, zone), datetime.combine(end, time.min, zone)
    as_of = min(today, end - timedelta(days=1))  # month end, or today for the current month
    ym = start.strftime("%Y-%m")
    props = scope.property_ids or [uuid.uuid4()]  # empty scope matches nothing

    # Collections
    rows = db.execute(
        sa.select(Payment.payment_mode, sa.func.coalesce(sa.func.sum(Payment.amount), 0), sa.func.count(Payment.id))
        .where(Payment.property_id.in_(props), Payment.status.in_(PAID), Payment.paid_at >= start_dt, Payment.paid_at < end_dt)
        .group_by(Payment.payment_mode)
    ).all()
    by_mode = {m: _d(a) for m, a, _ in rows}
    collected = sum(by_mode.values(), ZERO)
    payment_count = sum(c for _, _, c in rows)

    # Expenses (property-level or company-wide)
    erows = db.execute(
        sa.select(Expense.category, sa.func.coalesce(sa.func.sum(Expense.amount), 0))
        .where(Expense.company_id == scope.company_id, Expense.date >= start, Expense.date < end,
               sa.or_(Expense.property_id.in_(props), Expense.property_id.is_(None)))
        .group_by(Expense.category)
    ).all()
    by_category = {c: _d(a) for c, a in erows}
    spent = sum(by_category.values(), ZERO)
    profit = collected - spent

    # Billing for the month and money still owed
    billed, billed_paid = (_d(x) for x in db.execute(
        sa.select(sa.func.coalesce(sa.func.sum(Invoice.amount), 0), sa.func.coalesce(sa.func.sum(Invoice.paid_amount), 0))
        .where(Invoice.property_id.in_(props), Invoice.billing_month == ym, Invoice.status != "CANCELLED")
    ).one())
    unpaid_now = _d(db.scalar(
        sa.select(sa.func.coalesce(sa.func.sum(Invoice.amount - Invoice.paid_amount), 0))
        .where(Invoice.property_id.in_(props), Invoice.status.in_(OPEN), Invoice.billing_month <= ym)
    ))

    # Residents
    left_on = sa.func.coalesce(Resident.actual_check_out_date, Resident.expected_check_out_date)
    living = sa.and_(Resident.property_id.in_(props), Resident.status.notin_(NOT_LIVING), Resident.check_in_date <= as_of,
                     sa.or_(Resident.status != "CHECKED_OUT", left_on > as_of))
    residents = db.scalar(sa.select(sa.func.count(Resident.id)).where(living)) or 0
    joined = db.scalar(sa.select(sa.func.count(Resident.id)).where(
        Resident.property_id.in_(props), Resident.status.notin_(NOT_LIVING), Resident.check_in_date >= start, Resident.check_in_date < end)) or 0
    left = db.scalar(sa.select(sa.func.count(Resident.id)).where(
        Resident.property_id.in_(props), Resident.status == "CHECKED_OUT", left_on >= start, left_on < end)) or 0
    beds = db.scalar(sa.select(sa.func.count(Bed.id)).join(Room, Room.id == Bed.room_id).where(
        Room.property_id.in_(props), Room.is_active.is_(True), Bed.is_active.is_(True), Bed.is_deleted.is_(False))) or 0

    # Deposits
    drows = dict(db.execute(
        sa.select(DepositLedgerEntry.entry_type, sa.func.coalesce(sa.func.sum(DepositLedgerEntry.amount), 0))
        .where(DepositLedgerEntry.property_id.in_(props), DepositLedgerEntry.created_at >= start_dt, DepositLedgerEntry.created_at < end_dt)
        .group_by(DepositLedgerEntry.entry_type)
    ).all())

    return {
        "month": ym,
        "is_current": start <= today < end,
        "collected": _money(collected),
        "collected_by_mode": {k: _money(v) for k, v in by_mode.items()},
        "payment_count": payment_count,
        "spent": _money(spent),
        "spent_by_category": {k: _money(v) for k, v in sorted(by_category.items(), key=lambda x: -x[1])},
        "profit": _money(profit),
        "margin_percent": round(float(profit / collected * 100), 1) if collected else None,
        "billed": _money(billed),
        "billed_paid": _money(billed_paid),
        "collection_rate_percent": round(float(billed_paid / billed * 100), 1) if billed else None,
        "unpaid_now": _money(unpaid_now),
        "residents": residents,
        "joined": joined,
        "left": left,
        "net_growth": joined - left,
        "beds": beds,
        "occupancy_percent": round(residents / beds * 100, 1) if beds else None,
        "revenue_per_resident": _money(collected / residents) if residents else None,
        "deposits_received": _money(_d(drows.get(DEPOSIT_RECEIVED))),
        "deposits_refunded": _money(_d(drows.get(DEPOSIT_REFUNDED))),
    }


COMPARED = ("collected", "spent", "profit", "margin_percent", "billed", "collection_rate_percent", "unpaid_now",
            "residents", "joined", "left", "net_growth", "occupancy_percent", "revenue_per_resident", "deposits_received")


def compare(cur: dict, prev: dict) -> dict:
    """Change vs the previous month for each headline figure: absolute and % (None when not meaningful)."""
    out = {}
    for k in COMPARED:
        a, b = cur.get(k), prev.get(k)
        if a is None or b is None:
            out[k] = {"change": None, "percent": None}
            continue
        change = round(a - b, 2)
        pct = round(change / abs(b) * 100, 1) if b else None
        out[k] = {"change": change, "percent": pct}
    return out


TREND_FIELDS = (
    "month", "collected", "spent", "profit", "margin_percent", "residents", "joined", "left",
    "occupancy_percent", "collection_rate_percent", "unpaid_now", "spent_by_category",
)


def finance_report(db: Session, scope: Scope, month: date, months_of_trend: int = 6, today: Optional[date] = None) -> dict:
    cur = month_summary(db, scope, month, today)
    prev = month_summary(db, scope, previous_month(month), today)
    trend, m = [], month.replace(day=1)
    for _ in range(months_of_trend):
        s = cur if m == month.replace(day=1) else prev if m == previous_month(month) else month_summary(db, scope, m, today)
        trend.append({k: s[k] for k in TREND_FIELDS})
        m = previous_month(m)
    return {"current": cur, "previous": prev, "change": compare(cur, prev), "trend": list(reversed(trend))}
