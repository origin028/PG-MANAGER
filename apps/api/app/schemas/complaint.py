import uuid
from datetime import datetime
from typing import Any, Optional
from pydantic import BaseModel, ConfigDict, Field, model_validator


class ComplaintBase(BaseModel):
    category: str = Field(default="OTHER", description="ELECTRICAL, PLUMBING, CLEANING, WIFI, FOOD, CARPENTRY, OTHER")
    title: str = Field(..., max_length=200)
    description: str
    priority: str = Field(default="MEDIUM", description="LOW, MEDIUM, HIGH, EMERGENCY")


class ComplaintCreate(ComplaintBase):
    property_id: uuid.UUID


class ComplaintUpdate(BaseModel):
    category: Optional[str] = None
    title: Optional[str] = None
    description: Optional[str] = None
    priority: Optional[str] = None
    assigned_staff_id: Optional[uuid.UUID] = None
    status: Optional[str] = None
    resolution_notes: Optional[str] = None


class ComplaintAssignRequest(BaseModel):
    assigned_staff_id: uuid.UUID = Field(..., description="UUID of the staff member to assign")

    @model_validator(mode="before")
    @classmethod
    def preprocess_assign(cls, values: Any) -> Any:
        if isinstance(values, dict):
            if "assigned_staff_id" not in values and "staff_id" in values:
                values["assigned_staff_id"] = values["staff_id"]
        return values


class ComplaintResolveRequest(BaseModel):
    resolution_notes: str = Field(..., min_length=3, max_length=1000, description="Notes detailing how complaint was resolved")
    status: str = Field(default="RESOLVED", description="Target status: RESOLVED or CLOSED")


class ComplaintRead(ComplaintBase):
    id: uuid.UUID
    property_id: uuid.UUID
    resident_id: uuid.UUID
    assigned_staff_id: Optional[uuid.UUID] = None
    status: str
    resolution_notes: Optional[str] = None
    photo_path: Optional[str] = None
    resolved_at: Optional[datetime] = None
    created_at: datetime
    updated_at: datetime
    # Enriched fields
    assigned_staff_name: Optional[str] = None
    resident_name: Optional[str] = None
    resident_phone: Optional[str] = None
    property_name: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)
