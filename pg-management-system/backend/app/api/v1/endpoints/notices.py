import uuid
from typing import List
from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.orm import Session

from app.dependencies import get_current_user, get_db, verify_property_access
from app.models.notice import Notice
from app.models.user import User
from app.schemas.common import APIResponse

router = APIRouter()


@router.get("", response_model=APIResponse[List[dict]], status_code=status.HTTP_200_OK)
def list_notices(
    property_id: uuid.UUID = Query(..., description="Property ID filter"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Lists published notices for a property."""
    verify_property_access(property_id, current_user, db)
    notices = db.query(Notice).filter(Notice.property_id == property_id).order_by(Notice.is_pinned.desc(), Notice.created_at.desc()).all()
    data = [
        {
            "id": str(n.id),
            "title": n.title,
            "content": n.content,
            "is_pinned": n.is_pinned,
            "created_at": n.created_at.isoformat(),
        }
        for n in notices
    ]
    return APIResponse(
        success=True,
        message=f"Retrieved {len(data)} notices.",
        data=data,
    )
