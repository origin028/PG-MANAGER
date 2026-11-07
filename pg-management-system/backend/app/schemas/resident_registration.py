import uuid
from datetime import date, datetime
from typing import Optional
from pydantic import BaseModel, ConfigDict, EmailStr, Field


class OTPRequest(BaseModel):
    phone: str = Field(..., description="Indian 10-digit mobile number")


class OTPResponse(BaseModel):
    phone: str
    expires_in_seconds: int
    cooldown_seconds: int
    email_masked: Optional[str] = None


class ResidentRegistrationForm(BaseModel):
    # Personal Information
    full_name: str = Field(..., min_length=2, max_length=150, description="Resident full name")
    date_of_birth: date = Field(..., description="Date of birth")
    gender: str = Field(..., min_length=1, max_length=20, description="Gender (e.g., Male, Female, Other)")
    occupation: str = Field(..., min_length=1, max_length=100, description="Current occupation")

    # Contact Information
    primary_phone: str = Field(..., description="Indian 10-digit mobile number")
    email: EmailStr = Field(..., description="Resident contact and OTP destination email")
    emergency_contact: str = Field(
        ...,
        min_length=2,
        max_length=150,
        description="Preserved single-field emergency contact (e.g. 'Father - Ramesh - 9876543210')",
    )

    # Permanent Address
    house_flat_no: str = Field(..., min_length=1, max_length=100, description="House/Flat number")
    street: str = Field(..., min_length=1, max_length=150, description="Street/Locality")
    landmark: Optional[str] = Field(None, max_length=150, description="Nearby landmark (optional)")
    city: str = Field(..., min_length=1, max_length=100, description="City")
    state: str = Field(..., min_length=1, max_length=100, description="State")
    pincode: str = Field(..., min_length=4, max_length=20, description="Postal pincode")

    # Target Property
    property_id: uuid.UUID = Field(..., description="Target PG property ID")

    # KYC Verification Selection
    verification_method: str = Field(
        ...,
        description="Choose exactly one method: 'Aadhaar + PAN' or 'Passport Only'",
    )

    # Pre-stored file paths (optional when submitting via JSON)
    aadhaar_front_path: Optional[str] = None
    aadhaar_back_path: Optional[str] = None
    pan_card_path: Optional[str] = None
    passport_path: Optional[str] = None
    resident_selfie_path: Optional[str] = None


class ResidentRegistrationVerifyRequest(BaseModel):
    phone: str = Field(..., description="Indian 10-digit mobile number")
    otp: str = Field(..., min_length=6, max_length=6, description="6-digit verification code")


class ResidentLoginOTPRequest(BaseModel):
    phone: str = Field(..., description="Registered Indian 10-digit mobile number")


class ResidentLoginOTPVerifyRequest(BaseModel):
    phone: str = Field(..., description="Registered Indian 10-digit mobile number")
    otp: str = Field(..., min_length=6, max_length=6, description="6-digit verification code")


class ResidentRegistrationRequest(BaseModel):
    phone: str = Field(..., description="Indian 10-digit mobile number")
    otp: str = Field(..., min_length=6, max_length=6, description="6-digit verification code")
    full_name: str = Field(..., min_length=2, max_length=150, description="Resident full name")
    password: Optional[str] = Field(None, min_length=6, description="Account password (optional/legacy)")
    property_id: uuid.UUID = Field(..., description="Target PG property ID")
    email: Optional[EmailStr] = None


class ResidentRegistrationResponse(BaseModel):
    resident_id: uuid.UUID
    user_id: uuid.UUID
    full_name: str
    phone: str
    email: Optional[str] = None
    property_id: uuid.UUID
    property_name: str
    status: str
    approval_status: str
    registered_at: datetime

    model_config = ConfigDict(from_attributes=True)


class PendingResidentApprovalItem(BaseModel):
    resident_id: uuid.UUID
    user_id: uuid.UUID
    full_name: str
    phone: str
    email: Optional[str] = None
    property_id: uuid.UUID
    property_name: str
    status: str
    approval_status: str
    registered_at: datetime

    # New frontend fields
    date_of_birth: Optional[date] = None
    gender: Optional[str] = None
    occupation: Optional[str] = None
    emergency_contact: Optional[str] = None
    house_flat_no: Optional[str] = None
    street: Optional[str] = None
    landmark: Optional[str] = None
    city: Optional[str] = None
    state: Optional[str] = None
    pincode: Optional[str] = None
    verification_method: Optional[str] = None
    aadhaar_front_path: Optional[str] = None
    aadhaar_back_path: Optional[str] = None
    pan_card_path: Optional[str] = None
    passport_path: Optional[str] = None
    resident_selfie_path: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)


class ResidentApprovalActionRequest(BaseModel):
    room_id: Optional[uuid.UUID] = None
    bed_id: Optional[uuid.UUID] = None
    monthly_rent: Optional[float] = None
    security_deposit: Optional[float] = None
    check_in_date: Optional[date] = None


class ResidentRejectionActionRequest(BaseModel):
    reason: str = Field(..., min_length=2, max_length=255, description="Mandatory audit-logged rejection reason")
