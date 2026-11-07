from datetime import datetime, timezone
import uuid
from typing import List, Optional
from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.orm import Session
import sqlalchemy as sa

from app.core.exceptions import BadRequestError, ConflictError, NotFoundError
from app.dependencies import get_current_user, get_db, require_roles, verify_property_access
from app.models.bed import Bed
from app.models.resident import Resident
from app.models.room import Room
from app.models.user import User
from app.schemas.bed import BedBulkCreate, BedCreate, BedRead, BedSummary, BedUpdate
from app.schemas.common import APIResponse
from app.services.bed_capacity_service import BedCapacityService
from app.services.property_service import PropertyService

router = APIRouter()


def _build_bed_read(bed: Bed, db: Session) -> BedRead:
    res = db.query(Resident).filter(Resident.bed_id == bed.id, Resident.status == "ACTIVE").first()
    room = db.scalar(sa.select(Room).where(Room.id == bed.room_id))
    return BedRead(
        id=bed.id,
        property_id=bed.property_id,
        room_id=bed.room_id,
        room_number=room.room_number if room else None,
        bed_number=bed.bed_number,
        status="OCCUPIED" if res else bed.status,
        monthly_rent=float(bed.monthly_rent) if bed.monthly_rent is not None else (float(room.base_monthly_rent) if room else 0.0),
        is_active=bed.is_active,
        current_resident_id=res.id if res else None,
        current_resident_name=res.full_name if res else None,
        created_at=bed.created_at,
        updated_at=bed.updated_at,
    )


