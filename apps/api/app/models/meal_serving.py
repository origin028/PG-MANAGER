import uuid
from datetime import date, datetime
from typing import Optional

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin, UUIDMixin


class MealServing(Base, UUIDMixin, TimestampMixin):
    """One resident served one meal on one day. The unique key stops a pass being used twice."""

    __tablename__ = "meal_servings"
    __table_args__ = (
        sa.UniqueConstraint("resident_id", "meal_date", "meal_type", name="uq_meal_serving_once"),
        sa.Index("ix_meal_servings_property_date", "property_id", "meal_date"),
    )

    property_id: Mapped[uuid.UUID] = mapped_column(sa.Uuid(as_uuid=True), sa.ForeignKey("properties.id", ondelete="CASCADE"), nullable=False)
    resident_id: Mapped[uuid.UUID] = mapped_column(sa.Uuid(as_uuid=True), sa.ForeignKey("residents.id", ondelete="CASCADE"), nullable=False, index=True)
    meal_date: Mapped[date] = mapped_column(sa.Date, nullable=False)
    meal_type: Mapped[str] = mapped_column(sa.String(20), nullable=False)  # BREAKFAST | LUNCH | DINNER
    served_at: Mapped[datetime] = mapped_column(sa.DateTime(timezone=True), nullable=False)
    served_by_id: Mapped[Optional[uuid.UUID]] = mapped_column(sa.Uuid(as_uuid=True), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
