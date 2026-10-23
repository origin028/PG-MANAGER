import uuid
from typing import Dict, Any
from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.orm import Session

from app.dependencies import get_db, require_roles, verify_property_access
from app.models.user import User
from app.schemas.common import APIResponse

router = APIRouter()


@router.get("/occupancy", response_model=APIResponse[Dict[str, Any]], status_code=status.HTTP_200_OK)
def get_occupancy_report(
    property_id: uuid.UUID = Query(..., description="Property ID filter"),
    current_user: User = Depends(require_roles("SUPER_ADMIN", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Generates occupancy and bed utilization summary for a property."""
    verify_property_access(property_id, current_user, db)
    # Reporting calculation placeholder
    data = {
        "property_id": str(property_id),
        "total_beds": 48,
        "occupied_beds": 42,
        "available_beds": 6,
        "occupancy_rate_percent": 87.5,
    }
    return APIResponse(
        success=True,
        message="Occupancy summary generated.",
        data=data,
    )
