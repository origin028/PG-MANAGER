import uuid
from datetime import date, datetime, timezone
from typing import List, Optional
import sqlalchemy as sa
from sqlalchemy.orm import Session, joinedload

from app.core.exceptions import ConflictError, NotFoundError, PermissionDeniedError, ValidationError
from app.models.bed import Bed
from app.models.property import Property
from app.models.resident import Resident
from app.models.room import Room
from app.models.user import User, UserPropertyAccess
from app.schemas.resident import (
    ResidentCheckIn,
    ResidentCheckOut,
    ResidentCreate,
    ResidentDetail,
    ResidentKYCUpdate,
    ResidentOccupancyDetail,
    ResidentRead,
    ResidentUpdate,
    mask_id_proof,
)
from app.services.audit_service import record_audit_log
from app.services.invoice_service import build_initial_rent_invoice


def _get_permitted_property_ids(
    db: Session, user: User, target_property_id: Optional[uuid.UUID] = None
) -> List[uuid.UUID]:
    """
    Returns list of property IDs the user is authorized to view/manage.
    If target_property_id is specified, verifies authorization for it.
    """
    if user.role.name == "RESIDENT":
        raise PermissionDeniedError("Residents are not authorized for administrative resident access.")

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


def _build_resident_detail(resident: Resident) -> ResidentDetail:
    property_name = resident.property.name if resident.property else None
    room_number = resident.room.room_number if resident.room else None
    bed_number = resident.bed.bed_number if resident.bed else None
    floor_number = resident.room.floor_number if resident.room else None

    return ResidentDetail(
        id=resident.id,
        company_id=resident.company_id,
        property_id=resident.property_id,
        room_id=resident.room_id,
        bed_id=resident.bed_id,
        user_id=resident.user_id,
        full_name=resident.full_name,
        phone=resident.phone,
        email=resident.email,
        emergency_contact_name=resident.emergency_contact_name,
        emergency_contact_phone=resident.emergency_contact_phone,
        check_in_date=resident.check_in_date,
        expected_check_out_date=resident.expected_check_out_date,
        actual_check_out_date=resident.actual_check_out_date,
        monthly_rent=float(resident.monthly_rent),
        security_deposit=float(resident.security_deposit),
        status=resident.status,
        kyc_status=resident.kyc_status,
        id_proof_type=resident.id_proof_type,
        id_proof_number_masked=resident.id_proof_number_masked,
        kyc_notes=resident.kyc_notes,
        verified_at=resident.verified_at,
        created_at=resident.created_at,
        updated_at=resident.updated_at,
        property_name=property_name,
        room_number=room_number,
        bed_number=bed_number,
        floor_number=floor_number,
    )


def list_residents(
    db: Session,
    user: User,
    property_id: Optional[uuid.UUID] = None,
    status_filter: Optional[str] = None,
    kyc_status_filter: Optional[str] = None,
    search: Optional[str] = None,
) -> List[ResidentDetail]:
    permitted_ids = _get_permitted_property_ids(db, user, property_id)
    if not permitted_ids:
        return []

    stmt = (
        sa.select(Resident)
        .options(
            joinedload(Resident.property),
            joinedload(Resident.room),
            joinedload(Resident.bed),
        )
        .where(Resident.property_id.in_(permitted_ids))
    )

    if status_filter:
        stmt = stmt.where(Resident.status == status_filter.upper())
    if kyc_status_filter:
        stmt = stmt.where(Resident.kyc_status == kyc_status_filter.upper())
    if search:
        search_term = f"%{search.strip()}%"
        stmt = stmt.where(
            sa.or_(
                Resident.full_name.ilike(search_term),
                Resident.phone.ilike(search_term),
                Resident.email.ilike(search_term),
            )
        )

    stmt = stmt.order_by(Resident.created_at.desc())
    residents = db.scalars(stmt).unique().all()
    return [_build_resident_detail(r) for r in residents]


