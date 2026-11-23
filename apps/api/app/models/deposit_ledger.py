import uuid
from typing import Optional

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin, UUIDMixin

# Entry types (append-only ledger; amounts are always positive, the type gives the direction)
DEPOSIT_RECEIVED = "DEPOSIT_RECEIVED"   # money in: resident paid deposit
DEPOSIT_REFUNDED = "DEPOSIT_REFUNDED"   # money out: refund paid to resident on exit
DEPOSIT_FORFEITED = "DEPOSIT_FORFEITED"  # retained by the PG under the refund policy
DEPOSIT_DEDUCTED = "DEPOSIT_DEDUCTED"   # retained to cover unpaid dues / damages


class DepositLedgerEntry(Base, UUIDMixin, TimestampMixin):
    """Append-only security-deposit ledger. Never updated or deleted."""

    __tablename__ = "deposit_ledger"
    __table_args__ = (sa.CheckConstraint("amount >= 0", name="ck_deposit_ledger_amount_nonneg"),)

    company_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True), sa.ForeignKey("companies.id", ondelete="CASCADE"), nullable=False, index=True
    )
    property_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True), sa.ForeignKey("properties.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    resident_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True), sa.ForeignKey("residents.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    entry_type: Mapped[str] = mapped_column(sa.String(32), nullable=False, index=True)
    amount: Mapped[float] = mapped_column(sa.Numeric(10, 2), nullable=False)
    note: Mapped[Optional[str]] = mapped_column(sa.String(255), nullable=True)
    created_by_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        sa.Uuid(as_uuid=True), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
