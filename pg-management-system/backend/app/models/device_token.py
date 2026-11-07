import uuid
from datetime import datetime
from typing import Optional
import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDMixin


class DeviceToken(Base, UUIDMixin, TimestampMixin):
    """Stores client device push notification tokens associated with users (provider-neutral)."""
    __tablename__ = "device_tokens"
    __table_args__ = (
        sa.UniqueConstraint("user_id", "device_token", name="uq_user_device_token"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    device_token: Mapped[str] = mapped_column(sa.String(255), index=True, nullable=False)
    platform: Mapped[str] = mapped_column(sa.String(50), default="android", nullable=False)
    device_name: Mapped[Optional[str]] = mapped_column(sa.String(100), nullable=True)
    is_active: Mapped[bool] = mapped_column(sa.Boolean, default=True, nullable=False)
    last_seen_at: Mapped[Optional[datetime]] = mapped_column(sa.DateTime(timezone=True), nullable=True)

    # Relationships
    user: Mapped["User"] = relationship("User", back_populates="device_tokens")