def get_resident_detail(
    db: Session, resident_id: uuid.UUID, user: User
) -> ResidentDetail:
    stmt = (
        sa.select(Resident)
        .options(
            joinedload(Resident.property),
            joinedload(Resident.room),
            joinedload(Resident.bed),
        )
        .where(Resident.id == resident_id)
    )
    resident = db.scalar(stmt)
    if not resident:
        raise NotFoundError(f"Resident with ID '{resident_id}' not found.")

    # Resident self-access rule
    if user.role.name == "RESIDENT":
        if resident.user_id != user.id and resident.phone != user.phone:
            raise PermissionDeniedError("Residents can only access their own profile and occupancy data.")
        return _build_resident_detail(resident)

    # Admin / Staff scoping
    _get_permitted_property_ids(db, user, resident.property_id)
    return _build_resident_detail(resident)


def create_resident(
    db: Session,
    data: ResidentCreate,
    user: User,
    ip_address: Optional[str] = None,
    user_agent: Optional[str] = None,
) -> ResidentDetail:
    if user.role.name not in ["SUPER_ADMIN", "PROPERTY_MANAGER"]:
        raise PermissionDeniedError("Only Super Admins and Property Managers can create resident admissions.")

    _get_permitted_property_ids(db, user, data.property_id)

    # Conflict check: phone cannot be actively registered in the same property
    existing_active = db.scalar(
        sa.select(Resident).where(
            Resident.property_id == data.property_id,
            Resident.phone == data.phone.strip(),
            Resident.status.in_(["PENDING", "ACTIVE"]),
        )
    )
    if existing_active:
        raise ConflictError(
            f"A resident with phone '{data.phone.strip()}' is already registered as active or pending in this property."
        )

    # Optional bed allocation during admission
    bed: Optional[Bed] = None
    room_id = data.room_id
    if data.bed_id:
        bed = db.scalar(
            sa.select(Bed)
            .where(Bed.id == data.bed_id)
            .with_for_update()
        )
        if not bed:
            raise NotFoundError(f"Bed with ID '{data.bed_id}' not found.")

        # Property invariant check
        if bed.property_id != data.property_id:
            raise ConflictError(
                f"Property mismatch: Bed belongs to property '{bed.property_id}', "
                f"but resident is being admitted to property '{data.property_id}'."
            )

        if not bed.is_active:
            raise ConflictError(f"Bed '{bed.bed_number}' is inactive and cannot be allocated.")
        if bed.status != "AVAILABLE":
            raise ConflictError(f"Bed '{bed.bed_number}' is not available (current status: '{bed.status}').")

        # Concurrency safety check
        existing_bed_resident = db.scalar(
            sa.select(Resident).where(
                Resident.bed_id == bed.id,
                Resident.status == "ACTIVE",
            )
        )
        if existing_bed_resident:
            raise ConflictError(f"Bed '{bed.bed_number}' is already occupied.")

        room_id = bed.room_id

    # Check if a User account already exists with this phone
    linked_user = db.scalar(sa.select(User).where(User.phone == data.phone.strip()))
    user_id = linked_user.id if linked_user else None

    # Mask sensitive identity document before storing
    id_proof_masked = mask_id_proof(data.id_proof_number)

    status_val = "PENDING"
    check_in_date_val = None
    rent_val = data.monthly_rent if data.monthly_rent and data.monthly_rent > 0 else (bed.monthly_rent if bed else 0.00)

    if data.check_in_immediately:
        if not bed:
            raise ValidationError("A valid available bed must be specified to check in immediately.")
        status_val = "ACTIVE"
        check_in_date_val = date.today()
        bed.status = "OCCUPIED"

    resident = Resident(
        company_id=user.company_id,
        property_id=data.property_id,
        room_id=room_id,
        bed_id=bed.id if bed else None,
        user_id=user_id,
        full_name=data.full_name.strip(),
        phone=data.phone.strip(),
        email=data.email.strip().lower() if data.email else None,
        emergency_contact_name=data.emergency_contact_name.strip() if data.emergency_contact_name else None,
        emergency_contact_phone=data.emergency_contact_phone.strip() if data.emergency_contact_phone else None,
        check_in_date=check_in_date_val,
        expected_check_out_date=data.expected_check_out_date,
        monthly_rent=rent_val,
        security_deposit=data.security_deposit or 0.00,
        status=status_val,
        kyc_status="PENDING",
        id_proof_type=data.id_proof_type.upper() if data.id_proof_type else None,
        id_proof_number_masked=id_proof_masked,
        kyc_notes=data.kyc_notes,
    )

    db.add(resident)
    db.flush()
    initial_invoice = (
        build_initial_rent_invoice(db, resident, user, check_in_date_val)
        if check_in_date_val
        else None
    )
    db.commit()
    db.refresh(resident)

    record_audit_log(
        db=db,
        action="RESIDENT_ADMITTED" if status_val == "PENDING" else "RESIDENT_ADMITTED_AND_CHECKED_IN",
        resource_type="resident",
        resource_id=str(resident.id),
        user_id=user.id,
        user_email=user.email,
        user_role=user.role.name,
        company_id=user.company_id,
        property_id=data.property_id,
        details={
            "full_name": resident.full_name,
            "status": resident.status,
            "bed_assigned": bool(resident.bed_id),
            "initial_invoice_number": initial_invoice.invoice_number if initial_invoice else None,
        },
        ip_address=ip_address,
        user_agent=user_agent,
    )

    return get_resident_detail(db=db, resident_id=resident.id, user=user)


