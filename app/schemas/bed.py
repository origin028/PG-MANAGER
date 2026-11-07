import uuid
from datetime import datetime
from typing import Optional
from pydantic import BaseModel, ConfigDict, Field


class BedBase(BaseModel):
    bed_number: str = Field(..., min_length=1, max_length=50, description="Bed label, e.g. A, B, 1, 2")
    monthly_rent: float = Field(..., ge=0, description="Monthly rent for this specific bed")
    status: str = Field(
        default="AVAILABLE",
        pattern="^(AVAILABLE|OCCUPIED|RESERVED|MAINTENANCE)$",
        description="Bed occupancy status",
    )
    is_active: bool = True


class BedCreate(BedBase):
    pass


class BedUpdate(BaseModel):
    bed_number: Optional[str] = Field(None, min_length=1, max_length=50)
    monthly_rent: Optional[float] = Field(None, ge=0)
    status: Optional[str] = Field(None, pattern="^(AVAILABLE|OCCUPIED|RESERVED|MAINTENANCE)$")
    is_active: Optional[bool] = None


class BedStatusUpdate(BaseModel):
    status: str = Field(..., pattern="^(AVAILABLE|OCCUPIED|RESERVED|MAINTENANCE)$")


class BedRead(BedBase):
    id: uuid.UUID
    property_id: uuid.UUID
    room_id: uuid.UUID
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)
