from collections import defaultdict
from datetime import datetime, timezone
import uuid
from typing import List, Optional
from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.orm import Session
import sqlalchemy as sa

from app.core.exceptions import BadRequestError, ConflictError, NotFoundError
from app.dependencies import get_current_user, get_db, require_roles, verify_property_access
from app.models.bed import Bed
from app.models.property import Property
from app.models.resident import Resident
from app.models.room import Room
from app.models.user import User
from app.schemas.common import APIResponse
from app.schemas.room import (
    BedInfoInRoom,
    FloorWiseRoomsGroup,
    FloorWiseRoomsResponse,
    RoomCreate,
    RoomRead,
    RoomSummary,
    RoomUpdate,
)
from app.services.bed_capacity_service import BedCapacityService
from app.services.property_service import PropertyService

router = APIRouter()


def _build_room_read(room: Room, db: Session) -> RoomRead:
    beds = db.query(Bed).filter(Bed.room_id == room.id, Bed.is_deleted == False).all()
    bed_infos = []
    occupied_count = 0
    for b in beds:
        res = db.query(Resident).filter(Resident.bed_id == b.id, Resident.status == "ACTIVE").first()
        is_occ = (b.status == "OCCUPIED") or (res is not None)
        if is_occ:
            occupied_count += 1
        bed_infos.append(
            BedInfoInRoom(
                id=b.id,
                bed_number=b.bed_number,
                status=b.status,
                monthly_rent=float(b.monthly_rent) if b.monthly_rent is not None else float(room.base_monthly_rent or 0.0),
                is_active=b.is_active,
                resident_id=res.id if res else None,
                resident_name=res.full_name if res else None,
            )
        )
    total_beds = len(beds)
    available_beds = max(0, total_beds - occupied_count)
    return RoomRead(
        id=room.id,
        property_id=room.property_id,
        room_number=room.room_number,
        floor_number=room.floor_number,
        room_type=room.room_type,
        base_monthly_rent=float(room.base_monthly_rent or 0.0),
        base_rent=float(room.base_monthly_rent or 0.0),
        deposit_amount=float(room.deposit_amount or 0.0),
        max_occupancy=room.max_occupancy,
        is_active=room.is_active,
        amenities=room.amenities or {},
        beds=bed_infos,
        total_beds=total_beds,
        occupied_beds=occupied_count,
        available_beds=available_beds,
        created_at=room.created_at,
        updated_at=room.updated_at,
    )


