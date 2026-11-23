import uuid
from datetime import datetime
from typing import Optional
from pydantic import BaseModel, ConfigDict, Field


class BedBase(BaseModel):
    bed_number: str = Field(..., min_length=1, max_length=50)
    status: str = "AVAILABLE"  # AVAILABLE, OCCUPIED, MAINTENANCE
    monthly_rent: Optional[float] = 0.00
    is_active: bool = True


class BedCreate(BaseModel):
    property_id: Optional[uuid.UUID] = None
    room_id: uuid.UUID
    bed_number: str = Field(..., min_length=1, max_length=50)
    status: str = "AVAILABLE"
    monthly_rent: Optional[float] = 0.00
    is_active: bool = True


class BedBulkCreate(BaseModel):
    room_id: uuid.UUID
    bed_numbers: list[str] = Field(..., min_length=1)
    status: str = "AVAILABLE"
    monthly_rent: Optional[float] = 0.00
    is_active: bool = True


class BedUpdate(BaseModel):
    bed_number: Optional[str] = None
    status: Optional[str] = None
    monthly_rent: Optional[float] = None
    is_active: Optional[bool] = None


class BedRead(BaseModel):
    id: uuid.UUID
    property_id: uuid.UUID
    room_id: uuid.UUID
    room_number: Optional[str] = None
    bed_number: str
    status: str
    monthly_rent: Optional[float] = None
    is_active: bool
    current_resident_id: Optional[uuid.UUID] = None
    current_resident_name: Optional[str] = None
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class BedSummary(BaseModel):
    id: uuid.UUID
    property_id: uuid.UUID
    room_id: uuid.UUID
    room_number: Optional[str] = None
    bed_number: str
    status: str
    monthly_rent: Optional[float] = None
    is_active: bool

    model_config = ConfigDict(from_attributes=True)
