import uuid
from datetime import datetime
from typing import Any, Dict, List, Optional
from pydantic import BaseModel, ConfigDict, Field, model_validator


class RoomBase(BaseModel):
    floor_number: int = 1
    room_number: str = Field(..., min_length=1, max_length=50)
    room_type: str = "DOUBLE_SHARING"
    base_monthly_rent: float = 0.00
    deposit_amount: float = 0.00
    is_active: bool = True
    amenities: Dict[str, Any] = {}
    auto_create_beds: bool = False
    bed_count: Optional[int] = None


class RoomCreate(BaseModel):
    property_id: uuid.UUID
    floor_number: int = 1
    floor: Optional[int] = None
    room_number: str = Field(..., min_length=1, max_length=50)
    room_type: str = "DOUBLE_SHARING"
    base_monthly_rent: Optional[float] = 0.00
    base_rent: Optional[float] = None
    deposit_amount: Optional[float] = 0.00
    is_active: bool = True
    amenities: Dict[str, Any] = {}
    auto_create_beds: bool = False
    bed_count: Optional[int] = None

    @model_validator(mode="after")
    def sync_floor_fields(self) -> "RoomCreate":
        if self.floor is not None and self.floor_number == 1:
            self.floor_number = self.floor
        if self.base_rent is not None and (self.base_monthly_rent == 0.00 or self.base_monthly_rent is None):
            self.base_monthly_rent = self.base_rent
        return self


class RoomUpdate(BaseModel):
    floor_number: Optional[int] = None
    floor: Optional[int] = None
    room_number: Optional[str] = None
    room_type: Optional[str] = None
    base_monthly_rent: Optional[float] = None
    base_rent: Optional[float] = None
    deposit_amount: Optional[float] = None
    is_active: Optional[bool] = None
    amenities: Optional[Dict[str, Any]] = None
    auto_create_beds: Optional[bool] = None
    add_beds: Optional[int] = None

    @model_validator(mode="after")
    def sync_floor_fields(self) -> "RoomUpdate":
        if self.floor is not None and self.floor_number is None:
            self.floor_number = self.floor
        if self.base_rent is not None and self.base_monthly_rent is None:
            self.base_monthly_rent = self.base_rent
        return self


class BedInfoInRoom(BaseModel):
    id: uuid.UUID
    bed_number: str
    status: str
    monthly_rent: Optional[float] = None
    is_active: bool = True
    resident_name: Optional[str] = None
    resident_id: Optional[uuid.UUID] = None

    model_config = ConfigDict(from_attributes=True)


class RoomRead(BaseModel):
    id: uuid.UUID
    property_id: uuid.UUID
    room_number: str
    floor_number: int
    room_type: str
    base_monthly_rent: float
    base_rent: float
    deposit_amount: float
    max_occupancy: int
    is_active: bool
    amenities: Dict[str, Any]
    beds: List[BedInfoInRoom] = []
    total_beds: int = 0
    occupied_beds: int = 0
    available_beds: int = 0
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class RoomSummary(BaseModel):
    id: uuid.UUID
    property_id: uuid.UUID
    room_number: str
    floor_number: int
    room_type: str
    base_rent: float
    deposit_amount: float
    total_beds: int = 0
    occupied_beds: int = 0
    available_beds: int = 0
    is_active: bool

    model_config = ConfigDict(from_attributes=True)


class FloorWiseRoomsGroup(BaseModel):
    floor_number: int
    rooms: List[RoomSummary]
    total_rooms: int = 0
    total_beds: int = 0
    occupied_beds: int = 0
    available_beds: int = 0


class FloorWiseRoomsResponse(BaseModel):
    property_id: uuid.UUID
    property_name: str
    floors: List[FloorWiseRoomsGroup]
