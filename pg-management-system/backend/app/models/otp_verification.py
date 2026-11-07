import uuid
from datetime import datetime
from typing import Optional
import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin, UUIDMixin


class OTPVerification(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "otp_verifications"

    phone: Mapped[Optional[str]] = mapped_column(sa.String(30), nullable=True, index=True)
    email: Mapped[Optional[str]] = mapped_column(sa.String(255), nullable=True, index=True)
    otp_hash: Mapped[str] = mapped_column(sa.String(255), nullable=False)
    salt: Mapped[str] = mapped_column(sa.String(64), nullable=False)
    purpose: Mapped[str] = mapped_column(sa.String(50), default="RESIDENT_REGISTRATION", nullable=False, index=True)
    attempts: Mapped[int] = mapped_column(sa.Integer, default=0, nullable=False)
    max_attempts: Mapped[int] = mapped_column(sa.Integer, default=3, nullable=False)
    expires_at: Mapped[datetime] = mapped_column(sa.DateTime(timezone=True), nullable=False, index=True)
    is_verified: Mapped[bool] = mapped_column(sa.Boolean, default=False, nullable=False, index=True)
