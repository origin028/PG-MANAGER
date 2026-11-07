import uuid
from datetime import date
from decimal import Decimal
from typing import Optional
import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDMixin


class Expense(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "expenses"

    company_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("companies.id", ondelete="RESTRICT"),
        nullable=False,
        index=True,
    )
    property_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("properties.id", ondelete="RESTRICT"),
        nullable=True,
        index=True,
    )
    title: Mapped[str] = mapped_column(sa.String(150), nullable=False)
    category: Mapped[str] = mapped_column(sa.String(100), nullable=False)
    amount: Mapped[Decimal] = mapped_column(sa.Numeric(10, 2), nullable=False)
    date: Mapped[date] = mapped_column(sa.Date, nullable=False)
    method: Mapped[str] = mapped_column(sa.String(50), nullable=False)
    notes: Mapped[Optional[str]] = mapped_column(sa.Text, nullable=True)
    created_by_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        sa.Uuid(as_uuid=True), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )

    company: Mapped["Company"] = relationship("Company")
    property: Mapped[Optional["Property"]] = relationship("Property")
    created_by: Mapped[Optional["User"]] = relationship("User")
