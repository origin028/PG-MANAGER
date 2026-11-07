import uuid
from typing import List, Optional
from fastapi import APIRouter, Depends, Query, Request, status
from sqlalchemy.orm import Session

from app.api.deps import get_current_user, get_db
from app.models.user import User
from app.schemas.bed import BedCreate, BedRead, BedStatusUpdate
from app.schemas.common import APIResponse
from app.schemas.room import RoomCreate, RoomDetail, RoomRead, RoomUpdate
from app.services.room_service import (
    create_bed,
    create_room,
    get_room_detail,
    list_beds,
    list_rooms,
    update_room,
)

router = APIRouter()


@router.get("", response_model=APIResponse[List[RoomRead]], status_code=status.HTTP_200_OK)
def get_rooms(
    property_id: Optional[uuid.UUID] = Query(None, description="Filter by property ID"),
    floor_number: Optional[int] = Query(None, description="Filter by floor number"),
    room_type: Optional[str] = Query(None, description="Filter by room type"),
    is_active: Optional[bool] = Query(None, description="Filter by active status"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    List rooms accessible to the authenticated user.
    - Super Admin: All company rooms (or filtered by property_id).
    - Property Manager / Staff: Only rooms in assigned properties.
    - Resident: 403 Forbidden.
    """
    rooms = list_rooms(
        db=db,
        user=current_user,
        property_id=property_id,
        floor_number=floor_number,
        room_type=room_type,
        is_active=is_active,
    )
    return APIResponse(
        success=True,
        message=f"Retrieved {len(rooms)} rooms.",
        data=rooms,
    )


@router.get("/{room_id}", response_model=APIResponse[RoomDetail], status_code=status.HTTP_200_OK)
def get_room(
    room_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Get full details of a specific room, including its beds."""
    detail = get_room_detail(db=db, room_id=room_id, user=current_user)
    return APIResponse(
        success=True,
        message="Room details retrieved successfully.",
        data=detail,
    )


@router.put("/{room_id}", response_model=APIResponse[RoomRead], status_code=status.HTTP_200_OK)
def edit_room(
    room_id: uuid.UUID,
    payload: RoomUpdate,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Update room configuration. Restricted to Super Admin and Property Managers."""
    ip_address = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")

    room = update_room(
        db=db,
        room_id=room_id,
        data=payload,
        user=current_user,
        ip_address=ip_address,
        user_agent=user_agent,
    )
    return APIResponse(
        success=True,
        message="Room updated successfully.",
        data=room,
    )


@router.get("/{room_id}/beds", response_model=APIResponse[List[BedRead]], status_code=status.HTTP_200_OK)
def get_room_beds(
    room_id: uuid.UUID,
    status_filter: Optional[str] = Query(None, alias="status"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """List beds for a specific room."""
    beds = list_beds(
        db=db,
        user=current_user,
        room_id=room_id,
        status=status_filter,
    )
    return APIResponse(
        success=True,
        message=f"Retrieved {len(beds)} beds.",
        data=beds,
    )


@router.post("/{room_id}/beds", response_model=APIResponse[BedRead], status_code=status.HTTP_201_CREATED)
def add_bed_to_room(
    room_id: uuid.UUID,
    payload: BedCreate,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Create a new bed in a room. Restricted to Super Admin and Property Managers."""
    ip_address = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")

    bed = create_bed(
        db=db,
        room_id=room_id,
        data=payload,
        user=current_user,
        ip_address=ip_address,
        user_agent=user_agent,
    )
    return APIResponse(
        success=True,
        message="Bed created successfully.",
        data=bed,
    )


@router.put("/{room_id}/beds/{bed_id}", response_model=APIResponse[BedRead], status_code=status.HTTP_200_OK)
def put_bed_in_room(
    room_id: uuid.UUID,
    bed_id: uuid.UUID,
    payload: BedStatusUpdate,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Update a bed's status through its parent room.

    The bed must belong to the supplied room, the caller must be assigned to the
    bed's property, and occupancy can only be created through resident check-in.
    """
    from app.services.room_service import update_bed_status

    ip_address = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")
    bed = update_bed_status(
        db=db,
        bed_id=bed_id,
        new_status=payload.status,
        user=current_user,
        ip_address=ip_address,
        user_agent=user_agent,
        room_id=room_id,
    )
    return APIResponse(success=True, message=f"Bed status updated to '{bed.status}'.", data=bed)

