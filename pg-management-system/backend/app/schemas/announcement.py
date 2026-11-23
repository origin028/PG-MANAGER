import uuid
from datetime import datetime
from typing import Optional
from pydantic import BaseModel, ConfigDict, Field


class AnnouncementBase(BaseModel):
    title: str = Field(..., min_length=1, max_length=255)
    content: str = Field(..., min_length=1)
    property_id: Optional[uuid.UUID] = None
    is_active: bool = True


class AnnouncementCreate(AnnouncementBase):
    pass


class AnnouncementUpdate(BaseModel):
    title: Optional[str] = Field(None, min_length=1, max_length=255)
    content: Optional[str] = Field(None, min_length=1)
    property_id: Optional[uuid.UUID] = None
    is_active: Optional[bool] = None


class AnnouncementStatusUpdate(BaseModel):
    is_active: bool


class AnnouncementRead(BaseModel):
    id: uuid.UUID
    company_id: uuid.UUID
    property_id: Optional[uuid.UUID] = None
    property_name: Optional[str] = None
    created_by_user_id: uuid.UUID
    created_by_name: Optional[str] = None
    title: str
    content: str
    is_active: bool
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)
