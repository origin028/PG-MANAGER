from datetime import datetime
from typing import Optional
import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin, UUIDMixin


class PendingResidentRegistration(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "pending_resident_registrations"

    phone: Mapped[str] = mapped_column(
        sa.String(30), unique=True, index=True, nullable=False
    )
    email: Mapped[str] = mapped_column(
        sa.String(255), index=True, nullable=False
    )
    registration_data: Mapped[dict] = mapped_column(
        sa.JSON, nullable=False
    )
    expires_at: Mapped[datetime] = mapped_column(
        sa.DateTime(timezone=True), nullable=False
    )
