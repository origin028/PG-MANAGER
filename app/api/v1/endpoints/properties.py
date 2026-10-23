import uuid
from typing import List
from fastapi import APIRouter, Depends, status
import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.api.deps import get_current_user, get_db, require_roles, verify_property_access
from app.core.exceptions import ConflictError, NotFoundError
from app.models.property import Property
from app.models.user import User
from app.schemas.common import APIResponse
from app.schemas.property import PropertyCreate, PropertyRead, PropertySummary
from app.services.audit_service import record_audit_log
from app.services.property_service import get_properties_for_user, get_property_by_id

router = APIRouter()


@router.get("", response_model=APIResponse[List[PropertySummary]], status_code=status.HTTP_200_OK)
def list_user_properties(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Returns properties accessible to the current user.
    - Super Admins see all company PG properties.
    - Property Managers and Staff see only assigned properties.
    - Residents see only their assigned PG property.
    """
    properties = get_properties_for_user(db, current_user)
    summaries = [PropertySummary.model_validate(p) for p in properties]
    return APIResponse(
        success=True,
        message=f"Retrieved {len(summaries)} accessible properties.",
        data=summaries,
    )


@router.get("/{property_id}", response_model=APIResponse[PropertyRead], status_code=status.HTTP_200_OK)
def get_property_details(
    property_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Returns complete details of a property after server-side access verification.
    """
    verify_property_access(property_id, current_user, db)
    prop = get_property_by_id(db, property_id)
    if not prop:
        raise NotFoundError(f"Property with ID '{property_id}' not found.")

    return APIResponse(
        success=True,
        message="Property details retrieved successfully.",
        data=PropertyRead.model_validate(prop),
    )


@router.post("", response_model=APIResponse[PropertyRead], status_code=status.HTTP_201_CREATED)
def create_new_property(
    payload: PropertyCreate,
    current_user: User = Depends(require_roles("SUPER_ADMIN")),
    db: Session = Depends(get_db),
):
    """
    Create a new PG property. Restricted to Super Admin.
    """
    # Check property code uniqueness
    existing = db.scalar(sa.select(Property).where(Property.code == payload.code.upper()))
    if existing:
        raise ConflictError(f"A property with code '{payload.code}' already exists.")

    new_prop = Property(
        company_id=current_user.company_id,
        name=payload.name,
        code=payload.code.upper(),
        property_type=payload.property_type,
        address_line1=payload.address_line1,
        address_line2=payload.address_line2,
        city=payload.city,
        state=payload.state,
        pincode=payload.pincode,
        contact_phone=payload.contact_phone,
        contact_email=payload.contact_email,
        total_floors=payload.total_floors,
        is_active=payload.is_active,
        settings=payload.settings,
    )
    db.add(new_prop)
    db.commit()
    db.refresh(new_prop)

    record_audit_log(
        db=db,
        action="PROPERTY_CREATED",
        resource_type="property",
        user_id=current_user.id,
        user_email=current_user.email,
        user_role=current_user.role.name,
        company_id=current_user.company_id,
        property_id=new_prop.id,
        resource_id=str(new_prop.id),
        details={"name": new_prop.name, "code": new_prop.code},
    )

    return APIResponse(
        success=True,
        message="Property created successfully.",
        data=PropertyRead.model_validate(new_prop),
    )
