import uuid
from typing import List, Optional
import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDMixin


class Bed(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "beds"

    property_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("properties.id", ondelete="RESTRICT"),
        nullable=False,
        index=True,
    )
    room_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True),
        nullable=False,
        index=True,
    )
    bed_number: Mapped[str] = mapped_column(sa.String(50), nullable=False)
    monthly_rent: Mapped[float] = mapped_column(
        sa.Numeric(10, 2), default=0.00, nullable=False
    )
    status: Mapped[str] = mapped_column(
        sa.String(50), default="AVAILABLE", nullable=False
    )  # AVAILABLE, OCCUPIED, RESERVED, MAINTENANCE
    is_active: Mapped[bool] = mapped_column(sa.Boolean, default=True, nullable=False)

    # Relationships
    room: Mapped["Room"] = relationship("Room", back_populates="beds", foreign_keys=[room_id, property_id], overlaps="beds,property")
    property: Mapped["Property"] = relationship("Property", back_populates="beds", foreign_keys=[property_id], overlaps="beds,room")
    residents: Mapped[List["Resident"]] = relationship("Resident", back_populates="bed", foreign_keys="[Resident.bed_id, Resident.property_id]", overlaps="residents,property,room,bed")

    __table_args__ = (
        sa.UniqueConstraint("room_id", "bed_number", name="uq_bed_room_bed_number"),
        sa.UniqueConstraint("id", "property_id", name="uq_beds_id_property_id"),
        sa.ForeignKeyConstraint(
            ["room_id", "property_id"],
            ["rooms.id", "rooms.property_id"],
            name="fk_beds_room_id_property_id",
            ondelete="RESTRICT",
        ),
        sa.Index("ix_beds_property_status", "property_id", "status"),
    )
