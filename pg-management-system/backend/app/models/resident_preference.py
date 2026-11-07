import uuid
import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDMixin


class ResidentPreference(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "resident_preferences"

    user_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("users.id", ondelete="CASCADE"),
        unique=True,
        nullable=False,
        index=True,
    )
    dark_mode: Mapped[bool] = mapped_column(
        sa.Boolean, default=False, nullable=False
    )
    language: Mapped[str] = mapped_column(
        sa.String(10), default="en", nullable=False
    )
    rent_reminders_enabled: Mapped[bool] = mapped_column(
        sa.Boolean, default=True, nullable=False
    )
    maintenance_alerts_enabled: Mapped[bool] = mapped_column(
        sa.Boolean, default=True, nullable=False
    )

    # Relationships
    user: Mapped["User"] = relationship("User", back_populates="resident_preference")
