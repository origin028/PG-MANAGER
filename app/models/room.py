import uuid
from typing import Any, Dict, List, Optional
import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDMixin


class Room(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "rooms"

    property_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("properties.id", ondelete="RESTRICT"),
        nullable=False,
        index=True,
    )
    room_number: Mapped[str] = mapped_column(sa.String(50), nullable=False)
    floor_number: Mapped[int] = mapped_column(sa.Integer, default=1, nullable=False)
    room_type: Mapped[str] = mapped_column(
        sa.String(50), default="DOUBLE", nullable=False
    )  # SINGLE, DOUBLE, TRIPLE, FOUR_SHARING, DORMITORY, OTHER
    base_monthly_rent: Mapped[float] = mapped_column(
        sa.Numeric(10, 2), default=0.00, nullable=False
    )
    deposit_amount: Mapped[float] = mapped_column(
        sa.Numeric(10, 2), default=0.00, nullable=False
    )
    amenities: Mapped[List[str]] = mapped_column(
        sa.JSON, default=list, nullable=False
    )
    is_active: Mapped[bool] = mapped_column(sa.Boolean, default=True, nullable=False)

    # Relationships
    property: Mapped["Property"] = relationship("Property", back_populates="rooms")
    beds: Mapped[List["Bed"]] = relationship(
        "Bed", back_populates="room", overlaps="beds"
    )
    residents: Mapped[List["Resident"]] = relationship(
        "Resident", back_populates="room", foreign_keys="[Resident.room_id, Resident.property_id]", overlaps="residents,property,room,bed"
    )

    __table_args__ = (
        sa.UniqueConstraint("property_id", "room_number", name="uq_room_property_room_number"),
        sa.UniqueConstraint("id", "property_id", name="uq_rooms_id_property_id"),
        sa.Index("ix_rooms_property_floor", "property_id", "floor_number"),
    )
