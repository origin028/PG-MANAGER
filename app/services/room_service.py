import uuid
from typing import List, Optional, Tuple
import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.core.exceptions import ConflictError, NotFoundError, PermissionDeniedError, ValidationError
from app.models.bed import Bed
from app.models.property import Property
from app.models.resident import Resident
from app.models.room import Room
from app.models.user import User, UserPropertyAccess
from app.schemas.bed import BedCreate, BedRead, BedUpdate
from app.schemas.room import RoomCreate, RoomDetail, RoomRead, RoomUpdate
from app.services.audit_service import record_audit_log
from app.services.property_service import check_user_property_access


def _get_permitted_property_ids(db: Session, user: User, target_property_id: Optional[uuid.UUID] = None) -> List[uuid.UUID]:
    """
    Returns list of property IDs the user is authorized to view/manage.
    If target_property_id is specified, verifies authorization for it.
    """
    if user.role.name == "RESIDENT":
        raise PermissionDeniedError("Residents are not authorized to access administrative rooms and beds.")

    if user.role.name == "SUPER_ADMIN":
        if target_property_id:
            prop = db.scalar(
                sa.select(Property).where(
                    Property.id == target_property_id,
                    Property.company_id == user.company_id,
                )
            )
            if not prop:
                raise NotFoundError(f"Property with ID '{target_property_id}' not found.")
            return [target_property_id]
        else:
            props = db.scalars(
                sa.select(Property.id).where(
                    Property.company_id == user.company_id,
                    Property.is_active == True,
                )
            ).all()
            return list(props)

    # For PROPERTY_MANAGER and STAFF
    assigned_query = sa.select(UserPropertyAccess.property_id).where(
        UserPropertyAccess.user_id == user.id
    )
    assigned_ids = list(db.scalars(assigned_query).all())

    if target_property_id:
        if target_property_id not in assigned_ids:
            raise PermissionDeniedError(
                f"You do not have access rights for property ID '{target_property_id}'."
            )
        return [target_property_id]

    return assigned_ids


def _build_room_read(room: Room) -> RoomRead:
    total_beds = len(room.beds) if room.beds else 0
    available_beds = sum(1 for b in room.beds if b.status == "AVAILABLE" and b.is_active) if room.beds else 0
    return RoomRead(
        id=room.id,
        property_id=room.property_id,
        room_number=room.room_number,
        floor_number=room.floor_number,
        room_type=room.room_type,
        base_monthly_rent=float(room.base_monthly_rent),
        deposit_amount=float(room.deposit_amount),
        amenities=room.amenities or [],
        is_active=room.is_active,
        total_beds=total_beds,
        available_beds=available_beds,
        created_at=room.created_at,
        updated_at=room.updated_at,
    )


def list_rooms(
    db: Session,
    user: User,
    property_id: Optional[uuid.UUID] = None,
    floor_number: Optional[int] = None,
    room_type: Optional[str] = None,
    is_active: Optional[bool] = None,
) -> List[RoomRead]:
    permitted_ids = _get_permitted_property_ids(db, user, property_id)
    if not permitted_ids:
        return []

    stmt = sa.select(Room).where(Room.property_id.in_(permitted_ids))

    if floor_number is not None:
        stmt = stmt.where(Room.floor_number == floor_number)
    if room_type:
        stmt = stmt.where(Room.room_type == room_type.upper())
    if is_active is not None:
        stmt = stmt.where(Room.is_active == is_active)

    stmt = stmt.order_by(Room.floor_number.asc(), Room.room_number.asc())
    rooms = db.scalars(stmt).all()
    return [_build_room_read(r) for r in rooms]


def get_room_detail(db: Session, room_id: uuid.UUID, user: User) -> RoomDetail:
    room = db.scalar(sa.select(Room).where(Room.id == room_id))
    if not room:
        raise NotFoundError(f"Room with ID '{room_id}' not found.")

    _get_permitted_property_ids(db, user, room.property_id)

    read_data = _build_room_read(room)
    beds_data = [
        BedRead(
            id=b.id,
            property_id=b.property_id,
            room_id=b.room_id,
            bed_number=b.bed_number,
            monthly_rent=float(b.monthly_rent),
            status=b.status,
            is_active=b.is_active,
            created_at=b.created_at,
            updated_at=b.updated_at,
        )
        for b in room.beds
    ]
    return RoomDetail(**read_data.model_dump(), beds=beds_data)


