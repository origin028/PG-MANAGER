import uuid
from datetime import date, datetime
from typing import List, Optional
import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDMixin


class Resident(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "residents"

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
    room_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        sa.Uuid(as_uuid=True),
        nullable=True,
        index=True,
    )
    bed_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        sa.Uuid(as_uuid=True),
        nullable=True,
        index=True,
    )
    user_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    full_name: Mapped[str] = mapped_column(sa.String(150), nullable=False)
    email: Mapped[Optional[str]] = mapped_column(sa.String(255), nullable=True, index=True)
    phone: Mapped[str] = mapped_column(sa.String(30), nullable=False, index=True)
    emergency_contact_name: Mapped[Optional[str]] = mapped_column(sa.String(150), nullable=True)
    emergency_contact_phone: Mapped[Optional[str]] = mapped_column(sa.String(30), nullable=True)
    check_in_date: Mapped[Optional[date]] = mapped_column(sa.Date, nullable=True)
    expected_check_out_date: Mapped[Optional[date]] = mapped_column(sa.Date, nullable=True)
    actual_check_out_date: Mapped[Optional[date]] = mapped_column(sa.Date, nullable=True)
    monthly_rent: Mapped[float] = mapped_column(
        sa.Numeric(10, 2), default=0.00, nullable=False
    )
    security_deposit: Mapped[float] = mapped_column(
        sa.Numeric(10, 2), default=0.00, nullable=False
    )
    status: Mapped[str] = mapped_column(
        sa.String(50), default="PENDING", nullable=False, index=True
    )  # PENDING, ACTIVE, CHECKED_OUT, CANCELLED
    kyc_status: Mapped[str] = mapped_column(
        sa.String(50), default="PENDING", nullable=False, index=True
    )  # PENDING, VERIFIED, REJECTED
    id_proof_type: Mapped[Optional[str]] = mapped_column(sa.String(50), nullable=True)
    id_proof_number_masked: Mapped[Optional[str]] = mapped_column(sa.String(50), nullable=True)
    kyc_notes: Mapped[Optional[str]] = mapped_column(sa.String(255), nullable=True)
    verified_at: Mapped[Optional[datetime]] = mapped_column(sa.DateTime(timezone=True), nullable=True)
    verified_by_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
    )

    # Relationships
    company: Mapped["Company"] = relationship("Company")
    property: Mapped["Property"] = relationship(
        "Property", back_populates="residents", overlaps="residents,property,room,bed"
    )
    room: Mapped[Optional["Room"]] = relationship(
        "Room",
        back_populates="residents",
        foreign_keys=[room_id, property_id],
        overlaps="residents,property,room,bed",
    )
    bed: Mapped[Optional["Bed"]] = relationship(
        "Bed",
        back_populates="residents",
        foreign_keys=[bed_id, property_id],
        overlaps="residents,property,room,bed",
    )
    user: Mapped[Optional["User"]] = relationship("User", foreign_keys=[user_id])
    verified_by: Mapped[Optional["User"]] = relationship("User", foreign_keys=[verified_by_id])
    invoices: Mapped[List["Invoice"]] = relationship(
        "Invoice", back_populates="resident", foreign_keys="[Invoice.resident_id, Invoice.property_id]", overlaps="invoices,resident"
    )
    payments: Mapped[List["Payment"]] = relationship(
        "Payment", back_populates="resident", foreign_keys="[Payment.resident_id, Payment.property_id]", overlaps="payments,resident"
    )

    __table_args__ = (
        sa.UniqueConstraint("id", "property_id", name="uq_residents_id_property_id"),
        sa.ForeignKeyConstraint(
            ["room_id", "property_id"],
            ["rooms.id", "rooms.property_id"],
            name="fk_residents_room_id_property_id",
            ondelete="RESTRICT",
        ),
        sa.ForeignKeyConstraint(
            ["bed_id", "property_id"],
            ["beds.id", "beds.property_id"],
            name="fk_residents_bed_id_property_id",
            ondelete="RESTRICT",
        ),
        sa.Index(
            "uq_active_resident_bed",
            "bed_id",
            unique=True,
            postgresql_where=(sa.column("status") == "ACTIVE") & (sa.column("bed_id").is_not(None)),
            sqlite_where=(sa.column("status") == "ACTIVE") & (sa.column("bed_id").is_not(None)),
        ),
        sa.Index("ix_residents_property_status", "property_id", "status"),
    )
