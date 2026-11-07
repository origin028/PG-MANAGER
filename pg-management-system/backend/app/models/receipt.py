import uuid
from datetime import datetime
from typing import Optional, TYPE_CHECKING
import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDMixin

if TYPE_CHECKING:
    from app.models.payment import Payment
    from app.models.invoice import Invoice


class Receipt(Base, UUIDMixin, TimestampMixin):
    """Immutable receipt issued exactly once for a settled payment."""
    __tablename__ = "receipts"

    payment_id: Mapped[uuid.UUID] = mapped_column(sa.Uuid(as_uuid=True), sa.ForeignKey("payments.id", ondelete="RESTRICT"), unique=True, nullable=False, index=True)
    invoice_id: Mapped[uuid.UUID] = mapped_column(sa.Uuid(as_uuid=True), sa.ForeignKey("invoices.id", ondelete="RESTRICT"), nullable=False, index=True)
    receipt_number: Mapped[str] = mapped_column(sa.String(100), unique=True, nullable=False, index=True)
    amount: Mapped[float] = mapped_column(sa.Numeric(10, 2), nullable=False)
    issued_at: Mapped[datetime] = mapped_column(sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False)
    whatsapp_status: Mapped[str] = mapped_column(sa.String(50), default="PENDING", nullable=False, index=True)
    whatsapp_attempts: Mapped[int] = mapped_column(sa.Integer, default=0, nullable=False)
    next_retry_at: Mapped[Optional[datetime]] = mapped_column(sa.DateTime(timezone=True), nullable=True)
    last_delivery_error: Mapped[Optional[str]] = mapped_column(sa.Text, nullable=True)

    # Explicit ORM Relationships
    payment: Mapped["Payment"] = relationship("Payment", foreign_keys=[payment_id])
    invoice: Mapped["Invoice"] = relationship("Invoice", foreign_keys=[invoice_id])
