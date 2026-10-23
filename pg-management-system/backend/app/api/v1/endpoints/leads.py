import uuid
from typing import List
from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.orm import Session

from app.dependencies import get_db, require_roles, verify_property_access
from app.models.lead import Lead
from app.models.user import User
from app.schemas.common import APIResponse

router = APIRouter()


@router.get("", response_model=APIResponse[List[dict]], status_code=status.HTTP_200_OK)
def list_leads(
    property_id: uuid.UUID = Query(..., description="Property ID filter"),
    current_user: User = Depends(require_roles("SUPER_ADMIN", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Lists prospective resident leads."""
    verify_property_access(property_id, current_user, db)
    leads = db.query(Lead).filter(Lead.property_id == property_id).order_by(Lead.created_at.desc()).all()
    data = [
        {
            "id": str(l.id),
            "name": l.name,
            "phone": l.phone,
            "email": l.email,
            "status": l.status,
            "visit_date": l.visit_date.isoformat() if l.visit_date else None,
        }
        for l in leads
    ]
    return APIResponse(
        success=True,
        message=f"Retrieved {len(data)} leads.",
        data=data,
    )