def create_room(
    db: Session,
    property_id: uuid.UUID,
    data: RoomCreate,
    user: User,
    ip_address: Optional[str] = None,
    user_agent: Optional[str] = None,
) -> RoomRead:
    if user.role.name not in ["SUPER_ADMIN", "PROPERTY_MANAGER"]:
        raise PermissionDeniedError("Only Super Admins and Property Managers can create rooms.")

    _get_permitted_property_ids(db, user, property_id)

    # Check unique room number within property
    existing = db.scalar(
        sa.select(Room).where(
            Room.property_id == property_id,
            Room.room_number == data.room_number.strip(),
        )
    )
    if existing:
        raise ConflictError(
            f"Room '{data.room_number.strip()}' already exists in this property."
        )

    room = Room(
        property_id=property_id,
        room_number=data.room_number.strip(),
        floor_number=data.floor_number,
        room_type=data.room_type.upper(),
        base_monthly_rent=data.base_monthly_rent,
        deposit_amount=data.deposit_amount,
        amenities=data.amenities or [],
        is_active=data.is_active,
    )
    db.add(room)
    db.commit()
    db.refresh(room)

    record_audit_log(
        db=db,
        action="ROOM_CREATED",
        resource_type="room",
        resource_id=str(room.id),
        user_id=user.id,
        user_email=user.email,
        user_role=user.role.name,
        company_id=user.company_id,
        property_id=property_id,
        details={"room_number": room.room_number, "room_type": room.room_type},
        ip_address=ip_address,
        user_agent=user_agent,
    )

    return _build_room_read(room)


def update_room(
    db: Session,
    room_id: uuid.UUID,
    data: RoomUpdate,
    user: User,
    ip_address: Optional[str] = None,
    user_agent: Optional[str] = None,
) -> RoomRead:
    if user.role.name not in ["SUPER_ADMIN", "PROPERTY_MANAGER"]:
        raise PermissionDeniedError("Only Super Admins and Property Managers can update rooms.")

    room = db.scalar(sa.select(Room).where(Room.id == room_id))
    if not room:
        raise NotFoundError(f"Room with ID '{room_id}' not found.")

    _get_permitted_property_ids(db, user, room.property_id)

    if data.room_number and data.room_number.strip() != room.room_number:
        existing = db.scalar(
            sa.select(Room).where(
                Room.property_id == room.property_id,
                Room.room_number == data.room_number.strip(),
                Room.id != room.id,
            )
        )
        if existing:
            raise ConflictError(
                f"Room '{data.room_number.strip()}' already exists in this property."
            )
        room.room_number = data.room_number.strip()

    if data.floor_number is not None:
        room.floor_number = data.floor_number
    if data.room_type:
        room.room_type = data.room_type.upper()
    if data.base_monthly_rent is not None:
        room.base_monthly_rent = data.base_monthly_rent
    if data.deposit_amount is not None:
        room.deposit_amount = data.deposit_amount
    if data.amenities is not None:
        room.amenities = data.amenities
    if data.is_active is not None:
        room.is_active = data.is_active

    db.commit()
    db.refresh(room)

    record_audit_log(
        db=db,
        action="ROOM_UPDATED",
        resource_type="room",
        resource_id=str(room.id),
        user_id=user.id,
        user_email=user.email,
        user_role=user.role.name,
        company_id=user.company_id,
        property_id=room.property_id,
        details={"room_number": room.room_number},
        ip_address=ip_address,
        user_agent=user_agent,
    )

    return _build_room_read(room)


def list_beds(
    db: Session,
    user: User,
    property_id: Optional[uuid.UUID] = None,
    room_id: Optional[uuid.UUID] = None,
    status: Optional[str] = None,
    is_active: Optional[bool] = None,
) -> List[BedRead]:
    permitted_ids = _get_permitted_property_ids(db, user, property_id)
    if not permitted_ids:
        return []

    stmt = sa.select(Bed).where(Bed.property_id.in_(permitted_ids))

    if room_id:
        room = db.scalar(sa.select(Room).where(Room.id == room_id))
        if not room:
            raise NotFoundError(f"Room with ID '{room_id}' not found.")
        _get_permitted_property_ids(db, user, room.property_id)
        stmt = stmt.where(Bed.room_id == room_id)
    if status:
        stmt = stmt.where(Bed.status == status.upper())
    if is_active is not None:
        stmt = stmt.where(Bed.is_active == is_active)

    stmt = stmt.order_by(Bed.bed_number.asc())
    beds = db.scalars(stmt).all()
    return [
        BedRead(
            id=b.id,
            property_id=b.property_id,
            room_id=b.room_id,
            bed_number=b.bed_number,
            monthly_rent=float(b.monthly_rent),
            status=b.status,
            is_active=b.is_active,
            created_at=b.created_at,
            updated_at=b.updated_at,
        )
        for b in beds
    ]


def get_bed_detail(db: Session, bed_id: uuid.UUID, user: User) -> BedRead:
    bed = db.scalar(sa.select(Bed).where(Bed.id == bed_id))
    if not bed:
        raise NotFoundError(f"Bed with ID '{bed_id}' not found.")

    _get_permitted_property_ids(db, user, bed.property_id)

    return BedRead(
        id=bed.id,
        property_id=bed.property_id,
        room_id=bed.room_id,
        bed_number=bed.bed_number,
        monthly_rent=float(bed.monthly_rent),
        status=bed.status,
        is_active=bed.is_active,
        created_at=bed.created_at,
        updated_at=bed.updated_at,
    )


