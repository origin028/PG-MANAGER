import uuid
from typing import List, Optional
import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDMixin


class FoodMenu(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "food_menus"

    property_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("properties.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    day_of_week: Mapped[str] = mapped_column(
        sa.String(10), nullable=False
    )  # MONDAY, TUESDAY, WEDNESDAY, THURSDAY, FRIDAY, SATURDAY, SUNDAY
    meal_type: Mapped[str] = mapped_column(
        sa.String(20), nullable=False
    )  # BREAKFAST, LUNCH, DINNER
    start_time: Mapped[Optional[str]] = mapped_column(
        sa.String(10), nullable=True
    )
    end_time: Mapped[Optional[str]] = mapped_column(
        sa.String(10), nullable=True
    )
    dishes: Mapped[List[str]] = mapped_column(
        sa.JSON, default=list, nullable=False
    )
    is_active: Mapped[bool] = mapped_column(
        sa.Boolean, default=True, nullable=False
    )

    # Relationships
    property: Mapped["Property"] = relationship("Property", back_populates="food_menus")
