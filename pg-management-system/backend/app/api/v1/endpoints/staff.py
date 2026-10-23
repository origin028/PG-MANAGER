import uuid
from typing import List
from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.orm import Session

from app.dependencies import get_db, require_roles, verify_property_access
from app.models.staff import Staff
from app.models.user import User
from app.schemas.common import APIResponse

router = APIRouter()


@router.get("", response_model=APIResponse[List[dict]], status_code=status.HTTP_200_OK)
def list_staff(
    property_id: uuid.UUID = Query(..., description="Property ID filter"),
    current_user: User = Depends(require_roles("SUPER_ADMIN", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Lists staff members for a property."""
    verify_property_access(property_id, current_user, db)
    staff_members = db.query(Staff).filter(Staff.property_id == property_id).all()
    data = [
        {
            "id": str(s.id),
            "user_id": str(s.user_id),
            "full_name": s.user.full_name,
            "designation": s.designation,
            "salary": float(s.salary) if current_user.role.name == "SUPER_ADMIN" else None,
            "status": s.status,
        }
        for s in staff_members
    ]
    return APIResponse(
        success=True,
        message=f"Retrieved {len(data)} staff members.",
        data=data,
    )
