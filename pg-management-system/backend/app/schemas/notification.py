import uuid
from datetime import datetime
from typing import Optional
from pydantic import BaseModel, ConfigDict, Field


class DeviceTokenRegisterRequest(BaseModel):
    device_token: str = Field(min_length=1, max_length=255, description="Push notification device token (Pushy / native)")
    platform: str = Field(default="android", min_length=1, max_length=50)
    device_name: Optional[str] = Field(default=None, max_length=100)


class DeviceTokenRead(BaseModel):
    id: uuid.UUID
    device_token: str
    platform: str
    device_name: Optional[str] = None
    is_active: bool
    last_seen_at: Optional[datetime] = None

    model_config = ConfigDict(from_attributes=True)


class NotificationRead(BaseModel):
    id: uuid.UUID
    title: str
    body: str
    channel: str
    status: str
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)