@router.post("", response_model=APIResponse[RoomRead], status_code=status.HTTP_201_CREATED, summary="Create Room")
def create_room(
    payload: RoomCreate,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Adds a new room to a PG property."""
    verify_property_access(payload.property_id, current_user, db)

    # Check duplicate room number in property
    existing = db.scalar(
        sa.select(Room).where(
            Room.property_id == payload.property_id,
            Room.room_number == payload.room_number.strip().upper(),
        )
    )
    if existing:
        raise ConflictError(f"Room number '{payload.room_number}' already exists in this property.")

    rent = payload.base_rent if payload.base_rent is not None else payload.base_monthly_rent

    room = Room(
        property_id=payload.property_id,
        floor_number=payload.floor_number,
        room_number=payload.room_number.strip().upper(),
        room_type=payload.room_type,
        base_monthly_rent=rent or 0.00,
        deposit_amount=payload.deposit_amount or 0.00,
        is_active=payload.is_active,
        amenities=payload.amenities or {},
    )
    db.add(room)
    db.flush()

    # Automatic bed generation if requested
    beds_to_create = 0
    if payload.auto_create_beds or (payload.bed_count is not None and payload.bed_count > 0):
        beds_to_create = payload.bed_count if (payload.bed_count and payload.bed_count > 0) else room.max_occupancy

    if beds_to_create > 0:
        BedCapacityService.assert_can_add_beds_for_property(room.property_id, beds_to_create, db)
        bed_rent = payload.base_rent if payload.base_rent is not None else float(room.base_monthly_rent or 0.0)
        for i in range(beds_to_create):
            sfx = chr(65 + i) if i < 26 else str(i + 1)
            bed = Bed(
                property_id=room.property_id,
                room_id=room.id,
                bed_number=f"{room.room_number}-{sfx}",
                status="AVAILABLE",
                monthly_rent=bed_rent,
                is_active=True,
                is_deleted=False,
            )
            db.add(bed)

    db.commit()
    db.refresh(room)

    return APIResponse(
        success=True,
        message="Room created successfully.",
        data=_build_room_read(room, db),
    )


@router.get("", response_model=APIResponse[List[RoomSummary]], status_code=status.HTTP_200_OK, summary="List Rooms")
def list_rooms(
    property_id: Optional[uuid.UUID] = Query(None, description="Filter by property ID"),
    floor_number: Optional[int] = Query(None, description="Filter by floor number"),
    room_type: Optional[str] = Query(None, description="Filter by room type"),
    is_active: Optional[bool] = Query(None, description="Filter by active status"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Lists rooms property-wise or across accessible properties."""
    query = db.query(Room)
    if property_id:
        verify_property_access(property_id, current_user, db)
        query = query.filter(Room.property_id == property_id)
    else:
        accessible_props = PropertyService(db).get_accessible_properties(current_user)
        accessible_ids = [p.id for p in accessible_props]
        query = query.filter(Room.property_id.in_(accessible_ids))

    if floor_number is not None:
        query = query.filter(Room.floor_number == floor_number)
    if room_type:
        query = query.filter(Room.room_type == room_type)
    if is_active is not None:
        query = query.filter(Room.is_active == is_active)

    rooms = query.order_by(Room.floor_number.asc(), Room.room_number.asc()).all()

    summaries = []
    for r in rooms:
        beds = db.query(Bed).filter(Bed.room_id == r.id, Bed.is_deleted == False).all()
        total_beds = len(beds)
        occupied_beds = sum(1 for b in beds if b.status == "OCCUPIED")
        available_beds = max(0, total_beds - occupied_beds)
        summaries.append(
            RoomSummary(
                id=r.id,
                property_id=r.property_id,
                room_number=r.room_number,
                floor_number=r.floor_number,
                room_type=r.room_type,
                base_rent=float(r.base_monthly_rent or 0.0),
                deposit_amount=float(r.deposit_amount or 0.0),
                total_beds=total_beds,
                occupied_beds=occupied_beds,
                available_beds=available_beds,
                is_active=r.is_active,
            )
        )

    return APIResponse(
        success=True,
        message=f"Retrieved {len(summaries)} rooms.",
        data=summaries,
    )


@router.get("/floor-wise", response_model=APIResponse[FloorWiseRoomsResponse], status_code=status.HTTP_200_OK, summary="Group Rooms Floor-Wise")
def get_rooms_floor_wise(
    property_id: uuid.UUID = Query(..., description="Property ID"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Returns rooms grouped floor-wise with bed capacity breakdown for a property."""
    verify_property_access(property_id, current_user, db)
    prop = db.scalar(sa.select(Property).where(Property.id == property_id))
    if not prop:
        raise NotFoundError("Property not found.")

    rooms = (
        db.query(Room)
        .filter(Room.property_id == property_id)
        .order_by(Room.floor_number.asc(), Room.room_number.asc())
        .all()
    )

    floor_groups = defaultdict(list)
    for r in rooms:
        beds = db.query(Bed).filter(Bed.room_id == r.id, Bed.is_deleted == False).all()
        total_b = len(beds)
        occ_b = sum(1 for b in beds if b.status == "OCCUPIED")
        floor_groups[r.floor_number].append(
            RoomSummary(
                id=r.id,
                property_id=r.property_id,
                room_number=r.room_number,
                floor_number=r.floor_number,
                room_type=r.room_type,
                base_rent=float(r.base_monthly_rent or 0.0),
                deposit_amount=float(r.deposit_amount or 0.0),
                total_beds=total_b,
                occupied_beds=occ_b,
                available_beds=max(0, total_b - occ_b),
                is_active=r.is_active,
            )
        )

    groups = []
    for floor_num in sorted(floor_groups.keys()):
        rms = floor_groups[floor_num]
        tot_b = sum(rm.total_beds for rm in rms)
        occ_b = sum(rm.occupied_beds for rm in rms)
        groups.append(
            FloorWiseRoomsGroup(
                floor_number=floor_num,
                rooms=rms,
                total_rooms=len(rms),
                total_beds=tot_b,
                occupied_beds=occ_b,
                available_beds=max(0, tot_b - occ_b),
            )
        )

    return APIResponse(
        success=True,
        message=f"Retrieved floor-wise rooms for '{prop.name}'.",
        data=FloorWiseRoomsResponse(
            property_id=property_id,
            property_name=prop.name,
            floors=groups,
        ),
    )


@router.get("/{room_id}", response_model=APIResponse[RoomRead], status_code=status.HTTP_200_OK, summary="Get Room Details")
def get_room_details(
    room_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Returns room details including individual bed allocations."""
    room = db.scalar(sa.select(Room).where(Room.id == room_id))
    if not room:
        raise NotFoundError("Room not found.")
    verify_property_access(room.property_id, current_user, db)

    return APIResponse(
        success=True,
        message="Room details retrieved.",
        data=_build_room_read(room, db),
    )


@router.patch("/{room_id}", response_model=APIResponse[RoomRead], status_code=status.HTTP_200_OK, summary="Update Room")
def update_room(
    room_id: uuid.UUID,
    payload: RoomUpdate,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Updates room configuration, rent, or amenities."""
    room = db.scalar(sa.select(Room).where(Room.id == room_id))
    if not room:
        raise NotFoundError("Room not found.")
    verify_property_access(room.property_id, current_user, db)

    update_dict = payload.model_dump(exclude_unset=True)
    if "base_rent" in update_dict and update_dict["base_rent"] is not None:
        room.base_monthly_rent = update_dict["base_rent"]
        update_dict.pop("base_rent")

    if "room_number" in update_dict and update_dict["room_number"]:
        clean_num = update_dict["room_number"].strip().upper()
        if clean_num != room.room_number:
            existing = db.scalar(
                sa.select(Room).where(
                    Room.property_id == room.property_id,
                    Room.room_number == clean_num,
                )
            )
            if existing:
                raise ConflictError(f"Room number '{clean_num}' already exists in this property.")
            room.room_number = clean_num
        update_dict.pop("room_number")

    if "add_beds" in update_dict and update_dict["add_beds"]:
        num_new_beds = int(update_dict["add_beds"])
        if num_new_beds > 0:
            BedCapacityService.assert_can_add_beds_for_property(room.property_id, num_new_beds, db)
            existing_beds = db.scalars(
                sa.select(Bed).where(Bed.room_id == room.id, Bed.is_deleted == False)
            ).all()
            start_idx = len(existing_beds)
            for i in range(num_new_beds):
                sfx = chr(65 + start_idx + i) if (start_idx + i) < 26 else str(start_idx + i + 1)
                bed = Bed(
                    property_id=room.property_id,
                    room_id=room.id,
                    bed_number=f"{room.room_number}-{sfx}",
                    status="AVAILABLE",
                    monthly_rent=float(room.base_monthly_rent or 0.0),
                    is_active=True,
                    is_deleted=False,
                )
                db.add(bed)
        update_dict.pop("add_beds")
    if "auto_create_beds" in update_dict:
        update_dict.pop("auto_create_beds")

    for f, v in update_dict.items():
        if hasattr(room, f):
            setattr(room, f, v)

    db.commit()
    db.refresh(room)

    return APIResponse(
        success=True,
        message="Room updated successfully.",
        data=_build_room_read(room, db),
    )


@router.get(
    "/property/{property_id}/floors",
    response_model=APIResponse[FloorWiseRoomsResponse],
    status_code=status.HTTP_200_OK,
    summary="Group Rooms Floor-Wise by Property Path (Alias)",
    include_in_schema=False,
)
def get_rooms_floor_wise_by_property_alias(
    property_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Path-based alias for get_rooms_floor_wise."""
    return get_rooms_floor_wise(property_id=property_id, current_user=current_user, db=db)


@router.delete(
    "/{room_id}",
    response_model=APIResponse[dict],
    status_code=status.HTTP_200_OK,
    summary="Delete or Deactivate Room",
)
def delete_room(
    room_id: uuid.UUID,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """
    Safely deletes or deactivates a room.
    - Rejects deletion if any bed in the room is currently occupied by an active resident (HTTP 400).
    - If historical residents, invoices, or payments are associated with the room or its beds,
      performs a safe deactivation (soft delete, is_active=False) preserving all historical audit trails.
    - If no historical records exist and all beds are available/empty, deletes the room cleanly.
    """
    room = db.scalar(sa.select(Room).where(Room.id == room_id))
    if not room:
        raise NotFoundError("Room not found.")
    verify_property_access(room.property_id, current_user, db)

    # Check 1: Is the room or any of its beds currently occupied?
    active_resident = db.scalar(
        sa.select(Resident).where(
            sa.or_(
                Resident.room_id == room.id,
                Resident.bed_id.in_(
                    sa.select(Bed.id).where(Bed.room_id == room.id)
                ),
            ),
            Resident.status == "ACTIVE",
        )
    )
    if active_resident:
        raise BadRequestError(
            f"Cannot delete room: Bed/room is currently occupied by active resident '{active_resident.full_name}'."
        )

    occupied_bed = db.scalar(
        sa.select(Bed).where(
            Bed.room_id == room.id,
            Bed.status == "OCCUPIED",
            Bed.is_deleted == False,
        )
    )
    if occupied_bed:
        raise BadRequestError(
            f"Cannot delete room: Bed '{occupied_bed.bed_number}' is marked as OCCUPIED."
        )

    # Check 2: Are there historical records (past residents, invoices, payments)?
    has_history = db.scalar(
        sa.select(Resident.id).where(
            sa.or_(
                Resident.room_id == room.id,
                Resident.bed_id.in_(
                    sa.select(Bed.id).where(Bed.room_id == room.id)
                ),
            )
        ).limit(1)
    )

    if has_history:
        # Soft delete / Deactivate to protect foreign keys and financial history
        room.is_active = False
        beds = db.scalars(sa.select(Bed).where(Bed.room_id == room.id)).all()
        for b in beds:
            b.is_deleted = True
            b.is_active = False
            b.deleted_at = datetime.now(timezone.utc)
        db.commit()
        return APIResponse(
            success=True,
            message=f"Room '{room.room_number}' deactivated successfully. Historical records preserved.",
            data={"room_id": str(room_id), "status": "DEACTIVATED"},
        )
    else:
        # No historical relations exist: safe to permanently remove
        db.delete(room)
        db.commit()
        return APIResponse(
            success=True,
            message=f"Room '{room.room_number}' deleted successfully.",
            data={"room_id": str(room_id), "status": "DELETED"},
        )

