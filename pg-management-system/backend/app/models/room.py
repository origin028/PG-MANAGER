import builtins
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
    base_monthly_rent: Mapped[float] = mapped_column(sa.Numeric(10, 2), default=0.00, nullable=False)
    deposit_amount: Mapped[float] = mapped_column(sa.Numeric(10, 2), default=0.00, nullable=False)
    is_active: Mapped[bool] = mapped_column(sa.Boolean, default=True, nullable=False)
    amenities: Mapped[Dict[str, Any]] = mapped_column(sa.JSON, default=dict, nullable=False)

    # Relationships
    property: Mapped["Property"] = relationship("Property", back_populates="rooms")
    beds: Mapped[List["Bed"]] = relationship("Bed", back_populates="room", cascade="all, delete-orphan")
    residents: Mapped[List["Resident"]] = relationship("Resident", back_populates="room")

    @builtins.property
    def base_rent(self) -> float:
        return float(self.base_monthly_rent or 0.0)

    @base_rent.setter
    def base_rent(self, value: float) -> None:
        self.base_monthly_rent = value

    @builtins.property
    def max_occupancy(self) -> int:
        if getattr(self, "_max_occupancy_val", None) is not None:
            return self._max_occupancy_val
        type_upper = (self.room_type or "").upper()
        if "SINGLE" in type_upper:
            return 1
        elif "DOUBLE" in type_upper:
            return 2
        elif "TRIPLE" in type_upper:
            return 3
        elif "FOUR" in type_upper:
            return 4
        return max(len(self.beds) if self.beds else 1, 1)

    @max_occupancy.setter
    def max_occupancy(self, value: int) -> None:
        self._max_occupancy_val = value

    @builtins.property
    def floor(self) -> int:
        return self.floor_number

    @floor.setter
    def floor(self, value: int) -> None:
        self.floor_number = value
