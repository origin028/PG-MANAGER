from typing import List, Optional
import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDMixin


class Role(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "roles"

    name: Mapped[str] = mapped_column(sa.String(50), unique=True, index=True, nullable=False)
    display_name: Mapped[str] = mapped_column(sa.String(100), nullable=False)
    description: Mapped[Optional[str]] = mapped_column(sa.String(255), nullable=True)
    is_system_role: Mapped[bool] = mapped_column(sa.Boolean, default=False, nullable=False)
    permissions: Mapped[List[str]] = mapped_column(sa.JSON, default=list, nullable=False)

    # Relationships
    users: Mapped[List["User"]] = relationship("User", back_populates="role")
