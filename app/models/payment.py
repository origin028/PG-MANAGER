import uuid
from datetime import date, datetime
from decimal import Decimal
from typing import Optional
import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDMixin


class Payment(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "payments"

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
    invoice_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True),
        nullable=False,
        index=True,
    )
    resident_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True),
        nullable=False,
        index=True,
    )
    payment_number: Mapped[str] = mapped_column(
        sa.String(100), unique=True, index=True, nullable=False
    )
    amount: Mapped[Decimal] = mapped_column(
        sa.Numeric(10, 2), default=Decimal("0.00"), nullable=False
    )
    payment_method: Mapped[str] = mapped_column(
        sa.String(50), nullable=False  # UPI, CASH, BANK_TRANSFER, CARD, OTHER
    )
    transaction_reference: Mapped[Optional[str]] = mapped_column(
        sa.String(150), nullable=True
    )
    status: Mapped[str] = mapped_column(
        sa.String(50), default="COMPLETED", index=True, nullable=False
    )  # COMPLETED, PENDING, FAILED, REFUNDED
    recorded_by_user_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
    )
    payment_date: Mapped[date] = mapped_column(sa.Date, index=True, nullable=False)
    paid_at: Mapped[datetime] = mapped_column(
        sa.DateTime(timezone=True),
        server_default=sa.func.now(),
        nullable=False,
    )
    notes: Mapped[Optional[str]] = mapped_column(sa.String(255), nullable=True)

    # Relationships
    company: Mapped["Company"] = relationship("Company")
    property: Mapped["Property"] = relationship("Property", back_populates="payments", overlaps="payments,property")
    invoice: Mapped["Invoice"] = relationship(
        "Invoice",
        back_populates="payments",
        foreign_keys=[invoice_id, property_id],
        overlaps="payments,invoice,property,resident",
    )
    resident: Mapped["Resident"] = relationship(
        "Resident",
        back_populates="payments",
        foreign_keys=[resident_id, property_id],
        overlaps="payments,resident,property,invoice",
    )
    recorded_by: Mapped[Optional["User"]] = relationship("User", foreign_keys=[recorded_by_user_id])

    __table_args__ = (
        sa.ForeignKeyConstraint(
            ["invoice_id", "property_id"],
            ["invoices.id", "invoices.property_id"],
            name="fk_payments_invoice_id_property_id",
            ondelete="RESTRICT",
        ),
        sa.ForeignKeyConstraint(
            ["resident_id", "property_id"],
            ["residents.id", "residents.property_id"],
            name="fk_payments_resident_id_property_id",
            ondelete="RESTRICT",
        ),
        sa.Index(
            "uq_payment_transaction_ref",
            "transaction_reference",
            unique=True,
            postgresql_where=(sa.column("transaction_reference").is_not(None)) & (sa.column("transaction_reference") != ""),
            sqlite_where=(sa.column("transaction_reference").is_not(None)) & (sa.column("transaction_reference") != ""),
        ),
        sa.Index("ix_payments_property_status", "property_id", "status"),
    )
