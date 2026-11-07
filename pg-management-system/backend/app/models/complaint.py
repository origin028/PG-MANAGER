import uuid
from typing import Optional
import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDMixin


class Complaint(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "complaints"

    property_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("properties.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    resident_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("residents.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    assigned_staff_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("staff.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )

    category: Mapped[str] = mapped_column(
        sa.String(50), default="OTHER", nullable=False
    )  # ELECTRICAL, PLUMBING, CLEANING, WIFI, FOOD, CARPENTRY, OTHER
    title: Mapped[str] = mapped_column(sa.String(200), nullable=False)
    description: Mapped[str] = mapped_column(sa.Text, nullable=False)
    priority: Mapped[str] = mapped_column(
        sa.String(30), default="MEDIUM", nullable=False
    )  # LOW, MEDIUM, HIGH, EMERGENCY
    status: Mapped[str] = mapped_column(
        sa.String(50), default="PENDING", nullable=False, index=True
    )  # PENDING, ASSIGNED, IN_PROGRESS, RESOLVED, CLOSED
    resolution_notes: Mapped[Optional[str]] = mapped_column(sa.Text, nullable=True)
    photo_path: Mapped[Optional[str]] = mapped_column(sa.String(512), nullable=True)

    # Relationships
    property: Mapped["Property"] = relationship("Property", back_populates="complaints")
    resident: Mapped["Resident"] = relationship("Resident", back_populates="complaints")
    assigned_staff: Mapped[Optional["Staff"]] = relationship("Staff", back_populates="assigned_complaints")
