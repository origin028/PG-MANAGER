import uuid
from datetime import datetime, timedelta
from typing import Optional
import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDMixin


class Payment(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "payments"
    __table_args__ = (sa.UniqueConstraint("invoice_id", "idempotency_key", name="uq_payment_invoice_idempotency"),)

    property_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("properties.id", ondelete="RESTRICT"),
        nullable=False,
        index=True,
    )
    invoice_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("invoices.id", ondelete="RESTRICT"),
        nullable=False,
        index=True,
    )
    resident_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("residents.id", ondelete="RESTRICT"),
        nullable=False,
        index=True,
    )
    payment_number: Mapped[str] = mapped_column(sa.String(100), unique=True, index=True, nullable=False)
    # Legacy ledger rows predate payment requests. New API-created requests
    # always set these values; NULL is retained only for historical records.
    idempotency_key: Mapped[Optional[str]] = mapped_column(sa.String(128), nullable=True)
    reservation_expires_at: Mapped[Optional[datetime]] = mapped_column(sa.DateTime(timezone=True), nullable=True, index=True)
    amount: Mapped[float] = mapped_column(sa.Numeric(10, 2), nullable=False)
    payment_mode: Mapped[str] = mapped_column(
        sa.String(50), default="UPI", nullable=False
    )  # UPI, CASH, BANK_TRANSFER, CARD
    gateway_order_id: Mapped[Optional[str]] = mapped_column(sa.String(150), nullable=True)
    gateway_payment_id: Mapped[Optional[str]] = mapped_column(sa.String(150), unique=True, nullable=True)
    gateway_signature: Mapped[Optional[str]] = mapped_column(sa.String(255), nullable=True)
    status: Mapped[str] = mapped_column(
        sa.String(50), default="PENDING", nullable=False, index=True
    )  # PENDING, SUCCESS, FAILED, REFUNDED
    receipt_url: Mapped[Optional[str]] = mapped_column(sa.String(512), nullable=True)
    paid_at: Mapped[Optional[datetime]] = mapped_column(sa.DateTime(timezone=True), nullable=True)

    @property
    def payment_method(self) -> str:
        return self.payment_mode

    @property
    def transaction_reference(self) -> Optional[str]:
        return self.gateway_payment_id or self.payment_number

    # Relationships
    invoice: Mapped["Invoice"] = relationship("Invoice", back_populates="payments")
    resident: Mapped["Resident"] = relationship("Resident", back_populates="payments")
