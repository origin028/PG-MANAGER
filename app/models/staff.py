import uuid
from decimal import Decimal
from typing import Optional
import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDMixin


class Staff(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "staff"

    company_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("companies.id", ondelete="RESTRICT"),
        nullable=False,
        index=True,
    )
    property_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("properties.id", ondelete="RESTRICT"),
        nullable=True,
        index=True,
    )
    user_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    name: Mapped[str] = mapped_column(sa.String(150), nullable=False)
    role: Mapped[str] = mapped_column(sa.String(100), nullable=False)
    phone: Mapped[str] = mapped_column(sa.String(30), nullable=False)
    salary: Mapped[Decimal] = mapped_column(sa.Numeric(10, 2), nullable=False)
    is_active: Mapped[bool] = mapped_column(sa.Boolean, default=True, nullable=False)

    company: Mapped["Company"] = relationship("Company")
    property: Mapped[Optional["Property"]] = relationship("Property")
    user: Mapped[Optional["User"]] = relationship("User")