def update_resident(
    db: Session,
    resident_id: uuid.UUID,
    data: ResidentUpdate,
    user: User,
    ip_address: Optional[str] = None,
    user_agent: Optional[str] = None,
) -> ResidentDetail:
    if user.role.name not in ["SUPER_ADMIN", "PROPERTY_MANAGER"]:
        raise PermissionDeniedError("Only Super Admins and Property Managers can update resident details.")

    resident = db.scalar(
        sa.select(Resident)
        .where(Resident.id == resident_id)
        .with_for_update()
    )
    if not resident:
        raise NotFoundError(f"Resident with ID '{resident_id}' not found.")

    _get_permitted_property_ids(db, user, resident.property_id)

    if data.full_name is not None:
        resident.full_name = data.full_name.strip()
    if data.email is not None:
        resident.email = data.email.strip().lower() if data.email else None
    if data.emergency_contact_name is not None:
        resident.emergency_contact_name = data.emergency_contact_name.strip()
    if data.emergency_contact_phone is not None:
        resident.emergency_contact_phone = data.emergency_contact_phone.strip()
    if data.expected_check_out_date is not None:
        resident.expected_check_out_date = data.expected_check_out_date
    if data.monthly_rent is not None:
        resident.monthly_rent = data.monthly_rent
    if data.security_deposit is not None:
        resident.security_deposit = data.security_deposit

    db.commit()
    db.refresh(resident)

    record_audit_log(
        db=db,
        action="RESIDENT_UPDATED",
        resource_type="resident",
        resource_id=str(resident.id),
        user_id=user.id,
        user_email=user.email,
        user_role=user.role.name,
        company_id=resident.company_id,
        property_id=resident.property_id,
        details={"full_name": resident.full_name},
        ip_address=ip_address,
        user_agent=user_agent,
    )

    return get_resident_detail(db=db, resident_id=resident.id, user=user)


