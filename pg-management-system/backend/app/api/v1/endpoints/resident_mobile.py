import uuid
from typing import List, Optional
from fastapi import APIRouter, Depends, File, Query, UploadFile, status
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
