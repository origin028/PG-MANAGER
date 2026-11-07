import uuid
from datetime import datetime
from typing import Any, Dict, Optional
import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, UUIDMixin


class AuditLog(Base, UUIDMixin):
    __tablename__ = "audit_logs"

    company_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("companies.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    property_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("properties.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    user_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    user_email: Mapped[Optional[str]] = mapped_column(sa.String(255), nullable=True)
    user_role: Mapped[Optional[str]] = mapped_column(sa.String(50), nullable=True)
    action: Mapped[str] = mapped_column(sa.String(100), index=True, nullable=False)
    resource_type: Mapped[str] = mapped_column(sa.String(100), index=True, nullable=False)
    resource_id: Mapped[Optional[str]] = mapped_column(sa.String(100), nullable=True)
    details: Mapped[Dict[str, Any]] = mapped_column(
        sa.JSON, default=dict, nullable=False
    )
    ip_address: Mapped[Optional[str]] = mapped_column(sa.String(50), nullable=True)
    user_agent: Mapped[Optional[str]] = mapped_column(sa.String(255), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        sa.DateTime(timezone=True),
        server_default=sa.func.now(),
        index=True,
        nullable=False,
    )

    # Relationships
    user: Mapped[Optional["User"]] = relationship("User", back_populates="audit_logs")
