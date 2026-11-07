import uuid
from datetime import date
from typing import List, Optional
import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDMixin


class Invoice(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "invoices"
    __table_args__ = (
        sa.UniqueConstraint("resident_id", "billing_month", "invoice_type", name="uq_resident_invoice_cycle"),
    )

    property_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("properties.id", ondelete="RESTRICT"),
        nullable=False,
        index=True,
    )
    resident_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("residents.id", ondelete="RESTRICT"),
        nullable=False,
        index=True,
    )
    invoice_number: Mapped[str] = mapped_column(sa.String(100), unique=True, index=True, nullable=False)
    billing_month: Mapped[str] = mapped_column(sa.String(7), nullable=False)  # YYYY-MM
    invoice_type: Mapped[str] = mapped_column(
        sa.String(50), default="RENT", nullable=False
    )  # RENT, SECURITY_DEPOSIT, MAINTENANCE, PENALTY, ELECTRICITY
    amount: Mapped[float] = mapped_column(sa.Numeric(10, 2), nullable=False)
    paid_amount: Mapped[float] = mapped_column(sa.Numeric(10, 2), default=0.00, nullable=False)
    due_date: Mapped[date] = mapped_column(sa.Date, nullable=False)
    status: Mapped[str] = mapped_column(
        sa.String(50), default="PENDING", nullable=False, index=True
    )  # PENDING, PARTIALLY_PAID, PAID, OVERDUE, CANCELLED
    notes: Mapped[Optional[str]] = mapped_column(sa.Text, nullable=True)

    @property
    def balance_amount(self) -> float:
        return max(0.0, float(self.amount) - float(self.paid_amount))

    # Relationships
    resident: Mapped["Resident"] = relationship("Resident", back_populates="invoices")
    payments: Mapped[List["Payment"]] = relationship("Payment", back_populates="invoice")
