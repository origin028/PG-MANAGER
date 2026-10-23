import uuid
from typing import Optional
import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDMixin


class Bed(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "beds"

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

    # Relationships
    room: Mapped["Room"] = relationship("Room", back_populates="beds")
    resident: Mapped[Optional["Resident"]] = relationship(
        "Resident", back_populates="bed", uselist=False
    )
