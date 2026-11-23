import uuid
from datetime import datetime
from typing import Optional

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin, UUIDMixin


class AttendanceLog(Base, UUIDMixin, TimestampMixin):
    """One fingerprint-machine punch. Append-only; duplicates are rejected by the unique key."""

    __tablename__ = "attendance_logs"
    __table_args__ = (
        sa.UniqueConstraint("property_id", "device_user_id", "punched_at", name="uq_attendance_punch"),
        sa.Index("ix_attendance_property_time", "property_id", "punched_at"),
    )

    property_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True), sa.ForeignKey("properties.id", ondelete="CASCADE"), nullable=False
    )
    resident_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        sa.Uuid(as_uuid=True), sa.ForeignKey("residents.id", ondelete="SET NULL"), nullable=True, index=True
    )
    device_user_id: Mapped[str] = mapped_column(sa.String(64), nullable=False)
    punched_at: Mapped[datetime] = mapped_column(sa.DateTime(timezone=True), nullable=False)
    direction: Mapped[str] = mapped_column(sa.String(8), nullable=False, default="IN")  # IN | OUT
