from datetime import date
import secrets
import uuid
from typing import List, Optional
from fastapi import APIRouter, Depends, Query, status
import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.core.exceptions import BadRequestError, ConflictError, NotFoundError
from app.core.security import get_password_hash
from app.dependencies import get_current_user, get_db, require_roles, verify_property_access
from app.models.bed import Bed
from app.models.lead import Lead
from app.models.property import Property
from app.models.resident import Resident
from app.models.role import Role
from app.models.room import Room
from app.models.user import User
from app.schemas.common import APIResponse
from app.schemas.lead import LeadConvertRequest, LeadConvertResponse, LeadCreate, LeadRead, LeadUpdate
from app.services.audit_service import record_audit_log
from app.services.otp_service import normalize_phone

router = APIRouter()


@router.post("", response_model=APIResponse[LeadRead], status_code=status.HTTP_201_CREATED)
def create_lead(
    payload: LeadCreate,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "ADMIN", "OWNER", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Creates a new prospective tenant lead."""
    verify_property_access(payload.property_id, current_user, db)

    property_record = db.get(Property, payload.property_id)
    if not property_record:
        raise NotFoundError("Property not found.")

    lead = Lead(
        property_id=payload.property_id,
        name=payload.name.strip(),
        phone=payload.phone.strip(),
        email=payload.email.strip().lower() if payload.email else None,
        source=payload.source,
        requirement=payload.requirement,
        visit_date=payload.visit_date,
        follow_up_date=payload.follow_up_date,
        notes=payload.notes,
        status="NEW",
    )
    db.add(lead)
    db.commit()
    db.refresh(lead)

    record_audit_log(
        db=db,
        action="CREATE_LEAD",
        resource_type="leads",
        user_id=current_user.id,
        user_email=current_user.email,
        user_role=current_user.role.name if current_user.role else None,
        property_id=lead.property_id,
        resource_id=str(lead.id),
        details={"name": lead.name, "phone": lead.phone, "property": property_record.name},
    )

    read_data = LeadRead(
        id=lead.id,
        property_id=lead.property_id,
        name=lead.name,
        phone=lead.phone,
        email=lead.email,
        status=lead.status,
        source=lead.source,
        requirement=lead.requirement,
        visit_date=lead.visit_date,
        follow_up_date=lead.follow_up_date,
        notes=lead.notes,
        created_at=lead.created_at,
        updated_at=lead.updated_at,
        property_name=property_record.name,
    )
    return APIResponse(
        success=True,
        message=f"Lead '{lead.name}' created successfully.",
        data=read_data,
    )


@router.get("", response_model=APIResponse[List[LeadRead]], status_code=status.HTTP_200_OK)
def list_leads(
    property_id: Optional[uuid.UUID] = Query(None, description="Property ID filter"),
    status: Optional[str] = Query(None, description="Filter by status (NEW, CONTACTED, VISIT_SCHEDULED, BOOKED, LOST)"),
    search: Optional[str] = Query(None, description="Search name or phone"),
    current_user: User = Depends(require_roles("SUPER_ADMIN", "ADMIN", "OWNER", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Lists prospective resident leads with pipeline filters."""
    query = sa.select(Lead)

    if property_id:
        verify_property_access(property_id, current_user, db)
        query = query.where(Lead.property_id == property_id)
    elif current_user.role.name not in ("SUPER_ADMIN", "OWNER"):
        allowed = getattr(current_user, "allowed_properties", []) or []
        allowed_uuids = [uuid.UUID(str(p)) for p in allowed if p]
        query = query.where(Lead.property_id.in_(allowed_uuids))

    if status:
        query = query.where(Lead.status == status.strip().upper())

    if search:
        s = f"%{search.strip()}%"
        query = query.where(sa.or_(Lead.name.ilike(s), Lead.phone.ilike(s)))

    query = query.order_by(Lead.created_at.desc())
    leads = db.scalars(query).all()

    items = [
        LeadRead(
            id=l.id,
            property_id=l.property_id,
            name=l.name,
            phone=l.phone,
            email=l.email,
            status=l.status,
            source=l.source,
            requirement=l.requirement,
            visit_date=l.visit_date,
            follow_up_date=l.follow_up_date,
            notes=l.notes,
            created_at=l.created_at,
            updated_at=l.updated_at,
            property_name=l.property.name if l.property else None,
        )
        for l in leads
    ]
    return APIResponse(
        success=True,
        message=f"Retrieved {len(items)} leads.",
        data=items,
    )


@router.get("/{lead_id}", response_model=APIResponse[LeadRead], status_code=status.HTTP_200_OK)
def get_lead(
    lead_id: uuid.UUID,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "ADMIN", "OWNER", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Retrieves single lead details."""
    lead = db.get(Lead, lead_id)
    if not lead:
        raise NotFoundError("Lead not found.")

    verify_property_access(lead.property_id, current_user, db)

    read_data = LeadRead(
        id=lead.id,
        property_id=lead.property_id,
        name=lead.name,
        phone=lead.phone,
        email=lead.email,
        status=lead.status,
        source=lead.source,
        requirement=lead.requirement,
        visit_date=lead.visit_date,
        follow_up_date=lead.follow_up_date,
        notes=lead.notes,
        created_at=lead.created_at,
        updated_at=lead.updated_at,
        property_name=lead.property.name if lead.property else None,
    )
    return APIResponse(
        success=True,
        message="Lead details retrieved successfully.",
        data=read_data,
    )


@router.patch("/{lead_id}", response_model=APIResponse[LeadRead], status_code=status.HTTP_200_OK)
def update_lead(
    lead_id: uuid.UUID,
    payload: LeadUpdate,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "ADMIN", "OWNER", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Updates lead pipeline status or information."""
    lead = db.get(Lead, lead_id)
    if not lead:
        raise NotFoundError("Lead not found.")

    verify_property_access(lead.property_id, current_user, db)

    update_data = payload.model_dump(exclude_unset=True)
    if not update_data:
        read_data = LeadRead(
            id=lead.id,
            property_id=lead.property_id,
            name=lead.name,
            phone=lead.phone,
            email=lead.email,
            status=lead.status,
            source=lead.source,
            requirement=lead.requirement,
            visit_date=lead.visit_date,
            follow_up_date=lead.follow_up_date,
            notes=lead.notes,
            created_at=lead.created_at,
            updated_at=lead.updated_at,
            property_name=lead.property.name if lead.property else None,
        )
        return APIResponse(success=True, message="No changes requested.", data=read_data)

    if "name" in update_data and update_data["name"]:
        lead.name = update_data["name"].strip()
    if "phone" in update_data and update_data["phone"]:
        lead.phone = update_data["phone"].strip()
    if "email" in update_data:
        lead.email = update_data["email"].strip().lower() if update_data["email"] else None
    if "status" in update_data and update_data["status"]:
        lead.status = update_data["status"].strip().upper()
    if "source" in update_data:
        lead.source = update_data["source"]
    if "requirement" in update_data:
        lead.requirement = update_data["requirement"]
    if "visit_date" in update_data:
        lead.visit_date = update_data["visit_date"]
    if "follow_up_date" in update_data:
        lead.follow_up_date = update_data["follow_up_date"]
    if "notes" in update_data:
        lead.notes = update_data["notes"]
    if "property_id" in update_data and update_data["property_id"]:
        verify_property_access(update_data["property_id"], current_user, db)
        lead.property_id = update_data["property_id"]

    record_audit_log(
        db=db,
        action="UPDATE_LEAD",
        resource_type="leads",
        user_id=current_user.id,
        user_email=current_user.email,
        user_role=current_user.role.name if current_user.role else None,
        property_id=lead.property_id,
        resource_id=str(lead.id),
        details={"updated_fields": list(update_data.keys()), "status": lead.status},
    )

    db.commit()
    db.refresh(lead)

    read_data = LeadRead(
        id=lead.id,
        property_id=lead.property_id,
        name=lead.name,
        phone=lead.phone,
        email=lead.email,
        status=lead.status,
        source=lead.source,
        requirement=lead.requirement,
        visit_date=lead.visit_date,
        follow_up_date=lead.follow_up_date,
        notes=lead.notes,
        created_at=lead.created_at,
        updated_at=lead.updated_at,
        property_name=lead.property.name if lead.property else None,
    )
    return APIResponse(
        success=True,
        message="Lead updated successfully.",
        data=read_data,
    )


@router.delete("/{lead_id}", status_code=status.HTTP_200_OK)
def delete_lead(
    lead_id: uuid.UUID,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "ADMIN", "OWNER")),
    db: Session = Depends(get_db),
):
    """Deletes a lead record."""
    lead = db.get(Lead, lead_id)
    if not lead:
        raise NotFoundError("Lead not found.")

    verify_property_access(lead.property_id, current_user, db)

    record_audit_log(
        db=db,
        action="DELETE_LEAD",
        resource_type="leads",
        user_id=current_user.id,
        user_email=current_user.email,
        user_role=current_user.role.name if current_user.role else None,
        property_id=lead.property_id,
        resource_id=str(lead.id),
        details={"name": lead.name, "phone": lead.phone},
    )

    db.delete(lead)
    db.commit()

    return APIResponse(
        success=True,
        message=f"Lead '{lead.name}' deleted successfully.",
        data={"deleted_id": str(lead_id)},
    )


