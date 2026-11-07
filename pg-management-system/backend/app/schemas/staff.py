import uuid
from datetime import date, datetime
from decimal import Decimal
from typing import Optional
from pydantic import BaseModel, ConfigDict, Field


class StaffBase(BaseModel):
    name: str = Field(..., max_length=150)
    role: str = Field(default="PROPERTY_MANAGER", description="PROPERTY_MANAGER, WARDEN, CLEANING, COOK, SECURITY, MAINTENANCE")
    phone: str = Field(..., max_length=30)
    email: Optional[str] = Field(None, max_length=255)
    salary: Decimal = Field(default=Decimal("0.00"), ge=0, max_digits=10, decimal_places=2)
    joining_date: Optional[date] = None
    availability_hours: Optional[str] = Field(default="9:00 AM - 6:00 PM", max_length=100)
    is_emergency_contact: bool = False


class StaffCreate(StaffBase):
    property_id: Optional[uuid.UUID] = None


class StaffUpdate(BaseModel):
    name: Optional[str] = None
    role: Optional[str] = None
    phone: Optional[str] = None
    email: Optional[str] = None
    salary: Optional[Decimal] = Field(None, ge=0, max_digits=10, decimal_places=2)
    joining_date: Optional[date] = None
    availability_hours: Optional[str] = None
    is_emergency_contact: Optional[bool] = None
    is_active: Optional[bool] = None
    property_id: Optional[uuid.UUID] = None


class StaffRead(BaseModel):
    id: uuid.UUID
    property_id: Optional[uuid.UUID] = None
    company_id: uuid.UUID
    user_id: Optional[uuid.UUID] = None
    name: str
    role: str
    phone: str
    email: Optional[str] = None
    salary: float
    joining_date: Optional[date] = None
    is_active: bool
    availability_hours: Optional[str] = None
    is_emergency_contact: bool
    created_at: datetime
    property_name: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)
