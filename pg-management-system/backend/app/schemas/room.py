import uuid
from datetime import datetime
from typing import Any, Dict, Optional
from pydantic import BaseModel, ConfigDict


class RoomBase(BaseModel):
    floor_number: int = 1
    room_number: str
    room_type: str = "DOUBLE_SHARING"
    max_occupancy: int = 2
    base_rent: float = 0.00
    is_active: bool = True
    amenities: Dict[str, Any] = {}


class RoomCreate(RoomBase):
    property_id: uuid.UUID


class RoomRead(RoomBase):
    id: uuid.UUID
    property_id: uuid.UUID
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class RoomSummary(BaseModel):
    id: uuid.UUID
    room_number: str
    floor_number: int
    room_type: str
    max_occupancy: int
    base_rent: float
    is_active: bool

    model_config = ConfigDict(from_attributes=True)
