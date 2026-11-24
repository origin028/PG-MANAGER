import uuid
from typing import List, Optional
from fastapi import APIRouter, Depends, File, Query, Request, UploadFile, status
from sqlalchemy.orm import Session

from app.core.exceptions import BadRequestError
from app.dependencies import get_current_active_resident, get_current_user, get_db
from app.models.resident import Resident
from app.models.user import User
from app.schemas.common import APIResponse
from app.schemas.resident_mobile import (
    FoodMenuWeeklyResponse,
    PropertyContactsResponse,
    ResidentComplaintCreate,
    ResidentComplaintRead,
    ResidentDashboardResponse,
    ResidentInvoiceDetailResponse,
    ResidentInvoiceListItem,
    ResidentPaymentHistoryItem,
    ResidentProfileFullRead,
    ResidentPropertyDetailsResponse,
    ResidentSettingsRead,
    ResidentSettingsUpdate,
)
from app.services.resident_mobile_service import ResidentMobileService

router = APIRouter()


# ---------------------------------------------------------------------------
# 1. Resident Home Dashboard
# ---------------------------------------------------------------------------
@router.get(
    "/dashboard",
    response_model=APIResponse[ResidentDashboardResponse],
    status_code=status.HTTP_200_OK,
    summary="Get Resident Home Dashboard",
)
def get_resident_dashboard(
    active_resident: Resident = Depends(get_current_active_resident),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Returns aggregated dashboard data for the authenticated resident:
    - Profile information & stay details
    - Rent summary (total due, next due date, last payment)
    - Recent property notices (broadcasts)
    - Recent payments
    """
    service = ResidentMobileService(db)
    data = service.get_dashboard(active_resident, current_user)
    return APIResponse(
        success=True,
        message="Resident dashboard retrieved successfully.",
        data=data,
    )


# ---------------------------------------------------------------------------
# 2. Weekly Food Menu
# ---------------------------------------------------------------------------
@router.get(
    "/food-menu",
    response_model=APIResponse[FoodMenuWeeklyResponse],
    status_code=status.HTTP_200_OK,
    summary="Get Weekly Food Menu",
)
def get_food_menu(
    active_resident: Resident = Depends(get_current_active_resident),
    db: Session = Depends(get_db),
):
    """
    Returns Monday through Sunday food menu (Breakfast, Lunch, Dinner)
    scoped to the resident's assigned PG property.
    """
    service = ResidentMobileService(db)
    data = service.get_food_menu(active_resident)
    return APIResponse(
        success=True,
        message="Weekly food menu retrieved successfully.",
        data=data,
    )


# ---------------------------------------------------------------------------
# 3. Rent & Payments
# ---------------------------------------------------------------------------
@router.get(
    "/invoices",
    response_model=APIResponse[List[ResidentInvoiceListItem]],
    status_code=status.HTTP_200_OK,
    summary="Get Resident Invoices",
)
def get_resident_invoices(
    status_filter: Optional[str] = Query(None, alias="status", description="Filter by status (PENDING, PAID, etc.)"),
    active_resident: Resident = Depends(get_current_active_resident),
    db: Session = Depends(get_db),
):
    """
    Returns all rent and charge invoices issued to the authenticated resident.
    """
    service = ResidentMobileService(db)
    data = service.get_invoices(active_resident, status_filter)
    return APIResponse(
        success=True,
        message=f"Retrieved {len(data)} invoices.",
        data=data,
    )


@router.get(
    "/invoices/{invoice_id}",
    response_model=APIResponse[ResidentInvoiceDetailResponse],
    status_code=status.HTTP_200_OK,
    summary="Get Resident Invoice Detail",
)
def get_resident_invoice_detail(
    invoice_id: uuid.UUID,
    active_resident: Resident = Depends(get_current_active_resident),
    db: Session = Depends(get_db),
):
    """
    Returns breakdown of a specific invoice with payment receipts.
    Strictly isolated: Resident can only view their own invoice.
    """
    service = ResidentMobileService(db)
    data = service.get_invoice_detail(active_resident, invoice_id)
    return APIResponse(
        success=True,
        message="Invoice detail retrieved successfully.",
        data=data,
    )


@router.get(
    "/payments",
    response_model=APIResponse[List[ResidentPaymentHistoryItem]],
    status_code=status.HTTP_200_OK,
    summary="Get Resident Payment History",
)
def get_resident_payments(
    active_resident: Resident = Depends(get_current_active_resident),
    db: Session = Depends(get_db),
):
    """
    Returns ledger of all payment transactions made by the authenticated resident.
    """
    service = ResidentMobileService(db)
    data = service.get_payments(active_resident)
    return APIResponse(
        success=True,
        message=f"Retrieved {len(data)} payment transactions.",
        data=data,
    )


# ---------------------------------------------------------------------------
# 4. My Profile
# ---------------------------------------------------------------------------
@router.get(
    "/profile",
    response_model=APIResponse[ResidentProfileFullRead],
    status_code=status.HTTP_200_OK,
    summary="Get Resident Profile & KYC Status",
)
def get_resident_profile(
    active_resident: Resident = Depends(get_current_active_resident),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Returns complete resident profile:
    - Personal info & address
    - Property, room and bed allocation
    - KYC verification status & masked document numbers (Anti-Leak)
    """
    service = ResidentMobileService(db)
    data = service.get_profile(active_resident, current_user)
    return APIResponse(
        success=True,
        message="Resident profile retrieved successfully.",
        data=data,
    )


# ---------------------------------------------------------------------------
# 5. Property Details
# ---------------------------------------------------------------------------
@router.get(
    "/property",
    response_model=APIResponse[ResidentPropertyDetailsResponse],
    status_code=status.HTTP_200_OK,
    summary="Get Resident Property Details",
)
def get_resident_property(
    active_resident: Resident = Depends(get_current_active_resident),
    db: Session = Depends(get_db),
):
    """
    Returns property address, assigned room & floor, bed, amenities and house rules.
    """
    service = ResidentMobileService(db)
    data = service.get_property_details(active_resident)
    return APIResponse(
        success=True,
        message="Property details retrieved successfully.",
        data=data,
    )


# ---------------------------------------------------------------------------
# 6. Raise Complaint & Track
# ---------------------------------------------------------------------------
@router.get(
    "/complaints",
    response_model=APIResponse[List[ResidentComplaintRead]],
    status_code=status.HTTP_200_OK,
    summary="List Resident Complaints",
)
def list_resident_complaints(
    active_resident: Resident = Depends(get_current_active_resident),
    db: Session = Depends(get_db),
):
    """
    Lists all maintenance and service complaints raised by the authenticated resident.
    """
    service = ResidentMobileService(db)
    data = service.list_complaints(active_resident)
    return APIResponse(
        success=True,
        message=f"Retrieved {len(data)} complaints.",
        data=data,
    )


@router.post(
    "/complaints/upload-photo",
    response_model=APIResponse[dict],
    status_code=status.HTTP_200_OK,
    summary="Upload Complaint Photo Attachment",
)
async def upload_complaint_photo(
    photo: UploadFile = File(..., description="Photo attachment (JPG, PNG, max 5MB)"),
    active_resident: Resident = Depends(get_current_active_resident),
):
    """
    Uploads and validates a photo attachment for a complaint.
    Enforces 5MB limit, allowed extensions (.jpg, .jpeg, .png), and safe UUID filename.
    """
    from app.services.file_service import FileService

    photo_path = await FileService.validate_and_save_upload(photo, "complaint_photo")
    return APIResponse(
        success=True,
        message="Complaint photo uploaded successfully.",
        data={
            "photo_path": photo_path,
            "filename": photo.filename,
        },
    )


@router.post(
    "/complaints",
    response_model=APIResponse[ResidentComplaintRead],
    status_code=status.HTTP_201_CREATED,
    summary="Raise Maintenance Complaint",
)
def create_resident_complaint(
    payload: ResidentComplaintCreate,
    active_resident: Resident = Depends(get_current_active_resident),
    db: Session = Depends(get_db),
):
    """
    Submits a new maintenance complaint for the resident's assigned PG.
    Accepts category, title, description, priority, and optional photo attachment.
    """
    service = ResidentMobileService(db)
    data = service.create_complaint(active_resident, payload)
    return APIResponse(
        success=True,
        message="Complaint submitted successfully.",
        data=data,
    )


# ---------------------------------------------------------------------------
# 7. Property Contacts
# ---------------------------------------------------------------------------
@router.get(
    "/property-contacts",
    response_model=APIResponse[PropertyContactsResponse],
    status_code=status.HTTP_200_OK,
    summary="Get Property Contacts",
)
def get_property_contacts(
    active_resident: Resident = Depends(get_current_active_resident),
    db: Session = Depends(get_db),
):
    """
    Returns contact numbers for Property Manager, Warden, Caretaker, and Security.
    """
    service = ResidentMobileService(db)
    data = service.get_property_contacts(active_resident)
    return APIResponse(
        success=True,
        message="Property contacts retrieved successfully.",
        data=data,
    )


# ---------------------------------------------------------------------------
# 8. Resident Settings
# ---------------------------------------------------------------------------
@router.get(
    "/settings",
    response_model=APIResponse[ResidentSettingsRead],
    status_code=status.HTTP_200_OK,
    summary="Get Resident Settings",
)
def get_resident_settings(
    active_resident: Resident = Depends(get_current_active_resident),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Retrieves app settings (dark mode, language, notification preferences).
    """
    service = ResidentMobileService(db)
    data = service.get_settings(current_user)
    return APIResponse(
        success=True,
        message="Resident settings retrieved successfully.",
        data=data,
    )


@router.patch(
    "/settings",
    response_model=APIResponse[ResidentSettingsRead],
    status_code=status.HTTP_200_OK,
    summary="Update Resident Settings",
)
def update_resident_settings(
    payload: ResidentSettingsUpdate,
    active_resident: Resident = Depends(get_current_active_resident),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Updates app settings (dark mode, language, notification preferences).
    """
    service = ResidentMobileService(db)
    data = service.update_settings(current_user, payload)
    return APIResponse(
        success=True,
        message="Resident settings updated successfully.",
        data=data,
    )


@router.get("/deposit", status_code=status.HTTP_200_OK, summary="My Security Deposit")
def get_my_deposit(
    active_resident: Resident = Depends(get_current_active_resident),
    db: Session = Depends(get_db),
):
    """The resident's deposit held and what they would get back on moving out today (refund policy)."""
    from app.core.config import settings
    from app.services.deposit_service import DepositService, compute_exit_settlement, money

    svc = DepositService(db)
    held = svc.balance(active_resident.id) or money(active_resident.security_deposit)
    preview = compute_exit_settlement(held)
    return APIResponse(
        success=True,
        message="Deposit retrieved.",
        data={
            "deposit_held": float(held),
            "refund_percent": settings.DEPOSIT_REFUND_PERCENT,
            "refund_on_exit": float(preview.refund),
        },
    )


@router.get("/meal-pass", status_code=status.HTTP_200_OK, summary="My Meal Pass (rotating QR)")
def get_my_meal_pass(
    active_resident: Resident = Depends(get_current_active_resident),
    db: Session = Depends(get_db),
):
    """Short-lived signed QR token for the meal being served now. The app refreshes it before it expires."""
    from datetime import datetime, timezone

    import sqlalchemy as sa

    from app.models.meal_serving import MealServing
    from app.services.meal_service import current_meal, issue_pass, tz

    from app.models.property import Property
    from app.services.kitchen_access import kitchen_enabled

    prop = db.get(Property, active_resident.property_id)
    if not prop or not kitchen_enabled(db, prop.company_id):
        return APIResponse(success=True, message="Meal passes are not in use.", data={"enabled": False, "meal": None})

    now = datetime.now(timezone.utc)
    current, upcoming = current_meal(db, active_resident.property_id, now)
    nxt = {"meal": upcoming.meal, "starts_at": upcoming.start.isoformat()} if upcoming else None
    if current is None:
        return APIResponse(success=True, message="No meal is being served right now.", data={"enabled": True, "meal": None, "next": nxt})
    day = now.astimezone(tz()).date()
    served = db.scalar(sa.select(MealServing.served_at).where(
        MealServing.resident_id == active_resident.id, MealServing.meal_date == day, MealServing.meal_type == current.meal))
    token, ttl = issue_pass(active_resident, current.meal, day, now)
    return APIResponse(
        success=True,
        message="Meal pass issued.",
        data={"enabled": True, "meal": current.meal, "token": token, "expires_in": ttl, "served_at": served.isoformat() if served else None,
              "window_ends_at": current.end.isoformat(), "next": nxt},
    )


# ---------------------------------------------------------------------------
# App access + resident-completed KYC (owner adds name/phone/email, resident does the rest)
# ---------------------------------------------------------------------------
def _own_resident(user: User, db: Session) -> Resident:
    import sqlalchemy as sa

    from app.core.exceptions import PermissionDeniedError

    if not user.role or user.role.name != "RESIDENT":
        raise PermissionDeniedError("Only residents can use this.")
    r = db.scalar(sa.select(Resident).where(Resident.user_id == user.id))
    if not r or r.status not in ("ACTIVE", "NOTICE_PERIOD"):
        raise PermissionDeniedError("Your resident account is not active.")
    return r


@router.get("/portal", status_code=status.HTTP_200_OK, summary="My app access and KYC deadline")
def my_portal(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    from app.services import portal_service

    return APIResponse(success=True, message="Access status.", data=portal_service.state(_own_resident(current_user, db)))


@router.get("/kyc", status_code=status.HTTP_200_OK, summary="My details for the KYC form")
def my_kyc(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    from app.services import portal_service

    r = _own_resident(current_user, db)
    return APIResponse(success=True, message="KYC details.", data={
        "full_name": r.full_name, "phone": r.phone, "email": r.email,
        "date_of_birth": r.date_of_birth.isoformat() if r.date_of_birth else "", "gender": r.gender or "",
        "occupation": r.occupation or "", "emergency_contact_name": r.emergency_contact_name or "",
        "emergency_contact_phone": r.emergency_contact_phone or "", "house_flat_no": r.house_flat_no or "",
        "street": r.street or "", "landmark": r.landmark or "", "city": r.city or "", "state": r.state or "",
        "pincode": r.pincode or "", **portal_service.state(r),
    })


@router.post("/kyc", status_code=status.HTTP_200_OK, summary="Submit my details and ID documents")
async def submit_my_kyc(request: Request, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Multipart form: personal + address fields, verification_method ('Aadhaar + PAN' | 'Passport Only') and the photos.
    Files are checked by content, encrypted and stored exactly like at sign-up. The owner then verifies or rejects."""
    import re
    from datetime import date as _date

    from app.core.exceptions import ConflictError
    from app.services.audit_service import record_audit_log
    from app.services.file_service import FileService
    from app.services.otp_service import normalize_phone

    r = _own_resident(current_user, db)
    if r.kyc_status == "VERIFIED":
        raise ConflictError("Your KYC is already verified.")
    form = await request.form()
    g = lambda k: (str(form.get(k) or "")).strip()  # noqa: E731
    required = ["date_of_birth", "gender", "occupation", "emergency_contact_name", "emergency_contact_phone",
                "house_flat_no", "street", "city", "state", "pincode", "verification_method"]
    missing = [k for k in required if not g(k)]
    if missing:
        raise BadRequestError(f"Please fill in: {', '.join(m.replace('_', ' ') for m in missing)}.")
    try:
        dob = _date.fromisoformat(g("date_of_birth"))
    except ValueError:
        raise BadRequestError("Date of birth must look like 1999-08-14.")
    if not (_date(1940, 1, 1) <= dob <= _date.today().replace(year=_date.today().year - 15)):
        raise BadRequestError("Please check your date of birth.")
    if not re.fullmatch(r"\d{6}", g("pincode")):
        raise BadRequestError("PIN code must be 6 digits.")
    names = ["aadhaar_front_file", "aadhaar_back_file", "pan_card_file", "passport_file", "resident_selfie_file"]
    files = {k: form.get(k) for k in names}
    present = {k: hasattr(v, "filename") and bool(v.filename) for k, v in files.items()}
    method = FileService.validate_kyc_method_and_files(g("verification_method"), present)
    saved = {k: await FileService.validate_and_save_upload(files[k], k) for k in names if present[k]}

    r.date_of_birth = dob
    r.gender = g("gender")
    r.occupation = g("occupation")
    r.emergency_contact_name = g("emergency_contact_name")
    r.emergency_contact_phone = normalize_phone(g("emergency_contact_phone"))
    for k in ("house_flat_no", "street", "city", "state", "pincode"):
        setattr(r, k, g(k))
    r.landmark = g("landmark") or None
    r.verification_method = method
    r.id_proof_type = "PASSPORT" if method == "PASSPORT" else "AADHAAR"
    r.aadhaar_front_path = saved.get("aadhaar_front_file")
    r.aadhaar_back_path = saved.get("aadhaar_back_file")
    r.pan_card_path = saved.get("pan_card_file")
    r.passport_path = saved.get("passport_file")
    r.resident_selfie_path = saved.get("resident_selfie_file")
    r.kyc_status = "SUBMITTED"
    record_audit_log(db=db, action="RESIDENT_KYC_SUBMITTED", resource_type="residents", user_id=current_user.id,
                     user_email=current_user.email, user_role="RESIDENT", property_id=r.property_id, resource_id=str(r.id),
                     details={"method": method})
    db.commit()
    return APIResponse(success=True, message="Thanks! Your details were sent to the PG for verification.",
                       data={"kyc_status": r.kyc_status})
