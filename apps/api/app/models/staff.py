import builtins
import uuid
from datetime import date
from typing import List, Optional
import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDMixin


class Staff(Base, UUIDMixin, TimestampMixin):
    __tablename__ = "staff"

    company_id: Mapped[uuid.UUID] = mapped_column(
        sa.Uuid(as_uuid=True),
        sa.ForeignKey("companies.id", ondelete="CASCADE"),
        nullable=False,
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
        unique=True,
        nullable=True,
        index=True,
    )
    name: Mapped[str] = mapped_column(sa.String(150), nullable=False)
    role: Mapped[str] = mapped_column(sa.String(100), default="PROPERTY_MANAGER", nullable=False)
    phone: Mapped[str] = mapped_column(sa.String(30), nullable=False)
    email: Mapped[Optional[str]] = mapped_column(sa.String(255), nullable=True)
    salary: Mapped[float] = mapped_column(sa.Numeric(10, 2), default=0.00, nullable=False)
    joining_date: Mapped[Optional[date]] = mapped_column(sa.Date, nullable=True)
    is_active: Mapped[bool] = mapped_column(sa.Boolean, default=True, nullable=False)
    availability_hours: Mapped[Optional[str]] = mapped_column(
        sa.String(100), default="9:00 AM - 6:00 PM", nullable=True
    )
    is_emergency_contact: Mapped[bool] = mapped_column(sa.Boolean, default=False, nullable=False)

    # Backward compatibility properties
    @builtins.property
    def designation(self) -> str:
        return self.role

    @builtins.property
    def status(self) -> str:
        return "ACTIVE" if self.is_active else "INACTIVE"

    @builtins.property
    def monthly_salary(self) -> float:
        return float(self.salary or 0.0)

    @monthly_salary.setter
    def monthly_salary(self, value: float) -> None:
        self.salary = value

    # Relationships
    company: Mapped["Company"] = relationship("Company")
    property: Mapped[Optional["Property"]] = relationship("Property", back_populates="staff_members")
    user: Mapped[Optional["User"]] = relationship("User", back_populates="staff_profile")
    assigned_complaints: Mapped[List["Complaint"]] = relationship("Complaint", back_populates="assigned_staff")


@sa.event.listens_for(Staff, "before_insert")
def auto_populate_staff_company_id(mapper, connection, target):
    if not target.company_id:
        if target.property_id:
            from app.models.property import Property
            prop_company_id = connection.execute(
                sa.select(Property.company_id).where(Property.id == target.property_id)
            ).scalar()
            if prop_company_id:
                target.company_id = prop_company_id
                return
        from app.models.property import Company
        first_company_id = connection.execute(sa.select(Company.id)).scalar()
        if first_company_id:
            target.company_id = first_company_id

