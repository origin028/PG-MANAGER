import uuid
from datetime import date, datetime
from typing import Optional
from pydantic import BaseModel, ConfigDict, EmailStr, Field


def mask_id_proof(id_number: Optional[str]) -> Optional[str]:
    """
    Safely redacts sensitive ID documents (Aadhaar, PAN, Passport, etc.).
    Displays only the last 4 characters and masks preceding characters.
    Never stores or logs the unmasked plaintext identifier.
    """
    if not id_number:
        return None
    cleaned = id_number.strip().replace(" ", "").replace("-", "")
    if len(cleaned) <= 4:
        return "****"
    if len(cleaned) == 12:  # Aadhaar format: XXXX-XXXX-1234
        return f"XXXX-XXXX-{cleaned[-4:]}"
    elif len(cleaned) == 10:  # PAN format: XXXXXX1234
        return f"XXXXXX{cleaned[-4:]}"
    else:
        return f"{'X' * (len(cleaned) - 4)}{cleaned[-4:]}"


class ResidentBase(BaseModel):
    full_name: str = Field(..., min_length=1, max_length=150)
    phone: str = Field(..., min_length=10, max_length=30)
    email: Optional[EmailStr] = None
    emergency_contact_name: Optional[str] = Field(None, max_length=150)
    emergency_contact_phone: Optional[str] = Field(None, max_length=30)
    expected_check_out_date: Optional[date] = None
    monthly_rent: Optional[float] = Field(0.00, ge=0.0)
    security_deposit: Optional[float] = Field(0.00, ge=0.0)


class ResidentCreate(ResidentBase):
    property_id: uuid.UUID
    room_id: Optional[uuid.UUID] = None
    bed_id: Optional[uuid.UUID] = None
    check_in_immediately: bool = False
    id_proof_type: Optional[str] = Field(
        None, description="Type of ID (AADHAAR, PAN, PASSPORT, VOTER_ID, DRIVING_LICENSE, OTHER)"
    )
    id_proof_number: Optional[str] = Field(
        None, description="Plaintext ID number, automatically masked prior to persistence"
    )
    kyc_notes: Optional[str] = None


class ResidentUpdate(BaseModel):
    full_name: Optional[str] = Field(None, min_length=1, max_length=150)
    email: Optional[EmailStr] = None
    emergency_contact_name: Optional[str] = Field(None, max_length=150)
    emergency_contact_phone: Optional[str] = Field(None, max_length=30)
    expected_check_out_date: Optional[date] = None
    monthly_rent: Optional[float] = Field(None, ge=0.0)
    security_deposit: Optional[float] = Field(None, ge=0.0)


class ResidentKYCUpdate(BaseModel):
    kyc_status: str = Field(..., description="PENDING, VERIFIED, REJECTED")
    id_proof_type: Optional[str] = None
    id_proof_number: Optional[str] = None
    kyc_notes: Optional[str] = None


class ResidentCheckIn(BaseModel):
    bed_id: uuid.UUID
    check_in_date: Optional[date] = None


class ResidentCheckOut(BaseModel):
    actual_check_out_date: Optional[date] = None
    notes: Optional[str] = None


class ResidentRead(ResidentBase):
    id: uuid.UUID
    company_id: uuid.UUID
    property_id: uuid.UUID
    room_id: Optional[uuid.UUID] = None
    bed_id: Optional[uuid.UUID] = None
    user_id: Optional[uuid.UUID] = None
    check_in_date: Optional[date] = None
    actual_check_out_date: Optional[date] = None
    status: str
    kyc_status: str
    id_proof_type: Optional[str] = None
    id_proof_number_masked: Optional[str] = None
    kyc_notes: Optional[str] = None
    verified_at: Optional[datetime] = None
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class ResidentDetail(ResidentRead):
    property_name: Optional[str] = None
    room_number: Optional[str] = None
    bed_number: Optional[str] = None
    floor_number: Optional[int] = None


class ResidentOccupancyDetail(BaseModel):
    resident_id: uuid.UUID
    resident_name: str
    property_id: uuid.UUID
    property_name: str
    room_id: Optional[uuid.UUID] = None
    room_number: Optional[str] = None
    bed_id: Optional[uuid.UUID] = None
    bed_number: Optional[str] = None
    floor_number: Optional[int] = None
    status: str
    check_in_date: Optional[date] = None
    expected_check_out_date: Optional[date] = None
    actual_check_out_date: Optional[date] = None
    tenure_days: Optional[int] = None
    monthly_rent: float
    security_deposit: float

    model_config = ConfigDict(from_attributes=True)
