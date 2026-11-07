import uuid
from datetime import date, datetime
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
    # Frontend Single Emergency Contact Format
    emergency_contact: Mapped[Optional[str]] = mapped_column(sa.String(150), nullable=True)

    # Personal Information
    date_of_birth: Mapped[Optional[date]] = mapped_column(sa.Date, nullable=True)
    gender: Mapped[Optional[str]] = mapped_column(sa.String(20), nullable=True)
    occupation: Mapped[Optional[str]] = mapped_column(sa.String(100), nullable=True)

    # Permanent Address
    house_flat_no: Mapped[Optional[str]] = mapped_column(sa.String(100), nullable=True)
    street: Mapped[Optional[str]] = mapped_column(sa.String(150), nullable=True)
    landmark: Mapped[Optional[str]] = mapped_column(sa.String(150), nullable=True)
    city: Mapped[Optional[str]] = mapped_column(sa.String(100), nullable=True)
    state: Mapped[Optional[str]] = mapped_column(sa.String(100), nullable=True)
    pincode: Mapped[Optional[str]] = mapped_column(sa.String(20), nullable=True)

    # KYC & Identity Verification Files
    verification_method: Mapped[Optional[str]] = mapped_column(sa.String(50), nullable=True)
    aadhaar_front_path: Mapped[Optional[str]] = mapped_column(sa.String(512), nullable=True)
    aadhaar_back_path: Mapped[Optional[str]] = mapped_column(sa.String(512), nullable=True)
    pan_card_path: Mapped[Optional[str]] = mapped_column(sa.String(512), nullable=True)
    passport_path: Mapped[Optional[str]] = mapped_column(sa.String(512), nullable=True)
    resident_selfie_path: Mapped[Optional[str]] = mapped_column(sa.String(512), nullable=True)
    kyc_documents: Mapped[Optional[dict]] = mapped_column(sa.JSON, nullable=True)

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

    @property
    def full_name(self) -> Optional[str]:
        return self.user.full_name if self.user else getattr(self, "_full_name_val", None)

    @full_name.setter
    def full_name(self, value: Optional[str]) -> None:
        self._full_name_val = value
        if getattr(self, "user", None):
            self.user.full_name = value

    @property
    def phone(self) -> Optional[str]:
        return self.user.phone if self.user else getattr(self, "_phone_val", None)

    @phone.setter
    def phone(self, value: Optional[str]) -> None:
        self._phone_val = value
        if getattr(self, "user", None):
            self.user.phone = value

    @property
    def email(self) -> Optional[str]:
        return self.user.email if self.user else getattr(self, "_email_val", None)

    @email.setter
    def email(self, value: Optional[str]) -> None:
        self._email_val = value
        if getattr(self, "user", None):
            self.user.email = value

    @property
    def verified_at(self) -> Optional[datetime]:
        return getattr(self, "_verified_at_val", None)

    @verified_at.setter
    def verified_at(self, value: Optional[datetime]) -> None:
        self._verified_at_val = value

    @property
    def verified_by_id(self) -> Optional[uuid.UUID]:
        return getattr(self, "_verified_by_id_val", None)

    @verified_by_id.setter
    def verified_by_id(self, value: Optional[uuid.UUID]) -> None:
        self._verified_by_id_val = value

    @property
    def kyc_notes(self) -> Optional[str]:
        if getattr(self, "_kyc_notes_val", None) is not None:
            return self._kyc_notes_val
        if self.kyc_documents and isinstance(self.kyc_documents, dict):
            return self.kyc_documents.get("rejection_reason") or self.kyc_documents.get("notes")
        return None

    @kyc_notes.setter
    def kyc_notes(self, value: Optional[str]) -> None:
        self._kyc_notes_val = value
        if self.kyc_documents is None:
            self.kyc_documents = {}
        if isinstance(self.kyc_documents, dict):
            self.kyc_documents["rejection_reason"] = value
            self.kyc_documents["notes"] = value

    # Relationships
    user: Mapped["User"] = relationship("User", back_populates="resident_profile")
    property: Mapped["Property"] = relationship("Property", back_populates="residents")
    room: Mapped[Optional["Room"]] = relationship("Room", back_populates="residents")
    bed: Mapped[Optional["Bed"]] = relationship("Bed", back_populates="resident")
    invoices: Mapped[List["Invoice"]] = relationship("Invoice", back_populates="resident")
    payments: Mapped[List["Payment"]] = relationship("Payment", back_populates="resident")
    complaints: Mapped[List["Complaint"]] = relationship("Complaint", back_populates="resident")
