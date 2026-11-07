import uuid
from datetime import datetime
import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin, UUIDMixin


class OtpVerification(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "otp_verifications"

    email: Mapped[str] = mapped_column(sa.String(255), index=True, nullable=False)
    otp_hash: Mapped[str] = mapped_column(sa.String(255), nullable=False)
    expires_at: Mapped[datetime] = mapped_column(sa.DateTime(timezone=True), nullable=False)
    is_used: Mapped[bool] = mapped_column(sa.Boolean, default=False, nullable=False)
    attempts: Mapped[int] = mapped_column(sa.Integer, default=0, nullable=False)
