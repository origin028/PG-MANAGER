import uuid
from datetime import datetime
from typing import List, Optional
from pydantic import BaseModel, ConfigDict, Field

from app.schemas.bed import BedRead


class RoomBase(BaseModel):
    room_number: str = Field(..., min_length=1, max_length=50, description="Room number, e.g. 101, 204B")
    floor_number: int = Field(default=1, ge=0, le=100, description="Floor level")
    room_type: str = Field(
        default="DOUBLE",
        pattern="^(SINGLE|DOUBLE|TRIPLE|FOUR_SHARING|DORMITORY|OTHER)$",
        description="Room accommodation sharing type",
    )
    base_monthly_rent: float = Field(default=0.0, ge=0, description="Default base monthly rent")
    deposit_amount: float = Field(default=0.0, ge=0, description="Security deposit amount")
    amenities: List[str] = Field(default_factory=list, description="List of amenities")
    is_active: bool = True


class RoomCreate(RoomBase):
    pass


class RoomUpdate(BaseModel):
    room_number: Optional[str] = Field(None, min_length=1, max_length=50)
    floor_number: Optional[int] = Field(None, ge=0, le=100)
    room_type: Optional[str] = Field(None, pattern="^(SINGLE|DOUBLE|TRIPLE|FOUR_SHARING|DORMITORY|OTHER)$")
    base_monthly_rent: Optional[float] = Field(None, ge=0)
    deposit_amount: Optional[float] = Field(None, ge=0)
    amenities: Optional[List[str]] = None
    is_active: Optional[bool] = None


class RoomRead(RoomBase):
    id: uuid.UUID
    property_id: uuid.UUID
    total_beds: int = 0
    available_beds: int = 0
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class RoomDetail(RoomRead):
    beds: List[BedRead] = Field(default_factory=list)
