from datetime import date, datetime, timezone
from decimal import Decimal
import mimetypes
from pathlib import Path
import secrets
from typing import List, Optional
import uuid
from fastapi import APIRouter, Depends, Query, status
from fastapi.responses import FileResponse
import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.core.exceptions import BadRequestError, ConflictError, NotFoundError, PermissionDeniedError
from app.core.security import get_password_hash
from app.dependencies import get_current_user, get_db, require_roles, verify_property_access
from app.models.bed import Bed
from app.models.invoice import Invoice
from app.models.property import Property
from app.models.resident import Resident
from app.models.role import Role
from app.models.room import Room
from app.models.user import User
from app.repositories.resident_repository import ResidentRepository
from app.schemas.common import APIResponse, PaginatedData
from app.schemas.resident import (
    AdminResidentOnboardRequest,
    KYCActionRequest,
    ResidentCheckoutRequest,
    ResidentCheckoutResponse,
    ResidentDetailRead,
    ResidentProfileMeRead,
    ResidentRead,
    ResidentSummary,
    ResidentUpdateRequest,
)
from app.schemas.resident_registration import (
    PendingResidentApprovalItem,
    ResidentApprovalActionRequest,
    ResidentRejectionActionRequest,
)
from app.services.otp_service import normalize_phone
from app.services.property_service import PropertyService


def mask_kyc_number(num: Optional[str]) -> Optional[str]:
    if not num:
        return None
    clean = str(num).strip()
    if len(clean) >= 4:
        return "X" * (len(clean) - 4) + clean[-4:]
    return "****"


def _build_resident_detail(resident: Resident, db: Session) -> ResidentDetailRead:
    user = db.get(User, resident.user_id) if resident.user_id else None
    prop = db.get(Property, resident.property_id) if resident.property_id else None
    room = db.get(Room, resident.room_id) if resident.room_id else None
    bed = db.get(Bed, resident.bed_id) if resident.bed_id else None

    addr_parts = [
        resident.house_flat_no,
        resident.street,
        resident.landmark,
        resident.city,
        resident.state,
    ]
    perm_addr = ", ".join(p for p in addr_parts if p) or None

    return ResidentDetailRead(
        id=resident.id,
        user_id=resident.user_id,
        full_name=resident.full_name or (user.full_name if user else None),
        phone=resident.phone or (user.phone if user else None),
        email=resident.email or (user.email if user else None),
        property_id=resident.property_id,
        property_name=prop.name if prop else None,
        room_id=resident.room_id,
        room_number=room.room_number if room else None,
        bed_id=resident.bed_id,
        bed_number=bed.bed_number if bed else None,
        check_in_date=resident.check_in_date,
        expected_check_out_date=resident.expected_check_out_date,
        actual_check_out_date=resident.actual_check_out_date,
        monthly_rent=float(resident.monthly_rent or 0.0),
        security_deposit=float(resident.security_deposit or 0.0),
        status=resident.status,
        kyc_status=resident.kyc_status or "PENDING",
        id_proof_type=resident.id_proof_type,
        id_proof_number_masked=resident.id_proof_number_masked,
        kyc_document_type=resident.id_proof_type,
        kyc_document_number=resident.id_proof_number_masked,
        date_of_birth=resident.date_of_birth,
        gender=resident.gender,
        occupation=resident.occupation,
        emergency_contact_name=resident.emergency_contact_name or resident.emergency_contact,
        emergency_contact_phone=resident.emergency_contact_phone,
        permanent_address=perm_addr,
        pincode=resident.pincode,
        verified_at=getattr(resident, "verified_at", None),
        created_at=resident.created_at,
        updated_at=resident.updated_at,
    )

router = APIRouter()


