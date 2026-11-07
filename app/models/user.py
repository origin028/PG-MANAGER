import uuid
from datetime import datetime
from typing import List, Optional
import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDMixin


class User(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "users"

    company_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("companies.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    role_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("roles.id", ondelete="RESTRICT"),
        nullable=False,
        index=True,
    )
    email: Mapped[Optional[str]] = mapped_column(
        sa.String(255), unique=True, index=True, nullable=True
    )
    phone: Mapped[str] = mapped_column(
        sa.String(30), unique=True, index=True, nullable=False
    )
    full_name: Mapped[str] = mapped_column(sa.String(150), nullable=False)
    password_hash: Mapped[str] = mapped_column(sa.String(255), nullable=False)
    is_active: Mapped[bool] = mapped_column(sa.Boolean, default=True, nullable=False)
    is_verified: Mapped[bool] = mapped_column(sa.Boolean, default=False, nullable=False)
    avatar_url: Mapped[Optional[str]] = mapped_column(sa.String(512), nullable=True)
    last_login_at: Mapped[Optional[datetime]] = mapped_column(
        sa.DateTime(timezone=True), nullable=True
    )

    # Relationships
    company: Mapped["Company"] = relationship("Company", back_populates="users")
    role: Mapped["Role"] = relationship("Role", back_populates="users")
    property_accesses: Mapped[List["UserPropertyAccess"]] = relationship(
        "UserPropertyAccess", back_populates="user", cascade="all, delete-orphan"
    )
    refresh_tokens: Mapped[List["RefreshToken"]] = relationship(
        "RefreshToken", back_populates="user", cascade="all, delete-orphan"
    )
    audit_logs: Mapped[List["AuditLog"]] = relationship(
        "AuditLog", back_populates="user"
    )


class UserPropertyAccess(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "user_property_access"
    __table_args__ = (
        sa.UniqueConstraint("user_id", "property_id", name="uq_user_property_access"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    property_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("properties.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    access_level: Mapped[str] = mapped_column(
        sa.String(50), default="MANAGER", nullable=False
    )  # MANAGER, STAFF, VIEWER

    # Relationships
    user: Mapped["User"] = relationship("User", back_populates="property_accesses")
    property: Mapped["Property"] = relationship("Property", back_populates="user_accesses")


class RefreshToken(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "refresh_tokens"

    user_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    token_hash: Mapped[str] = mapped_column(sa.String(255), index=True, nullable=False)
    client_type: Mapped[str] = mapped_column(
        sa.String(50), default="admin_web", nullable=False
    )  # admin_web, admin_mobile, resident_mobile
    device_info: Mapped[Optional[str]] = mapped_column(sa.String(255), nullable=True)
    expires_at: Mapped[datetime] = mapped_column(sa.DateTime(timezone=True), nullable=False)
    is_revoked: Mapped[bool] = mapped_column(sa.Boolean, default=False, nullable=False)

    # Relationships
    user: Mapped["User"] = relationship("User", back_populates="refresh_tokens")
