import uuid
from datetime import datetime
from typing import Optional
import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin, UUIDMixin


class ProcessedWebhookEvent(Base, UUIDMixin, TimestampMixin):
    """Tracks processed external webhook events for strict deduplication."""
    __tablename__ = "processed_webhook_events"

    provider: Mapped[str] = mapped_column(sa.String(50), nullable=False, index=True)
    event_id: Mapped[str] = mapped_column(sa.String(150), unique=True, nullable=False, index=True)
    event_type: Mapped[str] = mapped_column(sa.String(100), nullable=False, index=True)
    status: Mapped[str] = mapped_column(sa.String(50), default="PROCESSED", nullable=False)
    processed_at: Mapped[datetime] = mapped_column(sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False)
