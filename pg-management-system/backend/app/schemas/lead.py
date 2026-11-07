import uuid
from datetime import datetime
from typing import Optional
from pydantic import BaseModel, ConfigDict, Field


class LeadBase(BaseModel):
    name: str = Field(..., max_length=150)
    phone: str = Field(..., max_length=30)
    email: Optional[str] = Field(None, max_length=255)
    source: Optional[str] = Field(None, max_length=100, description="WEBSITE, REFERRAL, WALK_IN, SOCIAL_MEDIA, JUSTDIAL")
    requirement: Optional[str] = Field(None, description="e.g. Single room, AC, 2 sharing")
    visit_date: Optional[datetime] = None
    follow_up_date: Optional[datetime] = None
    notes: Optional[str] = None


class LeadCreate(LeadBase):
    property_id: uuid.UUID


class LeadUpdate(BaseModel):
    name: Optional[str] = None
    phone: Optional[str] = None
    email: Optional[str] = None
    status: Optional[str] = Field(None, description="NEW, CONTACTED, VISIT_SCHEDULED, BOOKED, LOST")
    source: Optional[str] = None
    requirement: Optional[str] = None
    visit_date: Optional[datetime] = None
    follow_up_date: Optional[datetime] = None
    notes: Optional[str] = None
    property_id: Optional[uuid.UUID] = None


class LeadRead(LeadBase):
    id: uuid.UUID
    property_id: uuid.UUID
    status: str
    created_at: datetime
    updated_at: datetime
    property_name: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)


class LeadConvertRequest(BaseModel):
    room_id: Optional[uuid.UUID] = None
    bed_id: Optional[uuid.UUID] = None
    monthly_rent: Optional[float] = 6000.0
    security_deposit: Optional[float] = 6000.0
    check_in_date: Optional[datetime] = None
    notes: Optional[str] = None


class LeadConvertResponse(BaseModel):
    lead_id: uuid.UUID
    resident_id: uuid.UUID
    user_id: uuid.UUID
    status: str
    message: str
