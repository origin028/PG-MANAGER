import uuid
from typing import List
from fastapi import APIRouter, Depends, status
from sqlalchemy.orm import Session

from app.dependencies import get_current_user, get_db, verify_property_access
from app.core.exceptions import NotFoundError
from app.models.user import User
from app.schemas.common import APIResponse
from app.schemas.property import PropertyRead, PropertySummary
from app.services.property_service import PropertyService

router = APIRouter()


@router.get("", response_model=APIResponse[List[PropertySummary]], status_code=status.HTTP_200_OK)
def list_properties(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Returns properties accessible to the authenticated user.
    - Super Admin sees all company PG properties.
    - Property Managers and Staff see only assigned properties.
    - Residents see only their assigned PG property.
    """
    service = PropertyService(db)
    properties = service.get_accessible_properties(current_user)
    summaries = [PropertySummary.model_validate(p) for p in properties]
    return APIResponse(
        success=True,
        message=f"Retrieved {len(summaries)} accessible properties.",
        data=summaries,
    )


@router.get("/{property_id}", response_model=APIResponse[PropertyRead], status_code=status.HTTP_200_OK)
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
