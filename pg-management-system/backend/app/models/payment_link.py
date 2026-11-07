import uuid
from datetime import datetime
from typing import Optional
import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDMixin


class PaymentLink(Base, UUIDMixin, TimestampMixin):
    """Secure, opaque payment link token for resident self-checkout."""
    __tablename__ = "payment_links"

    payment_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("payments.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    invoice_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("invoices.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    resident_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("residents.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    # Hex-encoded SHA-256 hash of the unguessable raw token
    token_hash: Mapped[str] = mapped_column(sa.String(64), unique=True, nullable=False, index=True)
    expires_at: Mapped[datetime] = mapped_column(sa.DateTime(timezone=True), nullable=False, index=True)
    is_revoked: Mapped[bool] = mapped_column(sa.Boolean, default=False, nullable=False, index=True)
    whatsapp_sent: Mapped[bool] = mapped_column(sa.Boolean, default=False, nullable=False)
    whatsapp_message_id: Mapped[Optional[str]] = mapped_column(sa.String(150), nullable=True)
    whatsapp_last_error: Mapped[Optional[str]] = mapped_column(sa.Text, nullable=True)

    # Relationships
    payment: Mapped["Payment"] = relationship("Payment")
    invoice: Mapped["Invoice"] = relationship("Invoice")
    resident: Mapped["Resident"] = relationship("Resident")
