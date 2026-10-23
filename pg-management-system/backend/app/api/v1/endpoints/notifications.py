from typing import List
from fastapi import APIRouter, Depends, status
from sqlalchemy.orm import Session

from app.dependencies import get_current_user, get_db
from app.models.notification import Notification
from app.models.user import User
from app.schemas.common import APIResponse

router = APIRouter()


@router.get("", response_model=APIResponse[List[dict]], status_code=status.HTTP_200_OK)
def get_user_notifications(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Retrieves notifications for the current authenticated user."""
    notifications = (
        db.query(Notification)
        .filter(Notification.user_id == current_user.id)
        .order_by(Notification.created_at.desc())
        .limit(50)
        .all()
    )
    data = [
        {
            "id": str(n.id),
            "title": n.title,
            "body": n.body,
            "channel": n.channel,
            "status": n.status,
            "created_at": n.created_at.isoformat(),
        }
        for n in notifications
    ]
    return APIResponse(
        success=True,
        message=f"Retrieved {len(data)} notifications.",
        data=data,
    )
