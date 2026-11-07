import uuid
from decimal import Decimal
from typing import List, Optional

import sqlalchemy as sa
from fastapi import APIRouter, Depends, Query, Request, status
from pydantic import BaseModel, Field, field_validator
from sqlalchemy.orm import Session

from app.api.deps import get_db, require_roles
from app.core.exceptions import ConflictError, ValidationError
from app.models.staff import Staff
from app.models.user import User
from app.schemas.common import APIResponse
from app.services.audit_service import record_audit_log
from app.services.operations_service import get_permitted_property_ids

router = APIRouter()

DESIGNATIONS = {
    "WARDEN",
    "CARETAKER",
    "ACCOUNTANT",
    "CHEF",
    "MANAGER",
    "HOUSEKEEPING",
    "SECURITY",
    "OTHER",
}


def _normalize(value: str) -> str:
    return "_".join(value.strip().upper().replace("-", " ").split())


class StaffCreate(BaseModel):
    name: str = Field(..., min_length=2, max_length=150)
    role: str = Field(..., description="Staff designation, e.g. WARDEN, CARETAKER, CHEF")
    phone: str = Field(..., pattern=r"^\+?[0-9]{10,15}$")
    salary: Decimal = Field(..., ge=0)
    property_id: Optional[uuid.UUID] = None
    user_id: Optional[uuid.UUID] = None
    is_active: bool = True

    @field_validator("role")
    @classmethod
    def _validate_role(cls, value: str) -> str:
        normalized = _normalize(value)
        if normalized not in DESIGNATIONS:
            raise ValueError(
                "role must be one of WARDEN, CARETAKER, ACCOUNTANT, CHEF, MANAGER, "
                "HOUSEKEEPING, SECURITY, OTHER"
            )
        return normalized


def _serialize(staff: Staff) -> dict:
    return {
        "id": str(staff.id),
        "company_id": str(staff.company_id),
        "property_id": str(staff.property_id) if staff.property_id else None,
        "user_id": str(staff.user_id) if staff.user_id else None,
        "name": staff.name,
        "role": staff.role,
        "phone": staff.phone,
        "salary": float(staff.salary),
        "is_active": staff.is_active,
        "created_at": staff.created_at.isoformat() if staff.created_at else None,
    }


@router.get("", response_model=APIResponse[List[dict]], status_code=status.HTTP_200_OK)
def get_staff(
    property_id: Optional[uuid.UUID] = Query(None, description="Filter by property ID"),
    current_user: User = Depends(require_roles("SUPER_ADMIN", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Lists staff records scoped to the caller's company and assigned properties."""
    permitted = get_permitted_property_ids(db, current_user, property_id)
    stmt = sa.select(Staff).where(Staff.company_id == current_user.company_id)
    if property_id:
        stmt = stmt.where(Staff.property_id == property_id)
    elif permitted:
        stmt = stmt.where(
            sa.or_(Staff.property_id.in_(permitted), Staff.property_id.is_(None))
        )
    staff = db.scalars(stmt.order_by(Staff.name.asc())).all()
    result = [_serialize(s) for s in staff]
    return APIResponse(success=True, message=f"Retrieved {len(result)} staff.", data=result)


@router.post("", response_model=APIResponse[dict], status_code=status.HTTP_201_CREATED)
def create_staff(
    payload: StaffCreate,
    request: Request,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Creates a staff employment record within the caller's property scope."""
    if payload.property_id:
        get_permitted_property_ids(db, current_user, payload.property_id)
    elif current_user.role.name != "SUPER_ADMIN":
        raise ValidationError("property_id is required for property managers.")

    if payload.user_id:
        linked_user = db.get(User, payload.user_id)
        if not linked_user or linked_user.company_id != current_user.company_id:
            raise ValidationError("Linked user does not belong to your company.")

    duplicate = db.scalar(
        sa.select(Staff).where(
            Staff.company_id == current_user.company_id,
            Staff.phone == payload.phone,
            Staff.is_active == True,
        )
    )
    if duplicate:
        raise ConflictError("An active staff member with this phone number already exists.")

    staff = Staff(
        company_id=current_user.company_id,
        property_id=payload.property_id,
        user_id=payload.user_id,
        name=payload.name.strip(),
        role=payload.role,
        phone=payload.phone,
        salary=payload.salary,
        is_active=payload.is_active,
    )
    db.add(staff)
    db.commit()
    db.refresh(staff)

    record_audit_log(
        db=db,
        action="STAFF_CREATED",
        resource_type="staff",
        resource_id=str(staff.id),
        user_id=current_user.id,
        user_email=current_user.email,
        user_role=current_user.role.name,
        company_id=staff.company_id,
        property_id=staff.property_id,
        details={
            "name": staff.name,
            "role": staff.role,
            "phone": staff.phone,
        },
        ip_address=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent"),
    )
    return APIResponse(success=True, message="Staff created successfully.", data=_serialize(staff))
