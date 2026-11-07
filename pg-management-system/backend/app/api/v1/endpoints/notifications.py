import uuid
from datetime import datetime, timezone
from typing import List, Optional
from fastapi import APIRouter, Depends, Query, status
import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.core.exceptions import NotFoundError, PermissionDeniedError
from app.dependencies import get_current_user, get_db
from app.models.device_token import DeviceToken
from app.models.notification import Notification
from app.models.user import User
from app.schemas.common import APIResponse
from app.schemas.notification import DeviceTokenRead, DeviceTokenRegisterRequest

router = APIRouter()


@router.post("/device-token", response_model=APIResponse[DeviceTokenRead], status_code=status.HTTP_200_OK)
def register_device_token(
    payload: DeviceTokenRegisterRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Registers or refreshes an authenticated client device push token (Pushy/native)."""
    now = datetime.now(timezone.utc)
    token_record = db.scalar(
        sa.select(DeviceToken).where(
            DeviceToken.user_id == current_user.id,
            DeviceToken.device_token == payload.device_token,
        )
    )
    if token_record:
        token_record.platform = payload.platform
        token_record.device_name = payload.device_name
        token_record.is_active = True
        token_record.last_seen_at = now
    else:
        token_record = DeviceToken(
            user_id=current_user.id,
            device_token=payload.device_token,
            platform=payload.platform,
            device_name=payload.device_name,
            is_active=True,
            last_seen_at=now,
        )
        db.add(token_record)

    db.commit()
    db.refresh(token_record)
    return APIResponse(
        success=True,
        message="Device push token registered successfully.",
        data=DeviceTokenRead.model_validate(token_record),
    )


@router.get("", response_model=APIResponse[List[dict]], status_code=status.HTTP_200_OK)
def get_user_notifications(
    unread_only: bool = Query(False, description="Filter to only unread notifications"),
    limit: int = Query(50, ge=1, le=100, description="Max notifications to retrieve"),
    offset: int = Query(0, ge=0, description="Offset for pagination"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Retrieves notifications for the current authenticated user (Resident or Admin)."""
    query = (
        db.query(Notification)
        .filter(Notification.user_id == current_user.id)
    )
    if unread_only:
        query = query.filter(Notification.status != "READ")

    notifications = (
        query.order_by(Notification.created_at.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )
    data = [
        {
            "id": str(n.id),
            "title": n.title,
            "body": n.body,
            "channel": n.channel,
            "status": n.status,
            "is_read": n.status == "READ",
            "created_at": n.created_at.isoformat(),
        }
        for n in notifications
    ]
    return APIResponse(
        success=True,
        message=f"Retrieved {len(data)} notifications.",
        data=data,
    )


@router.get("/unread-count", response_model=APIResponse[dict], status_code=status.HTTP_200_OK)
def get_unread_notification_count(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Returns the count of unread notifications for the authenticated user."""
    count = (
        db.query(Notification)
        .filter(
            Notification.user_id == current_user.id,
            Notification.status != "READ",
        )
        .count()
    )
    return APIResponse(
        success=True,
        message="Unread notification count retrieved.",
        data={"unread_count": count},
    )


@router.post("/read-all", response_model=APIResponse[dict], status_code=status.HTTP_200_OK)
def mark_all_notifications_read(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Marks all unread notifications for the authenticated user as READ."""
    now = datetime.now(timezone.utc)
    updated_rows = (
        db.query(Notification)
        .filter(
            Notification.user_id == current_user.id,
            Notification.status != "READ",
        )
        .update(
            {
                "status": "READ",
                "updated_at": now,
            },
            synchronize_session="fetch",
        )
    )
    db.commit()
    return APIResponse(
        success=True,
        message=f"Marked {updated_rows} notifications as read.",
        data={"updated_count": updated_rows},
    )


@router.patch("/{notification_id}/read", response_model=APIResponse[dict], status_code=status.HTTP_200_OK)
def mark_notification_read(
    notification_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Marks a single notification as READ, enforcing user-level isolation."""
    notification = db.get(Notification, notification_id)
    if not notification:
        raise NotFoundError("Notification not found.")

    if notification.user_id != current_user.id:
        raise PermissionDeniedError("Access denied. You cannot modify another user's notifications.")

    notification.status = "READ"
    notification.updated_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(notification)

    return APIResponse(
        success=True,
        message="Notification marked as read.",
        data={
            "id": str(notification.id),
            "status": notification.status,
            "is_read": True,
        },
    )