def create_bed(
    db: Session,
    room_id: uuid.UUID,
    data: BedCreate,
    user: User,
    ip_address: Optional[str] = None,
    user_agent: Optional[str] = None,
) -> BedRead:
    if user.role.name not in ["SUPER_ADMIN", "PROPERTY_MANAGER"]:
        raise PermissionDeniedError("Only Super Admins and Property Managers can add beds.")

    room = db.scalar(sa.select(Room).where(Room.id == room_id))
    if not room:
        raise NotFoundError(f"Room with ID '{room_id}' not found.")

    _get_permitted_property_ids(db, user, room.property_id)

    # Check unique bed number in this room
    existing = db.scalar(
        sa.select(Bed).where(
            Bed.room_id == room_id,
            Bed.bed_number == data.bed_number.strip(),
        )
    )
    if existing:
        raise ConflictError(
            f"Bed '{data.bed_number.strip()}' already exists in room '{room.room_number}'."
        )

    bed = Bed(
        property_id=room.property_id,
        room_id=room_id,
        bed_number=data.bed_number.strip(),
        monthly_rent=data.monthly_rent if data.monthly_rent > 0 else room.base_monthly_rent,
        status=data.status.upper(),
        is_active=data.is_active,
    )
    db.add(bed)
    db.commit()
    db.refresh(bed)

    record_audit_log(
        db=db,
        action="BED_CREATED",
        resource_type="bed",
        resource_id=str(bed.id),
        user_id=user.id,
        user_email=user.email,
        user_role=user.role.name,
        company_id=user.company_id,
        property_id=room.property_id,
        details={"room_number": room.room_number, "bed_number": bed.bed_number, "status": bed.status},
        ip_address=ip_address,
        user_agent=user_agent,
    )

    return BedRead(
        id=bed.id,
        property_id=bed.property_id,
        room_id=bed.room_id,
        bed_number=bed.bed_number,
        monthly_rent=float(bed.monthly_rent),
        status=bed.status,
        is_active=bed.is_active,
        created_at=bed.created_at,
        updated_at=bed.updated_at,
    )


def update_bed_status(
    db: Session,
    bed_id: uuid.UUID,
    new_status: str,
    user: User,
    ip_address: Optional[str] = None,
    user_agent: Optional[str] = None,
    room_id: Optional[uuid.UUID] = None,
) -> BedRead:
    if user.role.name not in ["SUPER_ADMIN", "PROPERTY_MANAGER", "STAFF"]:
        raise PermissionDeniedError("You are not authorized to update bed status.")

    bed = db.scalar(sa.select(Bed).where(Bed.id == bed_id))
    if not bed:
        raise NotFoundError(f"Bed with ID '{bed_id}' not found.")

    # When addressed through a room, the bed must belong to that room.
    if room_id is not None and bed.room_id != room_id:
        raise NotFoundError(f"Bed with ID '{bed_id}' not found in room '{room_id}'.")

    _get_permitted_property_ids(db, user, bed.property_id)

    new_status = new_status.upper()
    if new_status not in ["AVAILABLE", "OCCUPIED", "RESERVED", "MAINTENANCE"]:
        raise ValidationError(f"Invalid bed status '{new_status}'.")

    # Business rule: an OCCUPIED bed cannot be manually reset to AVAILABLE without formal check-out/vacating
    if bed.status == "OCCUPIED" and new_status == "AVAILABLE":
        raise ValidationError("An occupied bed cannot be manually marked available without resident check-out.")

    # Occupancy is an outcome of the resident check-in flow, never a manual edit.
    if new_status == "OCCUPIED" and bed.status != "OCCUPIED":
        raise ValidationError(
            "A bed cannot be marked OCCUPIED manually. Use the resident check-in endpoint to allocate it."
        )

    if not bed.is_active and new_status != "MAINTENANCE":
        raise ValidationError("An inactive bed can only be moved to MAINTENANCE status.")

    # A bed with an active resident allocation cannot be marked AVAILABLE or MAINTENANCE
    active_resident = db.scalar(
        sa.select(Resident).where(
            Resident.bed_id == bed.id,
            Resident.status == "ACTIVE",
        )
    )
    if active_resident and new_status in ["AVAILABLE", "MAINTENANCE", "RESERVED"]:
        raise ValidationError("Bed has an active resident allocation and cannot change status without resident check-out.")

    old_status = bed.status
    bed.status = new_status
    db.commit()
    db.refresh(bed)

    record_audit_log(
        db=db,
        action="BED_STATUS_UPDATED",
        resource_type="bed",
        resource_id=str(bed.id),
        user_id=user.id,
        user_email=user.email,
        user_role=user.role.name,
        company_id=user.company_id,
        property_id=bed.property_id,
        details={"old_status": old_status, "new_status": new_status, "bed_number": bed.bed_number},
        ip_address=ip_address,
        user_agent=user_agent,
    )

    return BedRead(
        id=bed.id,
        property_id=bed.property_id,
        room_id=bed.room_id,
        bed_number=bed.bed_number,
        monthly_rent=float(bed.monthly_rent),
        status=bed.status,
        is_active=bed.is_active,
        created_at=bed.created_at,
        updated_at=bed.updated_at,
    )
