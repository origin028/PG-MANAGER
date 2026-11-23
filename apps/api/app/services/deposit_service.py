"""Security-deposit policy and ledger.

Owner policy: when a resident leaves they get back DEPOSIT_REFUND_PERCENT (50%) of the
deposit they paid, regardless of how long they stayed. Unpaid dues and damage charges are
deducted from the refundable portion. All arithmetic is Decimal, rounded half-up to paise.
"""
import uuid
from datetime import datetime, timezone
from dataclasses import dataclass
from decimal import ROUND_HALF_UP, Decimal
from typing import List, Optional

import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.deposit_ledger import (
    DEPOSIT_DEDUCTED,
    DEPOSIT_FORFEITED,
    DEPOSIT_RECEIVED,
    DEPOSIT_REFUNDED,
    DepositLedgerEntry,
)
from app.models.resident import Resident

CENT = Decimal("0.01")


def money(value) -> Decimal:
    return Decimal(str(value or 0)).quantize(CENT, rounding=ROUND_HALF_UP)


@dataclass(frozen=True)
class ExitSettlement:
    deposit_held: Decimal
    refundable_base: Decimal   # deposit x refund %
    forfeited: Decimal         # deposit - refundable_base (kept by PG under policy)
    deductions: Decimal        # unpaid dues + damages
    deducted_from_deposit: Decimal
    refund: Decimal            # paid back to resident
    net_payable_by_resident: Decimal  # deductions the deposit could not cover


def compute_exit_settlement(
    deposit_held, unpaid_dues=0, damage_charges=0, refund_percent: Optional[int] = None
) -> ExitSettlement:
    pct = settings.DEPOSIT_REFUND_PERCENT if refund_percent is None else refund_percent
    if not 0 <= pct <= 100:
        raise ValueError("refund percent must be between 0 and 100")
    held = money(deposit_held)
    base = (held * Decimal(pct) / Decimal(100)).quantize(CENT, rounding=ROUND_HALF_UP)
    forfeited = held - base
    deductions = money(unpaid_dues) + money(damage_charges)
    covered = min(base, deductions)
    return ExitSettlement(
        deposit_held=held,
        refundable_base=base,
        forfeited=forfeited,
        deductions=deductions,
        deducted_from_deposit=covered,
        refund=base - covered,
        net_payable_by_resident=deductions - covered,
    )


class DepositService:
    def __init__(self, db: Session):
        self.db = db

    def _add(self, resident: Resident, company_id, entry_type, amount, note, user_id) -> DepositLedgerEntry:
        entry = DepositLedgerEntry(
            company_id=company_id,
            property_id=resident.property_id,
            resident_id=resident.id,
            entry_type=entry_type,
            amount=money(amount),
            note=note,
            created_by_id=user_id,
            # Explicit per-entry time: entries in one transaction share now(), which would make order ambiguous.
            created_at=datetime.now(timezone.utc),
        )
        self.db.add(entry)
        return entry

    def balance(self, resident_id: uuid.UUID) -> Decimal:
        """Deposit currently held for the resident (received - refunded - forfeited - deducted)."""
        rows = self.db.execute(
            sa.select(DepositLedgerEntry.entry_type, sa.func.sum(DepositLedgerEntry.amount))
            .where(DepositLedgerEntry.resident_id == resident_id)
            .group_by(DepositLedgerEntry.entry_type)
        ).all()
        totals = {t: money(v) for t, v in rows}
        return (
            totals.get(DEPOSIT_RECEIVED, Decimal(0))
            - totals.get(DEPOSIT_REFUNDED, Decimal(0))
            - totals.get(DEPOSIT_FORFEITED, Decimal(0))
            - totals.get(DEPOSIT_DEDUCTED, Decimal(0))
        )

    def entries(self, resident_id: uuid.UUID) -> List[DepositLedgerEntry]:
        return list(
            self.db.scalars(
                sa.select(DepositLedgerEntry)
                .where(DepositLedgerEntry.resident_id == resident_id)
                .order_by(DepositLedgerEntry.created_at, DepositLedgerEntry.id)
            )
        )

    def record_received(self, resident: Resident, company_id, amount, note, user_id) -> DepositLedgerEntry:
        amt = money(amount)
        if amt <= 0:
            raise ValueError("Deposit amount must be positive.")
        entry = self._add(resident, company_id, DEPOSIT_RECEIVED, amt, note or "Security deposit received", user_id)
        resident.security_deposit = self.balance(resident.id) + amt  # running total held
        return entry

    def settle_exit(
        self, resident: Resident, company_id, unpaid_dues, damage_charges, user_id
    ) -> ExitSettlement:
        """Writes the exit entries. Deposit held is taken from the ledger, not from a mutable field."""
        held = self.balance(resident.id)
        if held == 0 and resident.security_deposit:
            # Resident predates the ledger: seed it so history stays auditable.
            self._add(resident, company_id, DEPOSIT_RECEIVED, resident.security_deposit,
                      "Opening balance (migrated from resident record)", user_id)
            held = money(resident.security_deposit)
        s = compute_exit_settlement(held, unpaid_dues, damage_charges)
        pct = settings.DEPOSIT_REFUND_PERCENT
        if s.forfeited > 0:
            self._add(resident, company_id, DEPOSIT_FORFEITED, s.forfeited,
                      f"Retained under policy ({100 - pct}% non-refundable)", user_id)
        if s.deducted_from_deposit > 0:
            self._add(resident, company_id, DEPOSIT_DEDUCTED, s.deducted_from_deposit,
                      "Unpaid dues / damage charges", user_id)
        if s.refund > 0:
            self._add(resident, company_id, DEPOSIT_REFUNDED, s.refund, "Refund to resident on move-out", user_id)
        return s
