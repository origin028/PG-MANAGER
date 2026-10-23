import uuid
from datetime import date
from typing import Optional
import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDMixin


class Expense(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "expenses"

    property_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("properties.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    recorded_by_user_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("users.id", ondelete="RESTRICT"),
        nullable=False,
        index=True,
    )

    category: Mapped[str] = mapped_column(
        sa.String(50), nullable=False
    )  # GROCERIES, UTILITIES, MAINTENANCE, SALARY, RENT_TO_OWNER, INTERNET, OTHER
    title: Mapped[str] = mapped_column(sa.String(200), nullable=False)
    amount: Mapped[float] = mapped_column(sa.Numeric(10, 2), nullable=False)
    payment_mode: Mapped[str] = mapped_column(sa.String(50), default="UPI", nullable=False)
    expense_date: Mapped[date] = mapped_column(sa.Date, nullable=False)
    receipt_url: Mapped[Optional[str]] = mapped_column(sa.String(512), nullable=True)
    notes: Mapped[Optional[str]] = mapped_column(sa.Text, nullable=True)

    # Relationships
    property: Mapped["Property"] = relationship("Property", back_populates="expenses")