def check_in_resident(
    db: Session,
    resident_id: uuid.UUID,
    payload: ResidentCheckIn,
    user: User,
    ip_address: Optional[str] = None,
    user_agent: Optional[str] = None,
) -> ResidentDetail:
    """
    Concurrency-safe resident check-in with row locking and status validation.
    """
    if user.role.name not in ["SUPER_ADMIN", "PROPERTY_MANAGER"]:
        raise PermissionDeniedError("Only Super Admins and Property Managers can check in residents.")

    try:
        # 1. Lock bed row for concurrency safety
        bed = db.scalar(
            sa.select(Bed)
            .where(Bed.id == payload.bed_id)
            .with_for_update()
        )
        if not bed:
            raise NotFoundError(f"Bed with ID '{payload.bed_id}' not found.")

        # 2. Lock resident row
        resident = db.scalar(
            sa.select(Resident)
            .where(Resident.id == resident_id)
            .with_for_update()
        )
        if not resident:
            raise NotFoundError(f"Resident with ID '{resident_id}' not found.")

        # Verify property authorization for both entities
        _get_permitted_property_ids(db, user, bed.property_id)
        _get_permitted_property_ids(db, user, resident.property_id)

        # 3. Database invariant check: Bed and Resident must belong to same property
        if bed.property_id != resident.property_id:
            raise ConflictError(
                f"Property mismatch: Resident belongs to property '{resident.property_id}', "
                f"but bed belongs to property '{bed.property_id}'."
            )

        # 4. Bed status check
        if not bed.is_active:
            raise ConflictError(f"Bed '{bed.bed_number}' is inactive and cannot be allocated.")
        if bed.status != "AVAILABLE":
            raise ConflictError(f"Bed '{bed.bed_number}' is not available (current status: '{bed.status}').")

        # 5. Resident status check
        if resident.status == "ACTIVE":
            raise ConflictError("Resident is already active.")
        if resident.status == "CHECKED_OUT":
            raise ConflictError("Resident has already checked out and cannot be re-checked in.")
        if resident.status != "PENDING":
            raise ConflictError(f"Cannot check in resident in '{resident.status}' status.")

        # 6. Verify no other active resident holds this bed
        existing_active = db.scalar(
            sa.select(Resident).where(
                Resident.bed_id == bed.id,
                Resident.status == "ACTIVE",
                Resident.id != resident.id,
            )
        )
        if existing_active:
            raise ConflictError(f"Bed '{bed.bed_number}' is already occupied by resident '{existing_active.full_name}'.")

        # 7. Apply state transition atomically
        bed.status = "OCCUPIED"
        resident.bed_id = bed.id
        resident.room_id = bed.room_id
        resident.status = "ACTIVE"
        resident.check_in_date = payload.check_in_date or date.today()
        if not resident.monthly_rent or resident.monthly_rent <= 0:
            resident.monthly_rent = bed.monthly_rent

        initial_invoice = build_initial_rent_invoice(
            db, resident, user, resident.check_in_date
        )

        db.commit()
        db.refresh(resident)
        db.refresh(bed)

        record_audit_log(
            db=db,
            action="RESIDENT_CHECKED_IN",
            resource_type="resident",
            resource_id=str(resident.id),
            user_id=user.id,
            user_email=user.email,
            user_role=user.role.name,
            company_id=resident.company_id,
            property_id=resident.property_id,
            details={
                "resident_name": resident.full_name,
                "bed_number": bed.bed_number,
                "check_in_date": str(resident.check_in_date),
                "initial_invoice_number": initial_invoice.invoice_number if initial_invoice else None,
            },
            ip_address=ip_address,
            user_agent=user_agent,
        )

        return get_resident_detail(db=db, resident_id=resident.id, user=user)
    except (ConflictError, NotFoundError, PermissionDeniedError, ValidationError):
        raise
    except Exception:
        db.rollback()
        raise


def check_out_resident(
    db: Session,
    resident_id: uuid.UUID,
    payload: ResidentCheckOut,
    user: User,
    ip_address: Optional[str] = None,
    user_agent: Optional[str] = None,
) -> ResidentDetail:
    """
    Concurrency-safe resident checkout and bed release.
    """
    if user.role.name not in ["SUPER_ADMIN", "PROPERTY_MANAGER"]:
        raise PermissionDeniedError("Only Super Admins and Property Managers can check out residents.")

    try:
        # 1. Lock resident row
        resident = db.scalar(
            sa.select(Resident)
            .where(Resident.id == resident_id)
            .with_for_update()
        )
        if not resident:
            raise NotFoundError(f"Resident with ID '{resident_id}' not found.")

        _get_permitted_property_ids(db, user, resident.property_id)

        if resident.status != "ACTIVE":
            raise ConflictError(f"Cannot check out resident in '{resident.status}' status (must be ACTIVE).")

        bed_number = None
        # 2. Lock and release assigned bed
        if resident.bed_id:
            bed = db.scalar(
                sa.select(Bed)
                .where(Bed.id == resident.bed_id)
                .with_for_update()
            )
            if bed:
                bed_number = bed.bed_number
                bed.status = "AVAILABLE"

        # 3. Transition resident status
        resident.status = "CHECKED_OUT"
        resident.actual_check_out_date = payload.actual_check_out_date or date.today()

        db.commit()
        db.refresh(resident)

        record_audit_log(
            db=db,
            action="RESIDENT_CHECKED_OUT",
            resource_type="resident",
            resource_id=str(resident.id),
            user_id=user.id,
            user_email=user.email,
            user_role=user.role.name,
            company_id=resident.company_id,
            property_id=resident.property_id,
            details={
                "resident_name": resident.full_name,
                "bed_number": bed_number,
                "actual_check_out_date": str(resident.actual_check_out_date),
            },
            ip_address=ip_address,
            user_agent=user_agent,
        )

        return get_resident_detail(db=db, resident_id=resident.id, user=user)
    except (ConflictError, NotFoundError, PermissionDeniedError, ValidationError):
        raise
    except Exception:
        db.rollback()
        raise


