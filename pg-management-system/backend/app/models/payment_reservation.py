import uuid
from datetime import datetime
from typing import Optional
import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDMixin


class PaymentReservation(Base, UUIDMixin, TimestampMixin):
    """Tracks time-limited payment reservations and idempotency on invoices."""
    __tablename__ = "payment_reservations"

    invoice_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("invoices.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    resident_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("residents.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    payment_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("payments.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    amount: Mapped[float] = mapped_column(sa.Numeric(10, 2), nullable=False)
    idempotency_key: Mapped[str] = mapped_column(sa.String(128), unique=True, nullable=False, index=True)
    status: Mapped[str] = mapped_column(sa.String(32), default="PENDING", nullable=False, index=True)
    reservation_expires_at: Mapped[datetime] = mapped_column(sa.DateTime(timezone=True), nullable=False, index=True)

    # Relationships
    invoice: Mapped["Invoice"] = relationship("Invoice")
    resident: Mapped[Optional["Resident"]] = relationship("Resident")
    payment: Mapped[Optional["Payment"]] = relationship("Payment")
