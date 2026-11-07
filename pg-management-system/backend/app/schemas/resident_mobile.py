import uuid
from datetime import date, datetime
from typing import Any, Dict, List, Optional
from pydantic import BaseModel, ConfigDict, Field, field_validator


# ---------------------------------------------------------------------------
# 1. Resident Home Dashboard Schemas
# ---------------------------------------------------------------------------

class ResidentBasicInfo(BaseModel):
    resident_id: uuid.UUID
    user_id: uuid.UUID
    full_name: str
    phone: str
    email: Optional[str] = None
    avatar_url: Optional[str] = None
    approval_status: str
    status: str

    model_config = ConfigDict(from_attributes=True)


class ResidentStaySummary(BaseModel):
    property_id: uuid.UUID
    property_name: str
    property_address: Optional[str] = None
    room_number: Optional[str] = None
    floor_number: Optional[int] = None
    bed_number: Optional[str] = None
    check_in_date: Optional[date] = None
    living_since: Optional[date] = None
    monthly_rent: float
    security_deposit: float


class PayNowSummary(BaseModel):
    can_pay: bool
    invoice_id: Optional[uuid.UUID] = None
    invoice_number: Optional[str] = None
    amount_due: float = 0.0
    billing_month: Optional[str] = None
    payment_methods: List[str] = ["UPI", "DEMO_ONLINE"]


class ResidentRentSummary(BaseModel):
    current_rent_amount: float
    total_paid: float
    outstanding_dues: float
    total_due: float
    rent_due_date: Optional[date] = None
    next_due_date: Optional[date] = None
    last_payment_amount: Optional[float] = None
    last_payment_date: Optional[datetime] = None
    rent_payment_status: str  # PAID, DUE, OVERDUE, NO_INVOICE
    status: str               # Alias for rent_payment_status
    pay_now: Optional[PayNowSummary] = None
    rent_reminders: List[str] = []


class ResidentNoticeSummary(BaseModel):
    id: uuid.UUID
    title: str
    content: str
    is_pinned: bool
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class ResidentPaymentSummary(BaseModel):
    payment_id: uuid.UUID
    amount: float
    payment_mode: str = "UPI"
    payment_method: Optional[str] = None
    transaction_reference: Optional[str] = None
    payment_date: Optional[datetime] = None
    status: str
    paid_at: Optional[datetime] = None
    receipt_available: bool = False
    receipt_url: Optional[str] = None
    receipt_number: Optional[str] = None


class ResidentDashboardResponse(BaseModel):
    resident_info: ResidentBasicInfo
    stay_details: ResidentStaySummary
    rent_summary: ResidentRentSummary
    recent_notices: List[ResidentNoticeSummary]
    recent_payments: List[ResidentPaymentSummary]


# ---------------------------------------------------------------------------
# 2. Weekly Food Menu Schemas
# ---------------------------------------------------------------------------

class FoodMenuItem(BaseModel):
    id: uuid.UUID
    property_id: uuid.UUID
    day_of_week: str  # MONDAY, TUESDAY, etc.
    meal_type: str    # BREAKFAST, LUNCH, DINNER
    start_time: Optional[str] = None
    end_time: Optional[str] = None
    dishes: List[str]
    is_active: bool

    model_config = ConfigDict(from_attributes=True)


class FoodMenuWeeklyResponse(BaseModel):
    property_id: uuid.UUID
    property_name: str
    menu_by_day: Dict[str, List[FoodMenuItem]]


# ---------------------------------------------------------------------------
# 3. Rent & Payments Schemas
# ---------------------------------------------------------------------------

class ResidentInvoiceListItem(BaseModel):
    id: uuid.UUID
    invoice_number: str
    billing_month: str
    invoice_type: str
    amount: float
    paid_amount: float
    balance_amount: float
    outstanding_balance: float
    due_date: date
    status: str
    can_pay: bool = False
    notes: Optional[str] = None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class ResidentInvoiceDetailResponse(BaseModel):
    id: uuid.UUID
    property_id: uuid.UUID
    resident_id: uuid.UUID
    invoice_number: str
    billing_month: str
    billing_period_start: Optional[date] = None
    billing_period_end: Optional[date] = None
    invoice_type: str
    rent_amount: Optional[float] = None
    additional_charges: Optional[float] = None
    discount_amount: Optional[float] = None
    amount: float
    paid_amount: float
    balance_amount: float
    outstanding_balance: float
    due_date: date
    status: str
    can_pay: bool = False
    pay_now: Optional[PayNowSummary] = None
    notes: Optional[str] = None
    payments: List[ResidentPaymentSummary] = []
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class ResidentPaymentHistoryItem(BaseModel):
    id: uuid.UUID
    payment_number: Optional[str] = None
    invoice_id: Optional[uuid.UUID] = None
    invoice_number: Optional[str] = None
    amount: float
    payment_mode: str = "UPI"
    payment_method: Optional[str] = None
    transaction_reference: Optional[str] = None
    status: str
    payment_date: Optional[datetime] = None
    paid_at: Optional[datetime] = None
    receipt_available: bool = False
    receipt_url: Optional[str] = None
    receipt_number: Optional[str] = None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


# ---------------------------------------------------------------------------
# 4. My Profile Schemas
# ---------------------------------------------------------------------------

class ResidentAddressInfo(BaseModel):
    house_flat_no: Optional[str] = None
    street: Optional[str] = None
    landmark: Optional[str] = None
    city: Optional[str] = None
    state: Optional[str] = None
    pincode: Optional[str] = None


