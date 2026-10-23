import uuid
from datetime import datetime
from typing import Optional
import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDMixin


class Notification(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "notifications"

    user_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    title: Mapped[str] = mapped_column(sa.String(200), nullable=False)
    body: Mapped[str] = mapped_column(sa.Text, nullable=False)
    channel: Mapped[str] = mapped_column(
        sa.String(50), default="PUSH", nullable=False
    )  # PUSH, SMS, WHATSAPP, EMAIL
    status: Mapped[str] = mapped_column(
        sa.String(50), default="PENDING", nullable=False, index=True
    )  # PENDING, SENT, FAILED
    scheduled_at: Mapped[Optional[datetime]] = mapped_column(sa.DateTime(timezone=True), nullable=True)
    sent_at: Mapped[Optional[datetime]] = mapped_column(sa.DateTime(timezone=True), nullable=True)

    # Relationships
    user: Mapped["User"] = relationship("User", back_populates="notifications")
