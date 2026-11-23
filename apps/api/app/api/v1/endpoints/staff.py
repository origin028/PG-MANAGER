import uuid
from typing import List, Optional
from fastapi import APIRouter, Depends, Query, status
import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.core.exceptions import BadRequestError, NotFoundError
from app.dependencies import get_current_user, get_db, require_roles, verify_property_access
from app.models.property import Property, Company
from app.models.staff import Staff
from app.models.user import User
from app.schemas.common import APIResponse
from app.schemas.staff import StaffCreate, StaffRead, StaffUpdate
from app.services.audit_service import record_audit_log

router = APIRouter()


@router.post("", response_model=APIResponse[StaffRead], status_code=status.HTTP_201_CREATED)
def create_staff(
    payload: StaffCreate,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "ADMIN", "OWNER", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Creates a new staff member profile."""
    company_id = None
    property_record = None

    if payload.property_id:
        verify_property_access(payload.property_id, current_user, db)
        property_record = db.get(Property, payload.property_id)
        if not property_record:
            raise NotFoundError("Property not found.")
        company_id = property_record.company_id
    else:
        first_company = db.scalar(sa.select(Company))
        if first_company:
            company_id = first_company.id

    if not company_id:
        raise BadRequestError("Cannot determine company for staff member.")

    staff = Staff(
        company_id=company_id,
        property_id=payload.property_id,
        name=payload.name.strip(),
        role=payload.role.strip().upper(),
        phone=payload.phone.strip(),
        email=payload.email.strip().lower() if payload.email else None,
        salary=payload.salary,
        joining_date=payload.joining_date,
        availability_hours=payload.availability_hours,
        is_emergency_contact=payload.is_emergency_contact,
        is_active=True,
    )
    db.add(staff)
    db.commit()
    db.refresh(staff)

    record_audit_log(
        db=db,
        action="CREATE_STAFF",
        resource_type="staff",
        user_id=current_user.id,
        user_email=current_user.email,
        user_role=current_user.role.name if current_user.role else None,
        property_id=staff.property_id,
        resource_id=str(staff.id),
        details={"name": staff.name, "role": staff.role, "phone": staff.phone},
    )

    read_data = StaffRead(
        id=staff.id,
        property_id=staff.property_id,
        company_id=staff.company_id,
        user_id=staff.user_id,
        name=staff.name,
        role=staff.role,
        phone=staff.phone,
        email=staff.email,
        salary=float(staff.salary or 0.0),
        joining_date=staff.joining_date,
        is_active=staff.is_active,
        availability_hours=staff.availability_hours,
        is_emergency_contact=staff.is_emergency_contact,
        created_at=staff.created_at,
        property_name=property_record.name if property_record else None,
    )
    return APIResponse(
        success=True,
        message=f"Staff member '{staff.name}' created successfully.",
        data=read_data,
    )


@router.get("", response_model=APIResponse[List[StaffRead]], status_code=status.HTTP_200_OK)
def list_staff(
    property_id: Optional[uuid.UUID] = Query(None, description="Property ID filter"),
    role: Optional[str] = Query(None, description="Role filter (PROPERTY_MANAGER, WARDEN, etc.)"),
    is_active: Optional[bool] = Query(None, description="Filter by active status"),
    current_user: User = Depends(require_roles("SUPER_ADMIN", "ADMIN", "OWNER", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Lists staff members with optional property, role and status filters."""
    query = sa.select(Staff)

    if property_id:
        verify_property_access(property_id, current_user, db)
        query = query.where(Staff.property_id == property_id)
    elif current_user.role.name not in ("SUPER_ADMIN", "OWNER"):
        allowed = getattr(current_user, "allowed_properties", []) or []
        allowed_uuids = [uuid.UUID(str(p)) for p in allowed if p]
        query = query.where(Staff.property_id.in_(allowed_uuids))

    if role:
        query = query.where(Staff.role == role.strip().upper())

    if is_active is not None:
        query = query.where(Staff.is_active == is_active)

    query = query.order_by(Staff.name.asc())
    staff_members = db.scalars(query).all()

    data = [
        StaffRead(
            id=s.id,
            property_id=s.property_id,
            company_id=s.company_id,
            user_id=s.user_id,
            name=s.name,
            role=s.role,
            phone=s.phone,
            email=s.email,
            salary=float(s.salary or 0.0),
            joining_date=s.joining_date,
            is_active=s.is_active,
            availability_hours=s.availability_hours,
            is_emergency_contact=s.is_emergency_contact,
            created_at=s.created_at,
            property_name=s.property.name if s.property else None,
        )
        for s in staff_members
    ]
    return APIResponse(
        success=True,
        message=f"Retrieved {len(data)} staff members.",
        data=data,
    )


@router.get("/{staff_id}", response_model=APIResponse[StaffRead], status_code=status.HTTP_200_OK)
def get_staff_detail(
    staff_id: uuid.UUID,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "ADMIN", "OWNER", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Retrieves single staff member details."""
    staff = db.get(Staff, staff_id)
    if not staff:
        raise NotFoundError("Staff member not found.")

    if staff.property_id:
        verify_property_access(staff.property_id, current_user, db)

    read_data = StaffRead(
        id=staff.id,
        property_id=staff.property_id,
        company_id=staff.company_id,
        user_id=staff.user_id,
        name=staff.name,
        role=staff.role,
        phone=staff.phone,
        email=staff.email,
        salary=float(staff.salary or 0.0),
        joining_date=staff.joining_date,
        is_active=staff.is_active,
        availability_hours=staff.availability_hours,
        is_emergency_contact=staff.is_emergency_contact,
        created_at=staff.created_at,
        property_name=staff.property.name if staff.property else None,
    )
    return APIResponse(
        success=True,
        message="Staff details retrieved successfully.",
        data=read_data,
    )


@router.patch("/{staff_id}", response_model=APIResponse[StaffRead], status_code=status.HTTP_200_OK)
def update_staff(
    staff_id: uuid.UUID,
    payload: StaffUpdate,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "ADMIN", "OWNER", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Updates staff member profile details."""
    staff = db.get(Staff, staff_id)
    if not staff:
        raise NotFoundError("Staff member not found.")

    if staff.property_id:
        verify_property_access(staff.property_id, current_user, db)

    update_data = payload.model_dump(exclude_unset=True)
    if not update_data:
        read_data = StaffRead(
            id=staff.id,
            property_id=staff.property_id,
            company_id=staff.company_id,
            user_id=staff.user_id,
            name=staff.name,
            role=staff.role,
            phone=staff.phone,
            email=staff.email,
            salary=float(staff.salary or 0.0),
            joining_date=staff.joining_date,
            is_active=staff.is_active,
            availability_hours=staff.availability_hours,
            is_emergency_contact=staff.is_emergency_contact,
            created_at=staff.created_at,
            property_name=staff.property.name if staff.property else None,
        )
        return APIResponse(success=True, message="No changes requested.", data=read_data)

    if "name" in update_data and update_data["name"]:
        staff.name = update_data["name"].strip()
    if "role" in update_data and update_data["role"]:
        staff.role = update_data["role"].strip().upper()
    if "phone" in update_data and update_data["phone"]:
        staff.phone = update_data["phone"].strip()
    if "email" in update_data:
        staff.email = update_data["email"].strip().lower() if update_data["email"] else None
    if "salary" in update_data and update_data["salary"] is not None:
        staff.salary = update_data["salary"]
    if "joining_date" in update_data:
        staff.joining_date = update_data["joining_date"]
    if "availability_hours" in update_data:
        staff.availability_hours = update_data["availability_hours"]
    if "is_emergency_contact" in update_data and update_data["is_emergency_contact"] is not None:
        staff.is_emergency_contact = update_data["is_emergency_contact"]
    if "is_active" in update_data and update_data["is_active"] is not None:
        staff.is_active = update_data["is_active"]
    if "property_id" in update_data:
        if update_data["property_id"]:
            verify_property_access(update_data["property_id"], current_user, db)
        staff.property_id = update_data["property_id"]

    record_audit_log(
        db=db,
        action="UPDATE_STAFF",
        resource_type="staff",
        user_id=current_user.id,
        user_email=current_user.email,
        user_role=current_user.role.name if current_user.role else None,
        property_id=staff.property_id,
        resource_id=str(staff.id),
        details={"updated_fields": list(update_data.keys())},
    )

    db.commit()
    db.refresh(staff)

    read_data = StaffRead(
        id=staff.id,
        property_id=staff.property_id,
        company_id=staff.company_id,
        user_id=staff.user_id,
        name=staff.name,
        role=staff.role,
        phone=staff.phone,
        email=staff.email,
        salary=float(staff.salary or 0.0),
        joining_date=staff.joining_date,
        is_active=staff.is_active,
        availability_hours=staff.availability_hours,
        is_emergency_contact=staff.is_emergency_contact,
        created_at=staff.created_at,
        property_name=staff.property.name if staff.property else None,
    )
    return APIResponse(
        success=True,
        message=f"Staff member '{staff.name}' updated successfully.",
        data=read_data,
    )


@router.delete("/{staff_id}", status_code=status.HTTP_200_OK)
def delete_staff(
    staff_id: uuid.UUID,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "ADMIN", "OWNER")),
    db: Session = Depends(get_db),
):
    """Deactivates a staff member (soft delete)."""
    staff = db.get(Staff, staff_id)
    if not staff:
        raise NotFoundError("Staff member not found.")

    if staff.property_id:
        verify_property_access(staff.property_id, current_user, db)

    staff.is_active = False

    record_audit_log(
        db=db,
        action="DEACTIVATE_STAFF",
        resource_type="staff",
        user_id=current_user.id,
        user_email=current_user.email,
        user_role=current_user.role.name if current_user.role else None,
        property_id=staff.property_id,
        resource_id=str(staff.id),
        details={"name": staff.name, "role": staff.role},
    )

    db.commit()

    return APIResponse(
        success=True,
        message=f"Staff member '{staff.name}' deactivated successfully.",
        data={"deactivated_id": str(staff_id)},
    )
