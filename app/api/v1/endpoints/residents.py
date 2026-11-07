import uuid
from typing import List, Optional
from fastapi import APIRouter, Depends, Query, Request, status
from sqlalchemy.orm import Session
import sqlalchemy as sa

from app.api.deps import get_current_user, get_db
from app.core.exceptions import NotFoundError, PermissionDeniedError
from app.models.resident import Resident
from app.models.user import User
from app.schemas.common import APIResponse
from app.schemas.resident import (
    ResidentCheckIn,
    ResidentCheckOut,
    ResidentCreate,
    ResidentDetail,
    ResidentKYCUpdate,
    ResidentOccupancyDetail,
    ResidentUpdate,
)
from app.services.resident_service import (
    check_in_resident,
    check_out_resident,
    create_resident,
    get_occupancy_detail,
    get_resident_detail,
    list_residents,
    update_resident,
    update_resident_kyc,
)

router = APIRouter()


@router.get("", response_model=APIResponse[List[ResidentDetail]], status_code=status.HTTP_200_OK)
def get_residents(
    property_id: Optional[uuid.UUID] = Query(None, description="Filter by property ID"),
    status_filter: Optional[str] = Query(None, alias="status", description="Filter by status (PENDING, ACTIVE, CHECKED_OUT, CANCELLED)"),
    kyc_status: Optional[str] = Query(None, description="Filter by KYC status (PENDING, VERIFIED, REJECTED)"),
    search: Optional[str] = Query(None, description="Search by name, phone, or email"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    List residents accessible to the authenticated user.
    - Super Admin: All company residents (or filtered by property_id).
    - Property Manager / Staff: Only residents in assigned properties.
    - Resident: 403 Forbidden.
    """
    residents = list_residents(
        db=db,
        user=current_user,
        property_id=property_id,
        status_filter=status_filter,
        kyc_status_filter=kyc_status,
        search=search,
    )
    return APIResponse(
        success=True,
        message=f"Retrieved {len(residents)} residents.",
        data=residents,
    )


@router.post("", response_model=APIResponse[ResidentDetail], status_code=status.HTTP_201_CREATED)
def admit_resident(
    payload: ResidentCreate,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Create a resident admission record.
    Restricted to Super Admin and Property Managers for their assigned properties.
    """
    ip_address = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")

    resident = create_resident(
        db=db,
        data=payload,
        user=current_user,
        ip_address=ip_address,
        user_agent=user_agent,
    )
    return APIResponse(
        success=True,
        message=f"Resident '{resident.full_name}' admitted successfully in status '{resident.status}'.",
        data=resident,
    )


@router.get("/me", response_model=APIResponse[ResidentDetail], status_code=status.HTTP_200_OK)
def get_my_resident_profile(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Retrieve the authenticated resident's own profile.
    Accessible to Resident Mobile app users.
    """
    resident = db.scalar(
        sa.select(Resident).where(
            sa.or_(
                Resident.user_id == current_user.id,
                Resident.phone == current_user.phone,
            )
        )
    )
    if not resident:
        raise NotFoundError("No resident profile found for the authenticated user.")

    detail = get_resident_detail(db=db, resident_id=resident.id, user=current_user)
    return APIResponse(
        success=True,
        message="Resident profile retrieved successfully.",
        data=detail,
    )


@router.get("/me/occupancy", response_model=APIResponse[ResidentOccupancyDetail], status_code=status.HTTP_200_OK)
def get_my_occupancy_detail(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Retrieve the authenticated resident's own room and bed occupancy details.
    Accessible to Resident Mobile app users.
    """
    resident = db.scalar(
        sa.select(Resident).where(
            sa.or_(
                Resident.user_id == current_user.id,
                Resident.phone == current_user.phone,
            )
        )
    )
    if not resident:
        raise NotFoundError("No resident profile found for the authenticated user.")

    occupancy = get_occupancy_detail(db=db, resident_id=resident.id, user=current_user)
    return APIResponse(
        success=True,
        message="Occupancy details retrieved successfully.",
        data=occupancy,
    )


@router.get("/{resident_id}", response_model=APIResponse[ResidentDetail], status_code=status.HTTP_200_OK)
def get_resident(
    resident_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Get full details of a specific resident.
    - Super Admin: All company residents.
    - Property Manager / Staff: Only residents in assigned properties.
    - Resident: Only their own record.
    """
    resident = get_resident_detail(db=db, resident_id=resident_id, user=current_user)
    return APIResponse(
        success=True,
        message="Resident details retrieved successfully.",
        data=resident,
    )


@router.put("/{resident_id}", response_model=APIResponse[ResidentDetail], status_code=status.HTTP_200_OK)
def edit_resident(
    resident_id: uuid.UUID,
    payload: ResidentUpdate,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Update permitted resident profile details.
    Restricted to Super Admin and Property Managers.
    """
    ip_address = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")

    resident = update_resident(
        db=db,
        resident_id=resident_id,
        data=payload,
        user=current_user,
        ip_address=ip_address,
        user_agent=user_agent,
    )
    return APIResponse(
        success=True,
        message="Resident updated successfully.",
        data=resident,
    )


@router.post("/{resident_id}/check-in", response_model=APIResponse[ResidentDetail], status_code=status.HTTP_200_OK)
def check_in(
    resident_id: uuid.UUID,
    payload: ResidentCheckIn,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Check in a resident and assign an available bed with database concurrency protection.
    Restricted to Super Admin and Property Managers.
    """
    ip_address = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")

    resident = check_in_resident(
        db=db,
        resident_id=resident_id,
        payload=payload,
        user=current_user,
        ip_address=ip_address,
        user_agent=user_agent,
    )
    return APIResponse(
        success=True,
        message=f"Resident '{resident.full_name}' checked in successfully.",
        data=resident,
    )


@router.post("/{resident_id}/check-out", response_model=APIResponse[ResidentDetail], status_code=status.HTTP_200_OK)
def check_out(
    resident_id: uuid.UUID,
    payload: ResidentCheckOut,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Check out a resident and atomically release their occupied bed to AVAILABLE.
    Restricted to Super Admin and Property Managers.
    """
    ip_address = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")

    resident = check_out_resident(
        db=db,
        resident_id=resident_id,
        payload=payload,
        user=current_user,
        ip_address=ip_address,
        user_agent=user_agent,
    )
    return APIResponse(
        success=True,
        message=f"Resident '{resident.full_name}' checked out successfully and bed released.",
        data=resident,
    )


@router.patch("/{resident_id}/kyc", response_model=APIResponse[ResidentDetail], status_code=status.HTTP_200_OK)
def verify_kyc(
    resident_id: uuid.UUID,
    payload: ResidentKYCUpdate,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Update resident KYC verification status and safe metadata.
    Authorized for Super Admin, Property Manager, and Staff within assigned properties.
    """
    ip_address = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")

    resident = update_resident_kyc(
        db=db,
        resident_id=resident_id,
        payload=payload,
        user=current_user,
        ip_address=ip_address,
        user_agent=user_agent,
    )
    return APIResponse(
        success=True,
        message=f"Resident KYC status updated to '{resident.kyc_status}'.",
        data=resident,
    )


@router.get("/{resident_id}/occupancy", response_model=APIResponse[ResidentOccupancyDetail], status_code=status.HTTP_200_OK)
def get_resident_occupancy(
    resident_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    View resident occupancy and stay duration details.
    """
    occupancy = get_occupancy_detail(db=db, resident_id=resident_id, user=current_user)
    return APIResponse(
        success=True,
        message="Occupancy details retrieved successfully.",
        data=occupancy,
    )
