import uuid
from typing import Any, Dict, List, Optional
import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDMixin


class Property(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "properties"

    company_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("companies.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    name: Mapped[str] = mapped_column(sa.String(150), nullable=False)
    code: Mapped[str] = mapped_column(sa.String(50), unique=True, index=True, nullable=False)
    property_type: Mapped[str] = mapped_column(
        sa.String(50), default="CO_LIVING", nullable=False
    )  # MENS_PG, LADIES_PG, CO_LIVING
    address_line1: Mapped[str] = mapped_column(sa.String(255), nullable=False)
    address_line2: Mapped[Optional[str]] = mapped_column(sa.String(255), nullable=True)
    city: Mapped[str] = mapped_column(sa.String(100), default="Bangalore", nullable=False)
    state: Mapped[str] = mapped_column(sa.String(100), default="Karnataka", nullable=False)
    pincode: Mapped[str] = mapped_column(sa.String(20), nullable=False)
    contact_phone: Mapped[Optional[str]] = mapped_column(sa.String(30), nullable=True)
    contact_email: Mapped[Optional[str]] = mapped_column(sa.String(255), nullable=True)
    total_floors: Mapped[int] = mapped_column(sa.Integer, default=4, nullable=False)
    is_active: Mapped[bool] = mapped_column(sa.Boolean, default=True, nullable=False)
    settings: Mapped[Dict[str, Any]] = mapped_column(
        sa.JSON, default=dict, nullable=False
    )

    # Relationships
    company: Mapped["Company"] = relationship("Company", back_populates="properties")
    user_accesses: Mapped[List["UserPropertyAccess"]] = relationship(
        "UserPropertyAccess", back_populates="property", cascade="all, delete-orphan"
    )