def update_resident_kyc(
    db: Session,
    resident_id: uuid.UUID,
    payload: ResidentKYCUpdate,
    user: User,
    ip_address: Optional[str] = None,
    user_agent: Optional[str] = None,
) -> ResidentDetail:
    """
    Updates KYC verification status and safe masked metadata without storing or leaking sensitive data.
    """
    if user.role.name not in ["SUPER_ADMIN", "PROPERTY_MANAGER", "STAFF"]:
        raise PermissionDeniedError("You are not authorized to update KYC verification.")

    resident = db.scalar(
        sa.select(Resident)
        .where(Resident.id == resident_id)
        .with_for_update()
    )
    if not resident:
        raise NotFoundError(f"Resident with ID '{resident_id}' not found.")

    _get_permitted_property_ids(db, user, resident.property_id)

    new_kyc_status = payload.kyc_status.upper()
    if new_kyc_status not in ["PENDING", "VERIFIED", "REJECTED"]:
        raise ValidationError(f"Invalid KYC status '{new_kyc_status}'. Must be PENDING, VERIFIED, or REJECTED.")

    resident.kyc_status = new_kyc_status
    if payload.id_proof_type:
        resident.id_proof_type = payload.id_proof_type.upper()
    if payload.id_proof_number:
        resident.id_proof_number_masked = mask_id_proof(payload.id_proof_number)
    if payload.kyc_notes is not None:
        resident.kyc_notes = payload.kyc_notes

    if new_kyc_status == "VERIFIED":
        resident.verified_at = datetime.now(timezone.utc)
        resident.verified_by_id = user.id
    elif new_kyc_status in ["PENDING", "REJECTED"]:
        resident.verified_at = None
        resident.verified_by_id = None

    db.commit()
    db.refresh(resident)

    record_audit_log(
        db=db,
        action="RESIDENT_KYC_UPDATED",
        resource_type="resident",
        resource_id=str(resident.id),
        user_id=user.id,
        user_email=user.email,
        user_role=user.role.name,
        company_id=resident.company_id,
        property_id=resident.property_id,
        details={
            "resident_name": resident.full_name,
            "kyc_status": resident.kyc_status,
            "id_proof_type": resident.id_proof_type,
        },
        ip_address=ip_address,
        user_agent=user_agent,
    )

    return get_resident_detail(db=db, resident_id=resident.id, user=user)


def get_occupancy_detail(
    db: Session, resident_id: uuid.UUID, user: User
) -> ResidentOccupancyDetail:
    """
    Returns resident occupancy breakdown and tenure calculations.
    """
    stmt = (
        sa.select(Resident)
        .options(
            joinedload(Resident.property),
            joinedload(Resident.room),
            joinedload(Resident.bed),
        )
        .where(Resident.id == resident_id)
    )
    resident = db.scalar(stmt)
    if not resident:
        raise NotFoundError(f"Resident with ID '{resident_id}' not found.")

    if user.role.name == "RESIDENT":
        if resident.user_id != user.id and resident.phone != user.phone:
            raise PermissionDeniedError("Residents can only access their own profile and occupancy data.")
    else:
        _get_permitted_property_ids(db, user, resident.property_id)

    tenure_days: Optional[int] = None
    if resident.check_in_date:
        end_date = resident.actual_check_out_date or date.today()
        tenure_days = max(0, (end_date - resident.check_in_date).days)

    return ResidentOccupancyDetail(
        resident_id=resident.id,
        resident_name=resident.full_name,
        property_id=resident.property_id,
        property_name=resident.property.name if resident.property else "Unknown",
        room_id=resident.room_id,
        room_number=resident.room.room_number if resident.room else None,
        bed_id=resident.bed_id,
        bed_number=resident.bed.bed_number if resident.bed else None,
        floor_number=resident.room.floor_number if resident.room else None,
        status=resident.status,
        check_in_date=resident.check_in_date,
        expected_check_out_date=resident.expected_check_out_date,
        actual_check_out_date=resident.actual_check_out_date,
        tenure_days=tenure_days,
        monthly_rent=float(resident.monthly_rent),
        security_deposit=float(resident.security_deposit),
    )
