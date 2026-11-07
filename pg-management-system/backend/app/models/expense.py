import builtins
import uuid
from datetime import date
from typing import Optional
import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDMixin


class Expense(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "expenses"

    company_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("companies.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    property_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("properties.id", ondelete="CASCADE"),
        nullable=True,
        index=True,
    )
    created_by_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )

    category: Mapped[str] = mapped_column(
        sa.String(50), nullable=False
    )  # GROCERIES, UTILITIES, MAINTENANCE, SALARY, RENT_TO_OWNER, INTERNET, OTHER
    title: Mapped[str] = mapped_column(sa.String(200), nullable=False)
    amount: Mapped[float] = mapped_column(sa.Numeric(10, 2), nullable=False)
    method: Mapped[str] = mapped_column(sa.String(50), default="UPI", nullable=False)
    date: Mapped[date] = mapped_column(sa.Date, nullable=False)
    notes: Mapped[Optional[str]] = mapped_column(sa.Text, nullable=True)

    # Aliases / backward compatibility
    @builtins.property
    def expense_date(self) -> date:
        return self.date

    @expense_date.setter
    def expense_date(self, val: date) -> None:
        self.date = val

    @builtins.property
    def payment_mode(self) -> str:
        return self.method

    @payment_mode.setter
    def payment_mode(self, val: str) -> None:
        self.method = val

    @builtins.property
    def recorded_by_user_id(self) -> Optional[uuid.UUID]:
        return self.created_by_id

    @recorded_by_user_id.setter
    def recorded_by_user_id(self, val: Optional[uuid.UUID]) -> None:
        self.created_by_id = val

    # Relationships
    company: Mapped["Company"] = relationship("Company")
    property: Mapped[Optional["Property"]] = relationship("Property", back_populates="expenses")
    created_by: Mapped[Optional["User"]] = relationship("User")


@sa.event.listens_for(Expense, "before_insert")
def auto_populate_expense_company_id(mapper, connection, target):
    if not target.company_id and target.property_id:
        from app.models.property import Property
        prop_company_id = connection.execute(
            sa.select(Property.company_id).where(Property.id == target.property_id)
        ).scalar()
        if prop_company_id:
            target.company_id = prop_company_id
