import uuid
from typing import List, Optional
import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDMixin


class Company(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "companies"

    name: Mapped[str] = mapped_column(sa.String(150), nullable=False)
    code: Mapped[str] = mapped_column(sa.String(50), unique=True, index=True, nullable=False)
    email: Mapped[Optional[str]] = mapped_column(sa.String(255), nullable=True)
    phone: Mapped[Optional[str]] = mapped_column(sa.String(30), nullable=True)
    address: Mapped[Optional[str]] = mapped_column(sa.Text, nullable=True)
    tax_id: Mapped[Optional[str]] = mapped_column(sa.String(50), nullable=True)
    is_active: Mapped[bool] = mapped_column(sa.Boolean, default=True, nullable=False)

    # Relationships
    properties: Mapped[List["Property"]] = relationship(
        "Property", back_populates="company", cascade="all, delete-orphan"
    )
    users: Mapped[List["User"]] = relationship(
        "User", back_populates="company", cascade="all, delete-orphan"
    )
