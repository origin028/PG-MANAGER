import uuid
from datetime import datetime
from typing import Optional
import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDMixin


class Bed(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "beds"

    property_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("properties.id", ondelete="CASCADE"),
        nullable=True,
        index=True,
    )
    room_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("rooms.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    bed_number: Mapped[str] = mapped_column(sa.String(50), nullable=False)
    status: Mapped[str] = mapped_column(
        sa.String(50), default="AVAILABLE", nullable=False, index=True
    )  # AVAILABLE, OCCUPIED, RESERVED, MAINTENANCE
    monthly_rent: Mapped[Optional[float]] = mapped_column(sa.Numeric(10, 2), nullable=True)
    is_active: Mapped[bool] = mapped_column(sa.Boolean, default=True, nullable=False)
    is_deleted: Mapped[bool] = mapped_column(sa.Boolean, default=False, nullable=False, server_default="false")
    deleted_at: Mapped[Optional[datetime]] = mapped_column(sa.DateTime(timezone=True), nullable=True)

    # Relationships
    room: Mapped["Room"] = relationship("Room", back_populates="beds")
    property: Mapped[Optional["Property"]] = relationship("Property")
    resident: Mapped[Optional["Resident"]] = relationship(
        "Resident", back_populates="bed", uselist=False
    )


@sa.event.listens_for(Bed, "before_insert")
def auto_populate_bed_property_id(mapper, connection, target):
    if not target.property_id and target.room_id:
        room_table = sa.table(
            "rooms",
            sa.column("id", sa.Uuid),
            sa.column("property_id", sa.Uuid),
        )
        stmt = sa.select(room_table.c.property_id).where(room_table.c.id == target.room_id)
        pid = connection.execute(stmt).scalar()
        if pid:
            target.property_id = pid
