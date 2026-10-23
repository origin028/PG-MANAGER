import uuid
from datetime import datetime
from typing import Optional
from pydantic import BaseModel, ConfigDict


class ComplaintBase(BaseModel):
    category: str = "OTHER"
    title: str
    description: str
    priority: str = "MEDIUM"


class ComplaintCreate(ComplaintBase):
    property_id: uuid.UUID


class ComplaintUpdate(BaseModel):
    assigned_staff_id: Optional[uuid.UUID] = None
    status: Optional[str] = None
    resolution_notes: Optional[str] = None


class ComplaintRead(ComplaintBase):
    id: uuid.UUID
    property_id: uuid.UUID
    resident_id: uuid.UUID
    assigned_staff_id: Optional[uuid.UUID] = None
    status: str
    resolution_notes: Optional[str] = None
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)
