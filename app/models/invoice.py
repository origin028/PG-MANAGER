import uuid
from datetime import date
from decimal import Decimal
from typing import List, Optional
import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDMixin


class Invoice(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "invoices"

    company_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("companies.id", ondelete="RESTRICT"),
        nullable=False,
        index=True,
    )
    property_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("properties.id", ondelete="RESTRICT"),
        nullable=False,
        index=True,
    )
    resident_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True),
        nullable=False,
        index=True,
    )
    invoice_number: Mapped[str] = mapped_column(
        sa.String(100), unique=True, index=True, nullable=False
    )
    billing_month: Mapped[str] = mapped_column(
        sa.String(7), index=True, nullable=False  # YYYY-MM format
    )
    billing_period_start: Mapped[date] = mapped_column(sa.Date, nullable=False)
    billing_period_end: Mapped[date] = mapped_column(sa.Date, nullable=False)
    issue_date: Mapped[date] = mapped_column(sa.Date, nullable=False)
    due_date: Mapped[date] = mapped_column(sa.Date, index=True, nullable=False)
    invoice_type: Mapped[str] = mapped_column(
        sa.String(50), default="RENT", nullable=False
    )  # RENT, SECURITY_DEPOSIT, MAINTENANCE, PENALTY
    rent_amount: Mapped[Decimal] = mapped_column(
        sa.Numeric(10, 2), default=Decimal("0.00"), nullable=False
    )
    additional_charges: Mapped[Decimal] = mapped_column(
        sa.Numeric(10, 2), default=Decimal("0.00"), nullable=False
    )
    discount_amount: Mapped[Decimal] = mapped_column(
        sa.Numeric(10, 2), default=Decimal("0.00"), nullable=False
    )
    total_amount: Mapped[Decimal] = mapped_column(
        sa.Numeric(10, 2), default=Decimal("0.00"), nullable=False
    )
    paid_amount: Mapped[Decimal] = mapped_column(
        sa.Numeric(10, 2), default=Decimal("0.00"), nullable=False
    )
    balance_amount: Mapped[Decimal] = mapped_column(
        sa.Numeric(10, 2), default=Decimal("0.00"), nullable=False
    )
    status: Mapped[str] = mapped_column(
        sa.String(50), default="ISSUED", index=True, nullable=False
    )  # DRAFT, ISSUED, PARTIALLY_PAID, PAID, OVERDUE, CANCELLED
    notes: Mapped[Optional[str]] = mapped_column(sa.String(255), nullable=True)

    # Relationships
    company: Mapped["Company"] = relationship("Company")
    property: Mapped["Property"] = relationship("Property", back_populates="invoices", overlaps="invoices,property")
    resident: Mapped["Resident"] = relationship(
        "Resident",
        back_populates="invoices",
        foreign_keys=[resident_id, property_id],
        overlaps="invoices,resident,property",
    )
    payments: Mapped[List["Payment"]] = relationship(
        "Payment",
        back_populates="invoice",
        foreign_keys="[Payment.invoice_id, Payment.property_id]",
        cascade="all, delete-orphan",
        overlaps="payments,invoice",
    )

    __table_args__ = (
        sa.ForeignKeyConstraint(
            ["resident_id", "property_id"],
            ["residents.id", "residents.property_id"],
            name="fk_invoices_resident_id_property_id",
            ondelete="RESTRICT",
        ),
        sa.UniqueConstraint("resident_id", "billing_month", "invoice_type", name="uq_resident_billing_month_type"),
        sa.UniqueConstraint("id", "property_id", name="uq_invoices_id_property_id"),
        sa.Index("ix_invoices_property_status", "property_id", "status"),
    )