@router.get("/me", response_model=APIResponse[ResidentProfileMeRead], status_code=status.HTTP_200_OK)
def get_resident_profile_me(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Retrieves the authenticated resident's profile and allocated stay details."""
    resident = db.scalar(
        sa.select(Resident).where(Resident.user_id == current_user.id)
    )
    if not resident:
        raise NotFoundError("Resident profile not found for this account.")

    property_record = db.get(Property, resident.property_id)
    room_record = db.get(Room, resident.room_id) if resident.room_id else None
    bed_record = db.get(Bed, resident.bed_id) if resident.bed_id else None

    profile_data = ResidentProfileMeRead(
        resident_id=resident.id,
        user_id=current_user.id,
        full_name=current_user.full_name,
        phone=current_user.phone,
        email=current_user.email,
        property_id=resident.property_id,
        property_name=property_record.name if property_record else "Unknown Property",
        property_address=property_record.address_line1 if property_record else None,
        room_id=resident.room_id,
        room_number=room_record.room_number if room_record else None,
        bed_id=resident.bed_id,
        bed_number=bed_record.bed_number if bed_record else None,
        check_in_date=resident.check_in_date,
        expected_check_out_date=resident.expected_check_out_date,
        monthly_rent=float(resident.monthly_rent),
        security_deposit=float(resident.security_deposit),
        kyc_status=resident.kyc_status,
        status=resident.status,
        approval_status=getattr(current_user, "approval_status", "APPROVED"),
    )

    return APIResponse(
        success=True,
        message="Resident profile retrieved successfully.",
        data=profile_data,
    )


@router.post("", response_model=APIResponse[ResidentDetailRead], status_code=status.HTTP_201_CREATED, summary="Manually Onboard Resident")
def onboard_resident(
    payload: AdminResidentOnboardRequest,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """
    Manually onboards a resident into a PG property.
    Creates both User account and Resident profile, assigns room and bed atomically.
    """
    verify_property_access(payload.property_id, current_user, db)

    clean_phone = normalize_phone(payload.phone)
    clean_email = payload.email.strip().lower() if payload.email else None

    # Check duplicate phone
    existing_phone = db.scalar(sa.select(User).where(User.phone == clean_phone))
    if existing_phone:
        raise ConflictError(f"A user with phone number '{clean_phone}' already exists.")

    if clean_email:
        existing_email = db.scalar(sa.select(User).where(User.email == clean_email))
        if existing_email:
            raise ConflictError(f"A user with email '{clean_email}' already exists.")

    # Room and Bed validation & atomic allocation
    room_id = payload.room_id
    bed = None
    if payload.bed_id:
        bed = db.scalar(sa.select(Bed).where(Bed.id == payload.bed_id).with_for_update())
        if not bed:
            raise NotFoundError("Specified bed not found.")
        if bed.property_id != payload.property_id:
            raise BadRequestError("Bed does not belong to the selected property.")

        occ = db.scalar(sa.select(Resident).where(Resident.bed_id == bed.id, Resident.status == "ACTIVE"))
        if occ or bed.status != "AVAILABLE":
            raise ConflictError(f"Bed '{bed.bed_number}' is already occupied or unavailable.")

        bed.status = "OCCUPIED"
        room_id = bed.room_id
    elif payload.room_id:
        room = db.scalar(sa.select(Room).where(Room.id == payload.room_id))
        if not room:
            raise NotFoundError("Specified room not found.")
        if room.property_id != payload.property_id:
            raise BadRequestError("Room does not belong to the selected property.")

    # Get Resident Role
    resident_role = db.scalar(sa.select(Role).where(Role.name == "RESIDENT"))
    if not resident_role:
        resident_role = Role(name="RESIDENT", display_name="Resident")
        db.add(resident_role)
        db.flush()

    init_password = secrets.token_urlsafe(16)
    user = User(
        company_id=current_user.company_id,
        role_id=resident_role.id,
        full_name=payload.full_name.strip(),
        phone=clean_phone,
        email=clean_email,
        password_hash=get_password_hash(init_password),
        is_active=True,
        is_verified=True,
        approval_status="APPROVED",
    )
    db.add(user)
    db.flush()

    masked_doc = mask_kyc_number(payload.id_proof_number or payload.pan_number)
    rent_val = payload.monthly_rent if payload.monthly_rent is not None else (float(bed.monthly_rent) if bed and bed.monthly_rent else 0.0)

    resident = Resident(
        property_id=payload.property_id,
        room_id=room_id,
        bed_id=payload.bed_id,
        user_id=user.id,
        full_name=payload.full_name.strip(),
        phone=clean_phone,
        email=clean_email,
        date_of_birth=payload.date_of_birth,
        gender=payload.gender,
        occupation=payload.occupation,
        emergency_contact_name=payload.emergency_contact_name,
        emergency_contact_phone=payload.emergency_contact_phone,
        house_flat_no=payload.house_flat_no,
        street=payload.street,
        landmark=payload.landmark,
        city=payload.city,
        state=payload.state,
        pincode=payload.pincode,
        check_in_date=payload.check_in_date or date.today(),
        monthly_rent=rent_val,
        security_deposit=payload.security_deposit or 0.00,
        status="ACTIVE",
        kyc_status="PENDING",
        id_proof_type=payload.id_proof_type,
        id_proof_number_masked=masked_doc,
    )
    db.add(resident)
    db.commit()
    db.refresh(resident)

    return APIResponse(
        success=True,
        message=f"Resident '{resident.full_name}' successfully onboarded.",
        data=_build_resident_detail(resident, db),
    )


@router.get("", response_model=APIResponse[PaginatedData[ResidentSummary]], status_code=status.HTTP_200_OK, summary="List Residents")
def list_residents(
    property_id: Optional[uuid.UUID] = Query(None, description="Property ID filter"),
    status: Optional[str] = Query(None, description="Resident status filter (ACTIVE, NOTICE_PERIOD, CHECKED_OUT)"),
    kyc_status: Optional[str] = Query(None, description="KYC status filter (PENDING, VERIFIED, REJECTED)"),
    search: Optional[str] = Query(None, description="Search by resident name or phone"),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Lists residents across one or all accessible properties with pagination and filtering."""
    query = sa.select(Resident)
    if property_id:
        verify_property_access(property_id, current_user, db)
        query = query.where(Resident.property_id == property_id)
    else:
        accessible_props = PropertyService(db).get_accessible_properties(current_user)
        accessible_ids = [p.id for p in accessible_props]
        query = query.where(Resident.property_id.in_(accessible_ids))

    if status:
        query = query.where(Resident.status == status.upper())
    if kyc_status:
        query = query.where(Resident.kyc_status == kyc_status.upper())
    if search:
        s_clean = f"%{search.strip()}%"
        query = query.where(
            sa.or_(
                Resident.full_name.ilike(s_clean),
                Resident.phone.ilike(s_clean),
            )
        )

    total = db.scalar(sa.select(sa.func.count()).select_from(query.subquery())) or 0
    offset = (page - 1) * page_size
    residents = db.scalars(
        query.order_by(Resident.created_at.desc()).offset(offset).limit(page_size)
    ).all()

    summaries = []
    for r in residents:
        user = db.get(User, r.user_id) if r.user_id else None
        room = db.get(Room, r.room_id) if r.room_id else None
        bed = db.get(Bed, r.bed_id) if r.bed_id else None
        summaries.append(
            ResidentSummary(
                id=r.id,
                user_id=r.user_id,
                property_id=r.property_id,
                full_name=r.full_name or (user.full_name if user else None),
                phone=r.phone or (user.phone if user else None),
                room_number=room.room_number if room else None,
                bed_number=bed.bed_number if bed else None,
                check_in_date=r.check_in_date,
                kyc_status=r.kyc_status or "PENDING",
                status=r.status,
                approval_status=user.approval_status if user else "APPROVED",
            )
        )

    total_pages = (total + page_size - 1) // page_size if total > 0 else 1

    return APIResponse(
        success=True,
        message=f"Retrieved {len(summaries)} residents.",
        data=PaginatedData(
            items=summaries,
            total=total,
            page=page,
            page_size=page_size,
            total_pages=total_pages,
        ),
    )


@router.get(
    "/pending-approvals",
    response_model=APIResponse[PaginatedData[PendingResidentApprovalItem]],
    status_code=status.HTTP_200_OK,
)
def list_pending_resident_approvals(
    property_id: Optional[uuid.UUID] = Query(None, description="Filter by property ID"),
    search: Optional[str] = Query(None, description="Search by resident name, phone or email"),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    current_user: User = Depends(require_roles("SUPER_ADMIN", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """
    Lists resident registrations waiting for administrator approval.
    Enforces property access control for property managers and company boundary for owners.
    """
    query = (
        sa.select(Resident, User, Property)
        .join(User, Resident.user_id == User.id)
        .join(Property, Resident.property_id == Property.id)
        .where(
            Resident.status == "PENDING_APPROVAL",
            User.approval_status == "PENDING_APPROVAL",
            Property.company_id == current_user.company_id,
        )
    )

    if current_user.role.name != "SUPER_ADMIN":
        from app.models.user import UserPropertyAccess
        has_specific_access = db.query(UserPropertyAccess).filter_by(user_id=current_user.id).first() is not None
        if has_specific_access:
            accessible_prop_ids = db.scalars(
                sa.select(UserPropertyAccess.property_id).where(UserPropertyAccess.user_id == current_user.id)
            ).all()
            query = query.where(Resident.property_id.in_(accessible_prop_ids))

    if property_id:
        verify_property_access(property_id, current_user, db)
        query = query.where(Resident.property_id == property_id)

    if search and search.strip():
        s = f"%{search.strip().lower()}%"
        query = query.where(
            sa.or_(
                sa.func.lower(User.full_name).ilike(s),
                sa.func.lower(User.email).ilike(s),
                User.phone.ilike(s),
            )
        )

    total = db.scalar(sa.select(sa.func.count()).select_from(query.subquery())) or 0
    offset = (page - 1) * page_size
    records = db.execute(
        query.order_by(Resident.created_at.desc()).offset(offset).limit(page_size)
    ).all()

    items = [
        PendingResidentApprovalItem(
            resident_id=r.id,
            user_id=u.id,
            full_name=u.full_name,
            phone=u.phone,
            email=u.email,
            property_id=p.id,
            property_name=p.name,
            status=r.status,
            approval_status=u.approval_status,
            registered_at=r.created_at,
            date_of_birth=r.date_of_birth,
            gender=r.gender,
            occupation=r.occupation,
            emergency_contact=r.emergency_contact,
            house_flat_no=r.house_flat_no,
            street=r.street,
            landmark=r.landmark,
            city=r.city,
            state=r.state,
            pincode=r.pincode,
            verification_method=r.verification_method,
            aadhaar_front_path=f"/api/v1/residents/{r.id}/kyc-document/aadhaar_front" if r.aadhaar_front_path else None,
            aadhaar_back_path=f"/api/v1/residents/{r.id}/kyc-document/aadhaar_back" if r.aadhaar_back_path else None,
            pan_card_path=f"/api/v1/residents/{r.id}/kyc-document/pan_card" if r.pan_card_path else None,
            passport_path=f"/api/v1/residents/{r.id}/kyc-document/passport" if r.passport_path else None,
            resident_selfie_path=f"/api/v1/residents/{r.id}/kyc-document/resident_selfie" if r.resident_selfie_path else None,
        )
        for r, u, p in records
    ]
    total_pages = (total + page_size - 1) // page_size if total > 0 else 1

    return APIResponse(
        success=True,
        message=f"Retrieved {len(items)} pending resident approvals.",
        data=PaginatedData(
            items=items,
            total=total,
            page=page,
            page_size=page_size,
            total_pages=total_pages,
        ),
    )


@router.post(
    "/{resident_id}/approve",
    response_model=APIResponse[ResidentRead],
    status_code=status.HTTP_200_OK,
)
def approve_resident_registration(
    resident_id: uuid.UUID,
    payload: ResidentApprovalActionRequest,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """
    Approves a pending resident registration, activating both User and Resident accounts.
    Enforces admin authorization, property access boundaries, self-approval prevention,
    and optional room/bed assignment.
    """
    from app.services.audit_service import record_audit_log

    resident = db.get(Resident, resident_id)
    if not resident:
        raise NotFoundError("Resident record not found.")

    # Property authorization check
    verify_property_access(resident.property_id, current_user, db)

    # Self-approval check
    if resident.user_id == current_user.id:
        raise PermissionDeniedError("Administrators cannot approve their own resident registrations.")

    # State validation
    if resident.status != "PENDING_APPROVAL":
        raise BadRequestError(
            f"Resident is not pending approval (current status: '{resident.status}')."
        )

    user = db.get(User, resident.user_id)
    if not user:
        raise NotFoundError("User record linked to resident not found.")

    # Handle optional room/bed allocation
    if payload.bed_id:
        # Use SELECT ... FOR UPDATE to serialize concurrent approvals competing for the same bed
        bed = db.scalar(
            sa.select(Bed).where(Bed.id == payload.bed_id).with_for_update()
        )
        if not bed:
            raise NotFoundError("Specified bed not found.")

        bed_room = db.get(Room, bed.room_id)
        if not bed_room:
            raise NotFoundError("Room associated with the specified bed not found.")

        if bed_room.property_id != resident.property_id:
            raise BadRequestError("Specified bed does not belong to this property.")

        if payload.room_id and payload.room_id != bed.room_id:
            raise BadRequestError("Specified bed does not belong to the selected room.")

        # Check bed occupancy: active resident allocation or non-available status
        occupied = db.scalar(
            sa.select(Resident).where(
                Resident.bed_id == payload.bed_id,
                Resident.status == "ACTIVE",
                Resident.id != resident.id,
            )
        )
        if occupied or bed.status != "AVAILABLE":
            raise ConflictError("The selected bed is already occupied by another active resident.")

        resident.room_id = bed.room_id
        resident.bed_id = bed.id
        bed.status = "OCCUPIED"

    elif payload.room_id:
        room = db.get(Room, payload.room_id)
        if not room:
            raise NotFoundError("Specified room not found.")
        if room.property_id != resident.property_id:
            raise BadRequestError("Specified room does not belong to this property.")
        resident.room_id = room.id

    if payload.monthly_rent is not None:
        resident.monthly_rent = payload.monthly_rent
    if payload.security_deposit is not None:
        resident.security_deposit = payload.security_deposit
    if payload.check_in_date is not None:
        resident.check_in_date = payload.check_in_date

    # Transition states atomically
    resident.status = "ACTIVE"
    resident.kyc_status = "VERIFIED"
    resident.verified_by_id = current_user.id
    resident.verified_at = datetime.now(timezone.utc)
    user.approval_status = "APPROVED"
    user.is_active = True
    user.is_verified = True

    try:
        db.commit()
    except sa.exc.IntegrityError as exc:
        db.rollback()
        err_msg = str(exc.orig if hasattr(exc, "orig") else exc).lower()
        if "ix_residents_bed_id" in err_msg or "uq_active_resident_bed" in err_msg or "bed_id" in err_msg:
            raise ConflictError("The selected bed is already occupied by another active resident.") from exc
        if "ix_residents_user_id" in err_msg or "user_id" in err_msg:
            raise ConflictError("This resident user account is already active or assigned.") from exc
        raise
    db.refresh(resident)
    db.refresh(user)

    # Audit log
    record_audit_log(
        db=db,
        action="RESIDENT_REGISTRATION_APPROVED",
        resource_type="resident",
        user_id=current_user.id,
        user_email=current_user.email,
        user_role=current_user.role.name,
        company_id=current_user.company_id,
        property_id=resident.property_id,
        resource_id=str(resident.id),
        details={
            "resident_user_id": str(resident.user_id),
            "resident_phone": user.phone,
            "room_id": str(resident.room_id) if resident.room_id else None,
            "bed_id": str(resident.bed_id) if resident.bed_id else None,
            "acting_admin": current_user.email,
        },
    )

    # Notifications (in-app and email) - fail-safe
    from app.services.notification_service import NotificationService
    from app.services.email_service import EmailService
    from app.core.logging import logger

    prop = db.get(Property, resident.property_id)
    prop_name = prop.name if prop else "PG Property"

    room_name = None
    if resident.room_id:
        r_obj = db.get(Room, resident.room_id)
        if r_obj:
            room_name = r_obj.room_number

    bed_name = None
    if resident.bed_id:
        b_obj = db.get(Bed, resident.bed_id)
        if b_obj:
            bed_name = b_obj.bed_number

    try:
        NotificationService(db).dispatch(
            user_id=user.id,
            title="Registration Approved",
            body=f"Your registration for {prop_name} has been approved. You can now log in using your registered phone number and email OTP.",
            channel="IN_APP",
        )
    except Exception as err:
        logger.warning(f"Failed to queue in-app approval notification for user {user.id}: {err}")

    if user.email:
        try:
            EmailService().send_resident_approval_notification(
                to_email=user.email,
                resident_name=user.full_name,
                property_name=prop_name,
                room_number=room_name,
                bed_number=bed_name,
            )
        except Exception as err:
            logger.warning(f"Failed to send approval email to {user.email}: {err}")

    return APIResponse(
        success=True,
        message="Resident registration approved successfully.",
        data=ResidentRead.model_validate(resident),
    )


@router.post(
    "/{resident_id}/reject",
    response_model=APIResponse[dict],
    status_code=status.HTTP_200_OK,
)
def reject_resident_registration(
    resident_id: uuid.UUID,
    payload: ResidentRejectionActionRequest,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """
    Rejects a pending resident registration. Deactivates user account and logs reason.
    """
    from app.services.audit_service import record_audit_log

    if not payload.reason or not payload.reason.strip():
        raise BadRequestError("A non-empty rejection reason is required.")

    resident = db.get(Resident, resident_id)
    if not resident:
        raise NotFoundError("Resident record not found.")

    verify_property_access(resident.property_id, current_user, db)

    if resident.user_id == current_user.id:
        raise PermissionDeniedError("Administrators cannot reject their own accounts.")

    if resident.status != "PENDING_APPROVAL":
        raise BadRequestError(
            f"Resident is not pending approval (current status: '{resident.status}')."
        )

    user = db.get(User, resident.user_id)
    if not user:
        raise NotFoundError("User record linked to resident not found.")

    resident.status = "REJECTED"
    resident.kyc_status = "REJECTED"
    resident.kyc_notes = payload.reason.strip()
    resident.verified_by_id = current_user.id
    resident.verified_at = datetime.now(timezone.utc)
    user.approval_status = "REJECTED"
    user.is_active = False

    db.commit()
    db.refresh(resident)
    db.refresh(user)

    # Audit log with safe rejection reason
    record_audit_log(
        db=db,
        action="RESIDENT_REGISTRATION_REJECTED",
        resource_type="resident",
        user_id=current_user.id,
        user_email=current_user.email,
        user_role=current_user.role.name,
        company_id=current_user.company_id,
        property_id=resident.property_id,
        resource_id=str(resident.id),
        details={
            "resident_user_id": str(resident.user_id),
            "reason": payload.reason.strip(),
            "acting_admin": current_user.email,
        },
    )

    # Notifications (in-app and email) - fail-safe
    from app.services.notification_service import NotificationService
    from app.services.email_service import EmailService
    from app.core.logging import logger

    prop = db.get(Property, resident.property_id)
    prop_name = prop.name if prop else "PG Property"

    try:
        NotificationService(db).dispatch(
            user_id=user.id,
            title="Registration Update",
            body=f"Your registration for {prop_name} was rejected: {payload.reason.strip()}",
            channel="IN_APP",
        )
    except Exception as err:
        logger.warning(f"Failed to queue in-app rejection notification for user {user.id}: {err}")

    if user.email:
        try:
            EmailService().send_resident_rejection_notification(
                to_email=user.email,
                resident_name=user.full_name,
                property_name=prop_name,
                reason=payload.reason.strip(),
            )
        except Exception as err:
            logger.warning(f"Failed to send rejection email to {user.email}: {err}")

    return APIResponse(
        success=True,
        message="Resident registration rejected successfully.",
        data={
            "resident_id": str(resident.id),
            "status": "REJECTED",
            "approval_status": "REJECTED",
            "kyc_status": "REJECTED",
            "reason": payload.reason.strip(),
        },
    )



@router.post(
    "/{resident_id}/checkout",
    response_model=APIResponse[ResidentCheckoutResponse],
    status_code=status.HTTP_200_OK,
)
def checkout_resident(
    resident_id: uuid.UUID,
    payload: ResidentCheckoutRequest,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """
    Settles and checks out an active resident.
    Reconciles outstanding invoices against security deposit, releases allocated bed,
    and transitions resident status to CHECKED_OUT.
    """
    from datetime import date
    from app.services.audit_service import record_audit_log

    resident = db.scalar(
        sa.select(Resident).where(Resident.id == resident_id).with_for_update()
    )
    if not resident:
        raise NotFoundError("Resident record not found.")

    verify_property_access(resident.property_id, current_user, db)

    if resident.status == "CHECKED_OUT":
        raise BadRequestError("Resident has already been checked out.")

    # 1. Sum unpaid invoice balances
    unpaid_invoices = db.scalars(
        sa.select(Invoice).where(
            Invoice.resident_id == resident.id,
            Invoice.status.in_(("PENDING", "PARTIALLY_PAID")),
        )
    ).all()
    unpaid_dues = sum(Decimal(str(inv.amount)) - Decimal(str(inv.paid_amount)) for inv in unpaid_invoices)
    damage_charges = payload.damage_charges or Decimal("0.00")
    total_deductions = unpaid_dues + damage_charges
    deposit = Decimal(str(resident.security_deposit or 0.00))

    if total_deductions > deposit and not payload.force_checkout:
        net_payable = total_deductions - deposit
        raise ConflictError(
            f"Resident has outstanding balance of INR {float(net_payable):,.2f} exceeding security deposit. "
            f"Please collect outstanding dues or enable force_checkout=true."
        )

    refund_amount = max(Decimal("0.00"), deposit - total_deductions)
    net_payable_by_resident = max(Decimal("0.00"), total_deductions - deposit)

    # 2. Release allocated bed
    bed_released = False
    bed_number = None
    old_bed_id = resident.bed_id
    if resident.bed_id:
        bed = db.scalar(sa.select(Bed).where(Bed.id == resident.bed_id).with_for_update())
        if bed:
            bed.status = "AVAILABLE"
            bed_number = bed.bed_number
            bed_released = True
        resident.bed_id = None

    # 3. Transition resident and user state
    checkout_dt = payload.check_out_date or payload.expected_check_out_date or date.today()
    resident.status = "CHECKED_OUT"
    resident.expected_check_out_date = checkout_dt

    user = db.get(User, resident.user_id)
    if user:
        user.is_active = False

    db.commit()
    db.refresh(resident)

    summary_msg = (
        f"Resident checked out successfully. Bed {bed_number or 'N/A'} released. "
        f"Deposit: INR {float(deposit):,.2f}, Deductions: INR {float(total_deductions):,.2f}, "
        f"Refund: INR {float(refund_amount):,.2f}."
    )

    record_audit_log(
        db=db,
        action="RESIDENT_CHECKOUT",
        resource_type="resident",
        user_id=current_user.id,
        user_email=current_user.email,
        user_role=current_user.role.name,
        property_id=resident.property_id,
        resource_id=str(resident.id),
        details={
            "check_out_date": str(checkout_dt),
            "bed_released": bed_released,
            "bed_id": str(old_bed_id) if old_bed_id else None,
            "security_deposit": float(deposit),
            "damage_charges": float(damage_charges),
            "unpaid_dues": float(unpaid_dues),
            "refund_amount": float(refund_amount),
            "net_payable_by_resident": float(net_payable_by_resident),
        },
    )

    return APIResponse(
        success=True,
        message="Resident checked out and bed released successfully.",
        data=ResidentCheckoutResponse(
            resident_id=resident.id,
            status=resident.status,
            check_out_date=checkout_dt,
            actual_check_out_date=checkout_dt,
            bed_released=bed_released,
            bed_id=old_bed_id,
            bed_number=bed_number,
            vacated_bed_id=old_bed_id,
            security_deposit=float(deposit),
            damage_charges=float(damage_charges),
            unpaid_invoices_total=float(unpaid_dues),
            outstanding_dues=float(unpaid_dues),
            deposit_refund_amount=float(refund_amount),
            net_payable_by_resident=float(net_payable_by_resident),
            summary=summary_msg,
            message=summary_msg,
        ),
    )


@router.get("/{resident_id}", response_model=APIResponse[ResidentDetailRead], status_code=status.HTTP_200_OK, summary="Get Resident Details")
def get_resident_detail(
    resident_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Retrieves full resident profile, allocation details, and masked KYC status."""
    resident = db.scalar(sa.select(Resident).where(Resident.id == resident_id))
    if not resident:
        raise NotFoundError("Resident record not found.")
    verify_property_access(resident.property_id, current_user, db)

    # Resident accounts can only view their own resident profile details
    if current_user.role.name == "RESIDENT" and resident.user_id != current_user.id:
        raise PermissionDeniedError("Resident accounts may only access their own profile details.")

    return APIResponse(
        success=True,
        message="Resident details retrieved.",
        data=_build_resident_detail(resident, db),
    )


@router.patch("/{resident_id}", response_model=APIResponse[ResidentDetailRead], status_code=status.HTTP_200_OK, summary="Update Resident Details")
def update_resident_details(
    resident_id: uuid.UUID,
    payload: ResidentUpdateRequest,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Updates resident profile, contacts, rent, or handles room/bed reallocation."""
    resident = db.scalar(sa.select(Resident).where(Resident.id == resident_id))
    if not resident:
        raise NotFoundError("Resident record not found.")
    verify_property_access(resident.property_id, current_user, db)

    user = db.get(User, resident.user_id) if resident.user_id else None

    update_dict = payload.model_dump(exclude_unset=True)

    # Reallocation logic
    if "bed_id" in update_dict:
        new_bed_id = update_dict["bed_id"]
        if new_bed_id != resident.bed_id:
            # Free old bed
            if resident.bed_id:
                old_bed = db.get(Bed, resident.bed_id)
                if old_bed:
                    old_bed.status = "AVAILABLE"

            if new_bed_id is not None:
                new_bed = db.scalar(sa.select(Bed).where(Bed.id == new_bed_id).with_for_update())
                if not new_bed:
                    raise NotFoundError("New bed not found.")
                if new_bed.property_id != resident.property_id:
                    raise BadRequestError("New bed does not belong to this property.")
                occ = db.scalar(sa.select(Resident).where(Resident.bed_id == new_bed.id, Resident.status == "ACTIVE", Resident.id != resident.id))
                if occ or new_bed.status != "AVAILABLE":
                    raise ConflictError(f"Bed '{new_bed.bed_number}' is already occupied.")

                new_bed.status = "OCCUPIED"
                resident.bed_id = new_bed.id
                resident.room_id = new_bed.room_id
            else:
                resident.bed_id = None
        update_dict.pop("bed_id")

    if "room_id" in update_dict and "bed_id" not in payload.model_fields_set:
        resident.room_id = update_dict["room_id"]
        update_dict.pop("room_id")

    if "full_name" in update_dict and update_dict["full_name"]:
        resident.full_name = update_dict["full_name"].strip()
        if user:
            user.full_name = resident.full_name
        update_dict.pop("full_name")

    if "phone" in update_dict and update_dict["phone"]:
        clean_p = normalize_phone(update_dict["phone"])
        resident.phone = clean_p
        if user:
            user.phone = clean_p
        update_dict.pop("phone")

    if "email" in update_dict and update_dict["email"]:
        clean_e = update_dict["email"].strip().lower()
        resident.email = clean_e
        if user:
            user.email = clean_e
        update_dict.pop("email")

    for f, v in update_dict.items():
        if hasattr(resident, f):
            setattr(resident, f, v)

    db.commit()
    db.refresh(resident)

    return APIResponse(
        success=True,
        message="Resident profile updated successfully.",
        data=_build_resident_detail(resident, db),
    )


@router.post("/{resident_id}/kyc/verify", response_model=APIResponse[ResidentDetailRead], status_code=status.HTTP_200_OK, summary="Verify Resident KYC")
def verify_resident_kyc(
    resident_id: uuid.UUID,
    payload: KYCActionRequest = KYCActionRequest(),
    current_user: User = Depends(require_roles("SUPER_ADMIN", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Marks resident KYC documentation as verified."""
    resident = db.scalar(sa.select(Resident).where(Resident.id == resident_id))
    if not resident:
        raise NotFoundError("Resident record not found.")
    verify_property_access(resident.property_id, current_user, db)

    resident.kyc_status = "VERIFIED"
    resident.verified_at = datetime.now(timezone.utc)
    resident.verified_by_id = current_user.id
    if payload.notes:
        resident.kyc_notes = payload.notes.strip()

    db.commit()
    db.refresh(resident)

    return APIResponse(
        success=True,
        message=f"KYC for resident '{resident.full_name}' verified successfully.",
        data=_build_resident_detail(resident, db),
    )


@router.post("/{resident_id}/kyc/reject", response_model=APIResponse[ResidentDetailRead], status_code=status.HTTP_200_OK, summary="Reject Resident KYC")
def reject_resident_kyc(
    resident_id: uuid.UUID,
    payload: KYCActionRequest,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Rejects resident KYC with required rejection notes."""
    resident = db.scalar(sa.select(Resident).where(Resident.id == resident_id))
    if not resident:
        raise NotFoundError("Resident record not found.")
    verify_property_access(resident.property_id, current_user, db)

    resident.kyc_status = "REJECTED"
    resident.kyc_notes = payload.notes.strip() if payload.notes else "KYC rejected by administrator."
    resident.verified_at = None
    resident.verified_by_id = None

    db.commit()
    db.refresh(resident)

    return APIResponse(
        success=True,
        message=f"KYC for resident '{resident.full_name}' rejected.",
        data=_build_resident_detail(resident, db),
    )


@router.post(
    "/{resident_id}/verify-kyc",
    response_model=APIResponse[ResidentDetailRead],
    status_code=status.HTTP_200_OK,
    summary="Verify Resident KYC (Alias)",
    include_in_schema=False,
)
def verify_resident_kyc_alias(
    resident_id: uuid.UUID,
    payload: KYCActionRequest = KYCActionRequest(),
    current_user: User = Depends(require_roles("SUPER_ADMIN", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Direct alias for verify KYC."""
    return verify_resident_kyc(resident_id=resident_id, payload=payload, current_user=current_user, db=db)


@router.post(
    "/{resident_id}/reject-kyc",
    response_model=APIResponse[ResidentDetailRead],
    status_code=status.HTTP_200_OK,
    summary="Reject Resident KYC (Alias)",
    include_in_schema=False,
)
def reject_resident_kyc_alias(
    resident_id: uuid.UUID,
    payload: KYCActionRequest,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Direct alias for reject KYC."""
    return reject_resident_kyc(resident_id=resident_id, payload=payload, current_user=current_user, db=db)


@router.post(
    "/onboard",
    response_model=APIResponse[ResidentDetailRead],
    status_code=status.HTTP_201_CREATED,
    summary="Manually Onboard Resident (Alias)",
    include_in_schema=False,
)
def onboard_resident_alias(
    payload: AdminResidentOnboardRequest,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Direct alias for manual resident onboarding."""
    return onboard_resident(payload=payload, current_user=current_user, db=db)


@router.get(
    "/{resident_id}/kyc-document/{doc_type}",
    summary="Download or Preview Resident KYC Document",
    response_class=FileResponse,
)
@router.get(
    "/{resident_id}/kyc-documents/{doc_type}",
    summary="Download or Preview Resident KYC Document (Alias)",
    response_class=FileResponse,
    include_in_schema=False,
)
def get_resident_kyc_document(
    resident_id: uuid.UUID,
    doc_type: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Authenticated and scoped KYC document retrieval.
    Strictly restricted to SUPER_ADMIN and PROPERTY_MANAGER belonging to the resident's company/property.
    STAFF and RESIDENT accounts are forbidden.
    Directory traversal attacks and raw path exposures are strictly prevented.
    """
    # 1. RBAC Check: Only SUPER_ADMIN and PROPERTY_MANAGER allowed
    if current_user.role.name not in ("SUPER_ADMIN", "PROPERTY_MANAGER"):
        raise PermissionDeniedError("STAFF and RESIDENT users are not permitted to access KYC documents.")

    # 2. Resident lookup
    resident = db.get(Resident, resident_id)
    if not resident:
        raise NotFoundError(f"Resident '{resident_id}' not found.")

    # 3. Company and Property scope check
    prop = db.get(Property, resident.property_id)
    if not prop or prop.company_id != current_user.company_id:
        raise PermissionDeniedError("Access to this property and its resident KYC documents is not permitted.")

    if current_user.role.name == "PROPERTY_MANAGER":
        verify_property_access(resident.property_id, current_user, db)

    # 4. Normalize and map doc_type to resident model attribute
    normalized_type = doc_type.strip().lower().replace("-", "_")
    type_attr_map = {
        "aadhaar_front": "aadhaar_front_path",
        "aadhaar_front_file": "aadhaar_front_path",
        "aadhaar_back": "aadhaar_back_path",
        "aadhaar_back_file": "aadhaar_back_path",
        "pan_card": "pan_card_path",
        "pan_card_file": "pan_card_path",
        "pan": "pan_card_path",
        "passport": "passport_path",
        "passport_file": "passport_path",
        "resident_selfie": "resident_selfie_path",
        "resident_selfie_file": "resident_selfie_path",
        "selfie": "resident_selfie_path",
        "id_proof": "id_proof_document_path",
    }

    if normalized_type not in type_attr_map:
        allowed = ["aadhaar_front", "aadhaar_back", "pan_card", "passport", "resident_selfie"]
        raise BadRequestError(f"Invalid KYC document type '{doc_type}'. Allowed types: {', '.join(allowed)}.")

    attr_name = type_attr_map[normalized_type]
    rel_path = getattr(resident, attr_name, None)

    # Fallback to resident.kyc_documents dict if stored there
    if not rel_path and resident.kyc_documents and isinstance(resident.kyc_documents, dict):
        rel_path = resident.kyc_documents.get(attr_name) or resident.kyc_documents.get(normalized_type)

    if not rel_path:
        raise NotFoundError(f"KYC document '{doc_type}' is not on record for this resident.")

    # 5. Directory traversal prevention & path resolution
    clean_rel = rel_path.lstrip("/\\")
    backend_root = Path(__file__).resolve().parents[4]  # backend root
    full_path = (backend_root / clean_rel).resolve()
    uploads_root = (backend_root / "uploads").resolve()

    if uploads_root not in full_path.parents and full_path != uploads_root:
        raise PermissionDeniedError("Access to the requested document path is forbidden.")

    if not full_path.is_file():
        raise NotFoundError(f"KYC document file '{doc_type}' not found on server storage.")

    # 6. Stream file with strict privacy headers
    mime_type, _ = mimetypes.guess_type(str(full_path))
    if not mime_type:
        mime_type = "application/octet-stream"

    return FileResponse(
        path=str(full_path),
        media_type=mime_type,
        filename=full_path.name,
        headers={
            "Cache-Control": "private, no-cache, no-store, must-revalidate",
            "Pragma": "no-cache",
            "Expires": "0",
            "X-Content-Type-Options": "nosniff",
        },
    )
