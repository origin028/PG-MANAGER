import uuid
from datetime import date, datetime
from typing import Optional
from pydantic import BaseModel, ConfigDict


class ResidentBase(BaseModel):
    check_in_date: date
    expected_check_out_date: Optional[date] = None
    security_deposit: float = 0.00
    monthly_rent: float = 0.00
    emergency_contact_name: Optional[str] = None
    emergency_contact_phone: Optional[str] = None
    id_proof_type: Optional[str] = None


class ResidentCreate(ResidentBase):
    user_id: uuid.UUID
    property_id: uuid.UUID
    room_id: Optional[uuid.UUID] = None
    bed_id: Optional[uuid.UUID] = None
    id_proof_number: Optional[str] = None


class ResidentRead(ResidentBase):
    id: uuid.UUID
    user_id: uuid.UUID
    property_id: uuid.UUID
    room_id: Optional[uuid.UUID] = None
    bed_id: Optional[uuid.UUID] = None
    kyc_status: str
    id_proof_number_masked: Optional[str] = None
    status: str
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class ResidentSummary(BaseModel):
    id: uuid.UUID
    user_id: uuid.UUID
    property_id: uuid.UUID
    check_in_date: date
    kyc_status: str
    status: str

    model_config = ConfigDict(from_attributes=True)
