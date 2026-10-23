import uuid
from datetime import datetime
from typing import Optional
import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDMixin


class Payment(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "payments"

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

    # Relationships
    invoice: Mapped["Invoice"] = relationship("Invoice", back_populates="payments")
    resident: Mapped["Resident"] = relationship("Resident", back_populates="payments")
