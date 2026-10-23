import uuid
from datetime import date
from typing import List, Optional
import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDMixin


class Resident(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "residents"

    user_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("users.id", ondelete="CASCADE"),
        unique=True,
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
        sa.ForeignKey("rooms.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    bed_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("beds.id", ondelete="SET NULL"),
        unique=True,
        nullable=True,
        index=True,
    )

    emergency_contact_name: Mapped[Optional[str]] = mapped_column(sa.String(150), nullable=True)
    emergency_contact_phone: Mapped[Optional[str]] = mapped_column(sa.String(30), nullable=True)
    check_in_date: Mapped[date] = mapped_column(sa.Date, nullable=False)
    expected_check_out_date: Mapped[Optional[date]] = mapped_column(sa.Date, nullable=True)
    actual_check_out_date: Mapped[Optional[date]] = mapped_column(sa.Date, nullable=True)
    security_deposit: Mapped[float] = mapped_column(sa.Numeric(10, 2), default=0.00, nullable=False)
    monthly_rent: Mapped[float] = mapped_column(sa.Numeric(10, 2), default=0.00, nullable=False)

    # KYC
    kyc_status: Mapped[str] = mapped_column(
        sa.String(50), default="PENDING", nullable=False, index=True
    )  # PENDING, VERIFIED, REJECTED
    id_proof_type: Mapped[Optional[str]] = mapped_column(
        sa.String(50), nullable=True
    )  # AADHAAR, PAN, PASSPORT, DRIVING_LICENSE
    id_proof_number_masked: Mapped[Optional[str]] = mapped_column(sa.String(50), nullable=True)
    id_proof_document_path: Mapped[Optional[str]] = mapped_column(sa.String(512), nullable=True)

    status: Mapped[str] = mapped_column(
        sa.String(50), default="ACTIVE", nullable=False, index=True
    )  # ACTIVE, NOTICE_PERIOD, CHECKED_OUT

    # Relationships
    user: Mapped["User"] = relationship("User", back_populates="resident_profile")
    property: Mapped["Property"] = relationship("Property", back_populates="residents")
    room: Mapped[Optional["Room"]] = relationship("Room", back_populates="residents")
    bed: Mapped[Optional["Bed"]] = relationship("Bed", back_populates="resident")
    invoices: Mapped[List["Invoice"]] = relationship("Invoice", back_populates="resident")
    payments: Mapped[List["Payment"]] = relationship("Payment", back_populates="resident")
    complaints: Mapped[List["Complaint"]] = relationship("Complaint", back_populates="resident")
