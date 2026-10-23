import uuid
from datetime import datetime
from typing import Optional
from pydantic import BaseModel, ConfigDict


class BedBase(BaseModel):
    bed_number: str
    status: str = "AVAILABLE"
    monthly_rent: Optional[float] = None


class BedCreate(BedBase):
    room_id: uuid.UUID


class BedRead(BedBase):
    id: uuid.UUID
    room_id: uuid.UUID
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class BedSummary(BaseModel):
    id: uuid.UUID
    bed_number: str
    status: str
    monthly_rent: Optional[float] = None

    model_config = ConfigDict(from_attributes=True)
