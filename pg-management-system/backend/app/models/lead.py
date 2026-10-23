import uuid
from datetime import datetime
from typing import Optional
import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDMixin


class Lead(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "leads"

    property_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("properties.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    name: Mapped[str] = mapped_column(sa.String(150), nullable=False)
    phone: Mapped[str] = mapped_column(sa.String(30), index=True, nullable=False)
    email: Mapped[Optional[str]] = mapped_column(sa.String(255), nullable=True)
    status: Mapped[str] = mapped_column(
        sa.String(50), default="NEW", nullable=False, index=True
    )  # NEW, CONTACTED, VISIT_SCHEDULED, BOOKED, LOST
    visit_date: Mapped[Optional[datetime]] = mapped_column(sa.DateTime(timezone=True), nullable=True)
    notes: Mapped[Optional[str]] = mapped_column(sa.Text, nullable=True)

    # Relationships
    property: Mapped["Property"] = relationship("Property", back_populates="leads")
