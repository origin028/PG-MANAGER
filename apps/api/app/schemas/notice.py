import uuid
from datetime import datetime
from typing import Optional
from pydantic import BaseModel, ConfigDict, Field


class NoticeBase(BaseModel):
    title: str = Field(..., max_length=200)
    content: str
    is_pinned: bool = False
    expires_at: Optional[datetime] = None


class NoticeCreate(NoticeBase):
    property_id: uuid.UUID


class NoticeUpdate(BaseModel):
    title: Optional[str] = None
    content: Optional[str] = None
    is_pinned: Optional[bool] = None
    expires_at: Optional[datetime] = None


class NoticeRead(NoticeBase):
    id: uuid.UUID
    property_id: uuid.UUID
    created_by_user_id: uuid.UUID
    created_at: datetime
    updated_at: datetime
    property_name: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)
