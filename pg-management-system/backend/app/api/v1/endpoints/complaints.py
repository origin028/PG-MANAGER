import uuid
from typing import List
from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.orm import Session

from app.dependencies import get_current_user, get_db, verify_property_access
from app.models.complaint import Complaint
from app.models.user import User
from app.schemas.common import APIResponse
from app.schemas.complaint import ComplaintRead

router = APIRouter()


@router.get("", response_model=APIResponse[List[ComplaintRead]], status_code=status.HTTP_200_OK)
def list_complaints(
    property_id: uuid.UUID = Query(..., description="Property ID filter"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Lists maintenance complaints for a property."""
    verify_property_access(property_id, current_user, db)
    complaints = db.query(Complaint).filter(Complaint.property_id == property_id).order_by(Complaint.created_at.desc()).all()
    items = [ComplaintRead.model_validate(c) for c in complaints]
    return APIResponse(
        success=True,
        message=f"Retrieved {len(items)} complaints.",
        data=items,
    )
