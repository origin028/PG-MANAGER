import uuid
from typing import List, Optional
from fastapi import APIRouter, Depends, Query, Request, status
from sqlalchemy.orm import Session

from app.api.deps import get_current_user, get_db
from app.models.user import User
from app.schemas.bed import BedRead, BedStatusUpdate
from app.schemas.common import APIResponse
from app.services.room_service import get_bed_detail, list_beds, update_bed_status

router = APIRouter()


@router.get("", response_model=APIResponse[List[BedRead]], status_code=status.HTTP_200_OK)
def get_beds(
    property_id: Optional[uuid.UUID] = Query(None, description="Filter by property ID"),
    room_id: Optional[uuid.UUID] = Query(None, description="Filter by room ID"),
    bed_status: Optional[str] = Query(None, alias="status", description="Filter by status (AVAILABLE, OCCUPIED, RESERVED, MAINTENANCE)"),
    is_active: Optional[bool] = Query(None, description="Filter by active status"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    List beds accessible to the authenticated user.
    - Super Admin: All company beds (or filtered by property_id / room_id / status).
    - Property Manager / Staff: Only beds in assigned properties.
    - Resident: 403 Forbidden.
    """
    beds = list_beds(
        db=db,
        user=current_user,
        property_id=property_id,
        room_id=room_id,
        status=bed_status,
        is_active=is_active,
    )
    return APIResponse(
        success=True,
        message=f"Retrieved {len(beds)} beds.",
        data=beds,
    )


@router.get("/{bed_id}", response_model=APIResponse[BedRead], status_code=status.HTTP_200_OK)
def get_bed(
    bed_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Get full details of a specific bed."""
    bed = get_bed_detail(db=db, bed_id=bed_id, user=current_user)
    return APIResponse(
        success=True,
        message="Bed details retrieved successfully.",
        data=bed,
    )


@router.patch("/{bed_id}/status", response_model=APIResponse[BedRead], status_code=status.HTTP_200_OK)
def change_bed_status(
    bed_id: uuid.UUID,
    payload: BedStatusUpdate,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Update bed status (AVAILABLE, MAINTENANCE, RESERVED).
    Authorized for Super Admin, Property Manager, and Staff within their assigned properties.
    """
    ip_address = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")

    bed = update_bed_status(
        db=db,
        bed_id=bed_id,
        new_status=payload.status,
        user=current_user,
        ip_address=ip_address,
        user_agent=user_agent,
    )
    return APIResponse(
        success=True,
        message=f"Bed status updated to '{bed.status}'.",
        data=bed,
    )


@router.put("/{bed_id}", response_model=APIResponse[BedRead], status_code=status.HTTP_200_OK)
def put_bed_status(
    bed_id: uuid.UUID,
    payload: BedStatusUpdate,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Update a bed's status. Occupancy can only be created through check-in."""
    ip_address = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")
    bed = update_bed_status(
        db=db,
        bed_id=bed_id,
        new_status=payload.status,
        user=current_user,
        ip_address=ip_address,
        user_agent=user_agent,
    )
    return APIResponse(success=True, message=f"Bed status updated to '{bed.status}'.", data=bed)

