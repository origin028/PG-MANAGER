import uuid
from typing import Any, Dict, List, Optional
import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDMixin


class Room(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "rooms"

    property_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("properties.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    floor_number: Mapped[int] = mapped_column(sa.Integer, default=1, nullable=False)
    room_number: Mapped[str] = mapped_column(sa.String(50), nullable=False)
    room_type: Mapped[str] = mapped_column(
        sa.String(50), default="DOUBLE_SHARING", nullable=False
    )  # SINGLE, DOUBLE_SHARING, TRIPLE_SHARING, FOUR_SHARING
    max_occupancy: Mapped[int] = mapped_column(sa.Integer, default=2, nullable=False)
    base_rent: Mapped[float] = mapped_column(sa.Numeric(10, 2), default=0.00, nullable=False)
    is_active: Mapped[bool] = mapped_column(sa.Boolean, default=True, nullable=False)
    amenities: Mapped[Dict[str, Any]] = mapped_column(sa.JSON, default=dict, nullable=False)

    # Relationships
    property: Mapped["Property"] = relationship("Property", back_populates="rooms")
    beds: Mapped[List["Bed"]] = relationship("Bed", back_populates="room", cascade="all, delete-orphan")
    residents: Mapped[List["Resident"]] = relationship("Resident", back_populates="room")
