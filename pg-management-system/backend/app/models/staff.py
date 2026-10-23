import uuid
from datetime import date
from typing import List, Optional
import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDMixin


class Staff(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "staff"

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
    designation: Mapped[str] = mapped_column(
        sa.String(100), default="WARDEN", nullable=False
    )  # WARDEN, CARETAKER, ACCOUNTANT, CHEF, SECURITY
    salary: Mapped[float] = mapped_column(sa.Numeric(10, 2), default=0.00, nullable=False)
    joining_date: Mapped[date] = mapped_column(sa.Date, nullable=False)
    status: Mapped[str] = mapped_column(
        sa.String(50), default="ACTIVE", nullable=False
    )  # ACTIVE, INACTIVE, RESIGNED

    # Relationships
    user: Mapped["User"] = relationship("User", back_populates="staff_profile")
    property: Mapped["Property"] = relationship("Property", back_populates="staff_members")
    assigned_complaints: Mapped[List["Complaint"]] = relationship("Complaint", back_populates="assigned_staff")