class ResidentKYCStatusInfo(BaseModel):
    kyc_status: str
    verification_method: Optional[str] = None
    id_proof_type: Optional[str] = None
    id_proof_number_masked: Optional[str] = None
    has_aadhaar_front: bool = False
    has_aadhaar_back: bool = False
    has_pan_card: bool = False
    has_passport: bool = False
    has_selfie: bool = False


class ResidentProfileFullRead(BaseModel):
    resident_id: uuid.UUID
    user_id: uuid.UUID
    full_name: str
    phone: str
    email: Optional[str] = None
    avatar_url: Optional[str] = None
    date_of_birth: Optional[date] = None
    gender: Optional[str] = None
    occupation: Optional[str] = None
    emergency_contact_name: Optional[str] = None
    emergency_contact_phone: Optional[str] = None
    living_since: Optional[date] = None
    permanent_address: ResidentAddressInfo
    stay_details: ResidentStaySummary
    kyc_details: ResidentKYCStatusInfo


# ---------------------------------------------------------------------------
# 5. Property Details Schemas
# ---------------------------------------------------------------------------

class AssignedRoomDetail(BaseModel):
    id: uuid.UUID
    room_number: str
    floor_number: int
    room_type: str
    amenities: List[str] = []


class AssignedBedDetail(BaseModel):
    id: uuid.UUID
    bed_number: str
    monthly_rent: Optional[float] = None


class ResidentPropertyDetailsResponse(BaseModel):
    id: uuid.UUID
    name: str
    code: str
    property_type: str
    address_line1: str
    address_line2: Optional[str] = None
    city: str
    state: str
    pincode: str
    contact_phone: Optional[str] = None
    contact_email: Optional[str] = None
    total_floors: int
    assigned_room: Optional[AssignedRoomDetail] = None
    assigned_bed: Optional[AssignedBedDetail] = None
    amenities: List[str] = []
    inclusions: List[str] = []
    rules: List[str] = []


# ---------------------------------------------------------------------------
# 6. Raise Complaint Schemas
# ---------------------------------------------------------------------------

VALID_COMPLAINT_CATEGORIES = {
    "ELECTRICAL", "PLUMBING", "CLEANING", "WIFI", "FOOD", "CARPENTRY", "OTHER"
}
VALID_COMPLAINT_PRIORITIES = {"LOW", "MEDIUM", "HIGH", "EMERGENCY"}


class ResidentComplaintCreate(BaseModel):
    category: str = Field("OTHER", description="ELECTRICAL, PLUMBING, CLEANING, WIFI, FOOD, CARPENTRY, OTHER")
    title: str = Field(..., max_length=200, description="Short summary of the issue")
    description: str = Field(..., description="Detailed description of the problem")
    priority: str = Field("MEDIUM", description="LOW, MEDIUM, HIGH, EMERGENCY")
    photo_path: Optional[str] = None

    @field_validator("category")
    @classmethod
    def validate_category(cls, v: str) -> str:
        upper = v.strip().upper()
        if upper not in VALID_COMPLAINT_CATEGORIES:
            raise ValueError(
                f"Invalid category '{v}'. Allowed categories: {sorted(VALID_COMPLAINT_CATEGORIES)}"
            )
        return upper

    @field_validator("priority")
    @classmethod
    def validate_priority(cls, v: str) -> str:
        upper = v.strip().upper()
        if upper not in VALID_COMPLAINT_PRIORITIES:
            raise ValueError(
                f"Invalid priority '{v}'. Allowed priorities: {sorted(VALID_COMPLAINT_PRIORITIES)}"
            )
        return upper


class ResidentComplaintRead(BaseModel):
    id: uuid.UUID
    property_id: uuid.UUID
    resident_id: uuid.UUID
    category: str
    title: str
    description: str
    priority: str
    status: str
    photo_path: Optional[str] = None
    assigned_staff_name: Optional[str] = None
    resolution_notes: Optional[str] = None
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


# ---------------------------------------------------------------------------
# 7. Property Contacts Schemas
# ---------------------------------------------------------------------------

class StaffContactItem(BaseModel):
    id: uuid.UUID
    name: str
    role: str
    phone: str
    availability_hours: Optional[str] = "9:00 AM - 6:00 PM"
    is_emergency: bool = False

    model_config = ConfigDict(from_attributes=True)


class PropertyContactsResponse(BaseModel):
    property_id: uuid.UUID
    property_name: str
    property_address: Optional[str] = None
    property_phone: Optional[str] = None
    property_email: Optional[str] = None
    property_manager: Optional[StaffContactItem] = None
    night_caretaker_security: Optional[StaffContactItem] = None
    staff_contacts: List[StaffContactItem] = []


# ---------------------------------------------------------------------------
# 8. Resident Settings Schemas
# ---------------------------------------------------------------------------

ALLOWED_APP_LANGUAGES = {"en", "hi", "kn", "te", "ta", "mr"}


class ResidentSettingsRead(BaseModel):
    dark_mode: bool = False
    language: str = "en"
    rent_reminders_enabled: bool = True
    maintenance_alerts_enabled: bool = True

    model_config = ConfigDict(from_attributes=True)


class ResidentSettingsUpdate(BaseModel):
    dark_mode: Optional[bool] = None
    language: Optional[str] = None
    rent_reminders_enabled: Optional[bool] = None
    maintenance_alerts_enabled: Optional[bool] = None

    @field_validator("language")
    @classmethod
    def validate_language(cls, v: Optional[str]) -> Optional[str]:
        if v is not None:
            lower = v.strip().lower()
            if lower not in ALLOWED_APP_LANGUAGES:
                raise ValueError(
                    f"Invalid language '{v}'. Supported languages: {sorted(ALLOWED_APP_LANGUAGES)}"
                )
            return lower
        return v
