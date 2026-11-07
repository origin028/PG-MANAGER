import uuid
from typing import List, Optional
from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.orm import Session
import sqlalchemy as sa

from app.core.exceptions import BadRequestError, ConflictError, NotFoundError, PermissionDeniedError
from app.dependencies import get_current_user, get_db, require_roles, verify_property_access
from app.models.property import Property
from app.models.resident import Resident
from app.models.user import User, UserPropertyAccess
from app.schemas.common import APIResponse
from app.schemas.property import (
    PropertyAccessAssignRequest,
    PropertyCreate,
    PropertyRead,
    PropertySummary,
    PropertyUpdate,
)
from app.services.property_service import PropertyService

router = APIRouter()


@router.post("", response_model=APIResponse[PropertyRead], status_code=status.HTTP_201_CREATED, summary="Create Property")
def create_property(
    payload: PropertyCreate,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """
    Creates a new PG property under the authenticated company.
    Restricted to SUPER_ADMIN role.
    """
    existing = db.scalar(sa.select(Property).where(Property.code == payload.code.strip().upper()))
    if existing:
        raise ConflictError(f"A property with code '{payload.code}' already exists.")

    prop = Property(
        company_id=current_user.company_id,
        name=payload.name.strip(),
        code=payload.code.strip().upper(),
        property_type=payload.property_type,
        address_line1=payload.address_line1,
        address_line2=payload.address_line2,
        city=payload.city.strip(),
        state=payload.state.strip(),
        pincode=payload.pincode.strip(),
        contact_phone=payload.contact_phone,
        contact_email=payload.contact_email,
        total_floors=payload.total_floors,
        is_active=payload.is_active,
        description=payload.description,
        amenities=payload.amenities or [],
        rules=payload.rules or [],
        settings=payload.settings or {},
    )
    db.add(prop)
    db.flush()

    # Automatically grant creator access to the property
    creator_access = UserPropertyAccess(
        user_id=current_user.id,
        property_id=prop.id,
        access_level="MANAGE",
    )
    db.add(creator_access)
    db.commit()
    db.refresh(prop)

    return APIResponse(
        success=True,
        message="Property created successfully.",
        data=PropertyRead.model_validate(prop),
    )


@router.get("", response_model=APIResponse[List[PropertySummary]], status_code=status.HTTP_200_OK, summary="List Properties")
def list_properties(
    search: Optional[str] = Query(None, description="Search by property name or city"),
    city: Optional[str] = Query(None, description="Filter by city"),
    is_active: Optional[bool] = Query(None, description="Filter by active status"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Returns properties accessible to the authenticated user with optional search and city filters.
    """
    service = PropertyService(db)
    properties = service.get_accessible_properties(current_user)

    if is_active is not None:
        properties = [p for p in properties if p.is_active == is_active]
    if city:
        city_lower = city.strip().lower()
        properties = [p for p in properties if p.city and p.city.lower() == city_lower]
    if search:
        s_lower = search.strip().lower()
        properties = [
            p for p in properties
            if (p.name and s_lower in p.name.lower()) or (p.city and s_lower in p.city.lower()) or (p.code and s_lower in p.code.lower())
        ]

    summaries = [PropertySummary.model_validate(p) for p in properties]
    return APIResponse(
        success=True,
        message=f"Retrieved {len(summaries)} accessible properties.",
        data=summaries,
    )


@router.get("/{property_id}", response_model=APIResponse[PropertyRead], status_code=status.HTTP_200_OK, summary="Get Property Details")
def get_property(
    property_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Returns details of a specific property after server-side access check."""
    verify_property_access(property_id, current_user, db)
    service = PropertyService(db)
    prop = service.get_property_by_id(property_id)
    if not prop:
        raise NotFoundError(f"Property with ID '{property_id}' not found.")

    return APIResponse(
        success=True,
        message="Property details retrieved.",
        data=PropertyRead.model_validate(prop),
    )


@router.patch("/{property_id}", response_model=APIResponse[PropertyRead], status_code=status.HTTP_200_OK, summary="Update Property")
def update_property(
    property_id: uuid.UUID,
    payload: PropertyUpdate,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Updates property configuration, amenities, rules, or details."""
    verify_property_access(property_id, current_user, db)
    prop = db.scalar(sa.select(Property).where(Property.id == property_id))
    if not prop:
        raise NotFoundError(f"Property with ID '{property_id}' not found.")

    update_dict = payload.model_dump(exclude_unset=True)
    if "code" in update_dict and update_dict["code"]:
        new_code = update_dict["code"].strip().upper()
        if new_code != prop.code:
            existing = db.scalar(sa.select(Property).where(Property.code == new_code))
            if existing:
                raise ConflictError(f"A property with code '{new_code}' already exists.")
            prop.code = new_code
        update_dict.pop("code")

    for field, val in update_dict.items():
        if hasattr(prop, field):
            setattr(prop, field, val)

    db.commit()
    db.refresh(prop)
    return APIResponse(
        success=True,
        message="Property updated successfully.",
        data=PropertyRead.model_validate(prop),
    )


@router.delete("/{property_id}", response_model=APIResponse[dict], status_code=status.HTTP_200_OK, summary="Deactivate Property Safely")
def deactivate_property(
    property_id: uuid.UUID,
    current_user: User = Depends(require_roles("SUPER_ADMIN")),
    db: Session = Depends(get_db),
):
    """
    Safely deactivates a property.
    Prevents deletion/deactivation if there are active residents in the property.
    """
    prop = db.scalar(sa.select(Property).where(Property.id == property_id))
    if not prop:
        raise NotFoundError(f"Property with ID '{property_id}' not found.")

    # Guard: Active residents
    active_residents = db.scalar(
        sa.select(sa.func.count(Resident.id)).where(
            Resident.property_id == property_id,
            Resident.status == "ACTIVE",
        )
    )
    if active_residents and active_residents > 0:
        raise BadRequestError(
            f"Cannot deactivate property '{prop.name}'. There are {active_residents} active resident(s) allocated. "
            f"Please checkout or relocate residents before deactivating."
        )

    prop.is_active = False
    db.commit()

    return APIResponse(
        success=True,
        message=f"Property '{prop.name}' has been safely deactivated.",
        data={"property_id": str(property_id), "is_active": False},
    )


@router.post("/{property_id}/access", response_model=APIResponse[dict], status_code=status.HTTP_200_OK, summary="Assign User Property Access")
def assign_property_access(
    property_id: uuid.UUID,
    payload: PropertyAccessAssignRequest,
    current_user: User = Depends(require_roles("SUPER_ADMIN")),
    db: Session = Depends(get_db),
):
    """Assigns property access rights to a Property Manager or Staff member."""
    prop = db.scalar(sa.select(Property).where(Property.id == property_id))
    if not prop:
        raise NotFoundError(f"Property with ID '{property_id}' not found.")

    target_user = db.scalar(sa.select(User).where(User.id == payload.user_id))
    if not target_user:
        raise NotFoundError("User not found.")

    existing_access = db.scalar(
        sa.select(UserPropertyAccess).where(
            UserPropertyAccess.property_id == property_id,
            UserPropertyAccess.user_id == payload.user_id,
        )
    )
    if not existing_access:
        access = UserPropertyAccess(property_id=property_id, user_id=payload.user_id)
        db.add(access)
        db.commit()

    return APIResponse(
        success=True,
        message=f"Access to '{prop.name}' granted to user {target_user.full_name}.",
        data={"property_id": str(property_id), "user_id": str(payload.user_id)},
    )