@router.post("/{lead_id}/convert", response_model=APIResponse[LeadConvertResponse], status_code=status.HTTP_200_OK)
def convert_lead(
    lead_id: uuid.UUID,
    payload: Optional[LeadConvertRequest] = None,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "ADMIN", "OWNER", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """
    Converts a sales lead into an onboarded resident.
    Creates user and resident records, optionally assigns room/bed, and marks lead as CONVERTED.
    """
    lead = db.get(Lead, lead_id)
    if not lead:
        raise NotFoundError("Lead not found.")

    verify_property_access(lead.property_id, current_user, db)

    if lead.status == "CONVERTED":
        raise ConflictError("This lead has already been converted to a resident.")

    clean_phone = normalize_phone(lead.phone)
    clean_email = lead.email.strip().lower() if lead.email else None

    # Check if user already exists
    user = db.scalar(sa.select(User).where(User.phone == clean_phone))
    if not user:
        resident_role = db.scalar(sa.select(Role).where(Role.name == "RESIDENT"))
        if not resident_role:
            resident_role = Role(name="RESIDENT", display_name="Resident")
            db.add(resident_role)
            db.flush()

        init_password = secrets.token_urlsafe(16)
        user = User(
            company_id=current_user.company_id,
            role_id=resident_role.id,
            full_name=lead.name.strip(),
            phone=clean_phone,
            email=clean_email,
            password_hash=get_password_hash(init_password),
            is_active=True,
            is_verified=True,
            approval_status="APPROVED",
        )
        db.add(user)
        db.flush()

    # Check if resident profile already exists for this user
    resident = db.scalar(sa.select(Resident).where(Resident.user_id == user.id))
    if not resident:
        req_rent = payload.monthly_rent if payload and payload.monthly_rent is not None else 6000.0
        req_deposit = payload.security_deposit if payload and payload.security_deposit is not None else 6000.0
        check_in = payload.check_in_date.date() if payload and payload.check_in_date else date.today()

        room_id = payload.room_id if payload else None
        bed_id = payload.bed_id if payload else None

        if bed_id:
            bed = db.scalar(sa.select(Bed).where(Bed.id == bed_id).with_for_update())
            if bed and bed.status == "AVAILABLE":
                bed.status = "OCCUPIED"
                room_id = bed.room_id

        resident = Resident(
            property_id=lead.property_id,
            room_id=room_id,
            bed_id=bed_id,
            user_id=user.id,
            check_in_date=check_in,
            monthly_rent=req_rent,
            security_deposit=req_deposit,
            kyc_status="VERIFIED",
            status="ACTIVE",
        )
        db.add(resident)
        db.flush()

    # Update lead status
    lead.status = "CONVERTED"
    if payload and payload.notes:
        lead.notes = f"{(lead.notes or '')}\nConversion Note: {payload.notes}".strip()

    record_audit_log(
        db=db,
        action="CONVERT_LEAD",
        resource_type="leads",
        user_id=current_user.id,
        user_email=current_user.email,
        user_role=current_user.role.name if current_user.role else None,
        property_id=lead.property_id,
        resource_id=str(lead.id),
        details={"lead_name": lead.name, "resident_id": str(resident.id), "user_id": str(user.id)},
    )

    db.commit()

    return APIResponse(
        success=True,
        message=f"Lead '{lead.name}' successfully converted to resident.",
        data=LeadConvertResponse(
            lead_id=lead.id,
            resident_id=resident.id,
            user_id=user.id,
            status="CONVERTED",
            message=f"Lead '{lead.name}' converted successfully.",
        ),
    )