@router.post("", response_model=APIResponse[BedRead], status_code=status.HTTP_201_CREATED, summary="Create Bed")
def create_bed(
    payload: BedCreate,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Adds a new bed to a room."""
    room = db.scalar(sa.select(Room).where(Room.id == payload.room_id))
    if not room:
        raise NotFoundError("Room not found.")
    verify_property_access(room.property_id, current_user, db)

    # Enforce organization-wide 240 bed capacity
    BedCapacityService.assert_can_add_beds_for_room(room.id, 1, db)

    # Check duplicate bed number in this room (non-deleted)
    clean_num = payload.bed_number.strip().upper()
    existing = db.scalar(
        sa.select(Bed).where(
            Bed.room_id == payload.room_id,
            Bed.bed_number == clean_num,
            Bed.is_deleted == False,
        )
    )
    if existing:
        raise ConflictError(f"Bed '{clean_num}' already exists in room '{room.room_number}'.")

    # Prevent over-allocation beyond room capacity
    current_bed_count = db.scalar(
        sa.select(sa.func.count(Bed.id)).where(Bed.room_id == payload.room_id, Bed.is_deleted == False)
    ) or 0
    if current_bed_count >= room.max_occupancy:
        raise BadRequestError(
            f"Cannot add bed. Room '{room.room_number}' already has {current_bed_count} bed(s), "
            f"which meets or exceeds maximum occupancy for room type '{room.room_type}' ({room.max_occupancy})."
        )

    rent = payload.monthly_rent if payload.monthly_rent is not None else float(room.base_monthly_rent or 0.0)

    bed = Bed(
        property_id=room.property_id,
        room_id=room.id,
        bed_number=clean_num,
        status=payload.status.upper() if payload.status else "AVAILABLE",
        monthly_rent=rent,
        is_active=payload.is_active,
    )
    db.add(bed)
    db.commit()
    db.refresh(bed)

    return APIResponse(
        success=True,
        message=f"Bed '{clean_num}' added to room '{room.room_number}'.",
        data=_build_bed_read(bed, db),
    )


@router.post("/bulk", response_model=APIResponse[List[BedRead]], status_code=status.HTTP_201_CREATED, summary="Bulk Create Beds")
def create_beds_bulk(
    payload: BedBulkCreate,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Bulk creates beds in a room, enforcing room capacity and organization bed capacity."""
    room = db.scalar(sa.select(Room).where(Room.id == payload.room_id))
    if not room:
        raise NotFoundError("Room not found.")
    verify_property_access(room.property_id, current_user, db)

    num_beds = len(payload.bed_numbers)
    if num_beds == 0:
        raise BadRequestError("At least one bed number must be provided.")

    # Enforce organization-wide 240 bed capacity
    BedCapacityService.assert_can_add_beds_for_room(room.id, num_beds, db)

    # Check room capacity
    current_bed_count = db.scalar(
        sa.select(sa.func.count(Bed.id)).where(Bed.room_id == payload.room_id, Bed.is_deleted == False)
    ) or 0
    if current_bed_count + num_beds > room.max_occupancy:
        raise BadRequestError(
            f"Cannot add {num_beds} bed(s). Room '{room.room_number}' has {current_bed_count} bed(s), "
            f"and maximum occupancy is {room.max_occupancy}."
        )

    created_beds = []
    rent = payload.monthly_rent if payload.monthly_rent is not None else float(room.base_monthly_rent or 0.0)

    for bnum in payload.bed_numbers:
        clean_num = bnum.strip().upper()
        existing = db.scalar(
            sa.select(Bed).where(
                Bed.room_id == payload.room_id,
                Bed.bed_number == clean_num,
                Bed.is_deleted == False,
            )
        )
        if existing:
            raise ConflictError(f"Bed '{clean_num}' already exists in room '{room.room_number}'.")

        bed = Bed(
            property_id=room.property_id,
            room_id=room.id,
            bed_number=clean_num,
            status=payload.status.upper() if payload.status else "AVAILABLE",
            monthly_rent=rent,
            is_active=payload.is_active,
        )
        db.add(bed)
        created_beds.append(bed)

    db.commit()
    for b in created_beds:
        db.refresh(b)

    return APIResponse(
        success=True,
        message=f"Added {len(created_beds)} beds to room '{room.room_number}'.",
        data=[_build_bed_read(b, db) for b in created_beds],
    )


@router.get("", response_model=APIResponse[List[BedSummary]], status_code=status.HTTP_200_OK, summary="List Beds")
def list_beds(
    room_id: Optional[uuid.UUID] = Query(None, description="Filter by room ID"),
    property_id: Optional[uuid.UUID] = Query(None, description="Filter by property ID"),
    bed_status: Optional[str] = Query(None, alias="status", description="Filter by bed status (AVAILABLE, OCCUPIED, MAINTENANCE)"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Lists beds with optional filters by room, property, and occupancy status (excluding deleted beds)."""
    query = db.query(Bed).filter(Bed.is_deleted == False)
    if room_id:
        room = db.scalar(sa.select(Room).where(Room.id == room_id))
        if room:
            verify_property_access(room.property_id, current_user, db)
        query = query.filter(Bed.room_id == room_id)
    elif property_id:
        verify_property_access(property_id, current_user, db)
        query = query.filter(Bed.property_id == property_id)
    else:
        accessible_props = PropertyService(db).get_accessible_properties(current_user)
        accessible_ids = [p.id for p in accessible_props]
        query = query.filter(Bed.property_id.in_(accessible_ids))

    if bed_status:
        query = query.filter(Bed.status == bed_status.upper())

    beds = query.order_by(Bed.bed_number.asc()).all()

    summaries = []
    for b in beds:
        res = db.query(Resident).filter(Resident.bed_id == b.id, Resident.status == "ACTIVE").first()
        status_val = "OCCUPIED" if res else b.status
        room = db.scalar(sa.select(Room).where(Room.id == b.room_id))
        summaries.append(
            BedSummary(
                id=b.id,
                property_id=b.property_id,
                room_id=b.room_id,
                room_number=room.room_number if room else None,
                bed_number=b.bed_number,
                status=status_val,
                monthly_rent=float(b.monthly_rent) if b.monthly_rent is not None else None,
                is_active=b.is_active,
            )
        )

    return APIResponse(
        success=True,
        message=f"Retrieved {len(summaries)} beds.",
        data=summaries,
    )


@router.get("/rooms/{room_id}/beds", response_model=APIResponse[List[BedSummary]], status_code=status.HTTP_200_OK, summary="List Beds in Room")
def list_beds_by_room_path(
    room_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Direct route to list all beds in a room."""
    return list_beds(room_id=room_id, property_id=None, bed_status=None, current_user=current_user, db=db)


@router.get("/{bed_id}", response_model=APIResponse[BedRead], status_code=status.HTTP_200_OK, summary="Get Bed Details")
def get_bed_details(
    bed_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Returns bed details with current allocated resident if occupied."""
    bed = db.scalar(sa.select(Bed).where(Bed.id == bed_id, Bed.is_deleted == False))
    if not bed:
        raise NotFoundError("Bed not found.")
    verify_property_access(bed.property_id, current_user, db)

    return APIResponse(
        success=True,
        message="Bed details retrieved.",
        data=_build_bed_read(bed, db),
    )


@router.patch("/{bed_id}", response_model=APIResponse[BedRead], status_code=status.HTTP_200_OK, summary="Update Bed")
def update_bed(
    bed_id: uuid.UUID,
    payload: BedUpdate,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Updates bed details, status (MAINTENANCE, AVAILABLE), or monthly rent."""
    bed = db.scalar(sa.select(Bed).where(Bed.id == bed_id, Bed.is_deleted == False))
    if not bed:
        raise NotFoundError("Bed not found.")
    verify_property_access(bed.property_id, current_user, db)

    update_dict = payload.model_dump(exclude_unset=True)
    if "bed_number" in update_dict and update_dict["bed_number"]:
        clean_num = update_dict["bed_number"].strip().upper()
        if clean_num != bed.bed_number:
            existing = db.scalar(
                sa.select(Bed).where(
                    Bed.room_id == bed.room_id,
                    Bed.bed_number == clean_num,
                    Bed.is_deleted == False,
                )
            )
            if existing:
                raise ConflictError(f"Bed '{clean_num}' already exists in this room.")
            bed.bed_number = clean_num
        update_dict.pop("bed_number")

    if "status" in update_dict and update_dict["status"]:
        new_status = update_dict["status"].upper()
        # If trying to mark AVAILABLE but there is an active resident:
        if new_status == "AVAILABLE":
            active_res = db.scalar(sa.select(Resident).where(Resident.bed_id == bed.id, Resident.status == "ACTIVE"))
            if active_res:
                raise BadRequestError(f"Cannot set bed to AVAILABLE: Bed is currently occupied by resident '{active_res.full_name}'.")
        bed.status = new_status
        update_dict.pop("status")

    for f, v in update_dict.items():
        if hasattr(bed, f):
            setattr(bed, f, v)

    db.commit()
    db.refresh(bed)

    return APIResponse(
        success=True,
        message="Bed updated successfully.",
        data=_build_bed_read(bed, db),
    )


@router.delete("/{bed_id}", response_model=APIResponse[dict], status_code=status.HTTP_200_OK, summary="Delete Bed")
def delete_bed(
    bed_id: uuid.UUID,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Soft-deletes a bed if not currently occupied."""
    bed = db.scalar(sa.select(Bed).where(Bed.id == bed_id, Bed.is_deleted == False))
    if not bed:
        raise NotFoundError("Bed not found.")
    verify_property_access(bed.property_id, current_user, db)

    active_res = db.scalar(sa.select(Resident).where(Resident.bed_id == bed.id, Resident.status == "ACTIVE"))
    if active_res:
        raise BadRequestError(f"Cannot delete bed: It is currently occupied by resident '{active_res.full_name}'.")

    bed.is_deleted = True
    bed.is_active = False
    bed.deleted_at = datetime.now(timezone.utc)
    db.commit()

    return APIResponse(
        success=True,
        message=f"Bed '{bed.bed_number}' deleted successfully.",
        data={"bed_id": str(bed_id)},
    )
