import uuid
from datetime import date, datetime
from decimal import Decimal
from typing import Optional
from pydantic import BaseModel, ConfigDict, EmailStr, Field, model_validator


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


class AdminResidentOnboardRequest(BaseModel):
    full_name: str = Field(..., min_length=2, max_length=150)
    phone: str = Field(..., min_length=10, max_length=15)
    email: Optional[EmailStr] = None
    date_of_birth: Optional[date] = None
    gender: Optional[str] = None
    occupation: Optional[str] = None
    emergency_contact_name: Optional[str] = None
    emergency_contact_phone: Optional[str] = None
    house_flat_no: Optional[str] = None
    street: Optional[str] = None
    landmark: Optional[str] = None
    city: Optional[str] = None
    state: Optional[str] = None
    pincode: Optional[str] = None
    property_id: uuid.UUID
    room_id: Optional[uuid.UUID] = None
    bed_id: Optional[uuid.UUID] = None
    check_in_date: Optional[date] = None
    monthly_rent: Optional[float] = None
    security_deposit: Optional[float] = 0.00
    id_proof_type: Optional[str] = "AADHAAR"
    id_proof_number: Optional[str] = None
    kyc_document_type: Optional[str] = None
    kyc_document_number: Optional[str] = None
    pan_number: Optional[str] = None

    @model_validator(mode="after")
    def sync_kyc_fields(self) -> "AdminResidentOnboardRequest":
        if self.kyc_document_type and not self.id_proof_type:
            self.id_proof_type = self.kyc_document_type
        if self.kyc_document_number and not self.id_proof_number:
            self.id_proof_number = self.kyc_document_number
        return self


class ResidentUpdateRequest(BaseModel):
    full_name: Optional[str] = None
    phone: Optional[str] = None
    email: Optional[EmailStr] = None
    emergency_contact_name: Optional[str] = None
    emergency_contact_phone: Optional[str] = None
    room_id: Optional[uuid.UUID] = None
    bed_id: Optional[uuid.UUID] = None
    monthly_rent: Optional[float] = None
    security_deposit: Optional[float] = None
    status: Optional[str] = None  # ACTIVE, NOTICE_PERIOD, CHECKED_OUT
    expected_check_out_date: Optional[date] = None


class ResidentRead(ResidentBase):
    id: uuid.UUID
    user_id: Optional[uuid.UUID] = None
    property_id: uuid.UUID
    room_id: Optional[uuid.UUID] = None
    bed_id: Optional[uuid.UUID] = None
    kyc_status: Optional[str] = "PENDING"
    id_proof_number_masked: Optional[str] = None
    status: str
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class ResidentDetailRead(BaseModel):
    id: uuid.UUID
    user_id: Optional[uuid.UUID] = None
    full_name: Optional[str] = None
    phone: Optional[str] = None
    email: Optional[str] = None
    property_id: uuid.UUID
    property_name: Optional[str] = None
    room_id: Optional[uuid.UUID] = None
    room_number: Optional[str] = None
    bed_id: Optional[uuid.UUID] = None
    bed_number: Optional[str] = None
    check_in_date: Optional[date] = None
    expected_check_out_date: Optional[date] = None
    actual_check_out_date: Optional[date] = None
    monthly_rent: float
    security_deposit: float
    status: str
    kyc_status: Optional[str] = "PENDING"
    id_proof_type: Optional[str] = None
    id_proof_number_masked: Optional[str] = None
    kyc_document_type: Optional[str] = None
    kyc_document_number: Optional[str] = None
    date_of_birth: Optional[date] = None
    gender: Optional[str] = None
    occupation: Optional[str] = None
    emergency_contact_name: Optional[str] = None
    emergency_contact_phone: Optional[str] = None
    permanent_address: Optional[str] = None
    pincode: Optional[str] = None
    verified_at: Optional[datetime] = None
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class ResidentSummary(BaseModel):
    id: uuid.UUID
    user_id: Optional[uuid.UUID] = None
    property_id: uuid.UUID
    full_name: Optional[str] = None
    phone: Optional[str] = None
    room_number: Optional[str] = None
    bed_number: Optional[str] = None
    check_in_date: Optional[date] = None
    kyc_status: Optional[str] = "PENDING"
    status: str
    approval_status: str = "APPROVED"

    model_config = ConfigDict(from_attributes=True)


class ResidentProfileMeRead(BaseModel):
    resident_id: uuid.UUID
    user_id: uuid.UUID
    full_name: str
    phone: str
    email: Optional[str] = None
    property_id: uuid.UUID
    property_name: str
    property_address: Optional[str] = None
    room_id: Optional[uuid.UUID] = None
    room_number: Optional[str] = None
    bed_id: Optional[uuid.UUID] = None
    bed_number: Optional[str] = None
    check_in_date: Optional[date] = None
    expected_check_out_date: Optional[date] = None
    monthly_rent: float
    security_deposit: float
    kyc_status: Optional[str] = "PENDING"
    status: str
    approval_status: str = "APPROVED"


class ResidentCheckoutRequest(BaseModel):
    check_out_date: Optional[date] = None
    expected_check_out_date: Optional[date] = None
    damage_charges: Optional[Decimal] = Field(default=Decimal("0.00"), ge=0)
    damage_notes: Optional[str] = None
    notes: Optional[str] = None
    settle_pending_dues: bool = False
    force_checkout: bool = False


class ResidentCheckoutResponse(BaseModel):
    resident_id: uuid.UUID
    status: str
    check_out_date: Optional[date] = None
    actual_check_out_date: Optional[date] = None
    bed_released: bool = False
    bed_id: Optional[uuid.UUID] = None
    bed_number: Optional[str] = None
    vacated_bed_id: Optional[uuid.UUID] = None
    security_deposit: float = 0.00
    damage_charges: float = 0.00
    unpaid_invoices_total: float = 0.00
    outstanding_dues: float = 0.00
    deposit_refund_amount: float = 0.00
    net_payable_by_resident: float = 0.00
    summary: Optional[str] = None
    message: Optional[str] = None


class KYCActionRequest(BaseModel):
    notes: Optional[str] = None
