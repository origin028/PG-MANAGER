import uuid
from typing import List, Optional
from fastapi import APIRouter, Depends, Query, status
import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.core.exceptions import NotFoundError
from app.dependencies import get_current_user, get_db, require_roles, verify_property_access
from app.models.notice import Notice
from app.models.property import Property
from app.models.resident import Resident
from app.models.user import User
from app.schemas.common import APIResponse
from app.schemas.notice import NoticeCreate, NoticeRead, NoticeUpdate
from app.services.audit_service import record_audit_log
from app.services.notification_service import NotificationService

router = APIRouter()


@router.post("", response_model=APIResponse[NoticeRead], status_code=status.HTTP_201_CREATED)
def create_notice(
    payload: NoticeCreate,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "ADMIN", "OWNER", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Publishes a new property notice and broadcasts to residents."""
    verify_property_access(payload.property_id, current_user, db)

    property_record = db.get(Property, payload.property_id)
    if not property_record:
        raise NotFoundError("Property not found.")

    notice = Notice(
        property_id=payload.property_id,
        created_by_user_id=current_user.id,
        title=payload.title.strip(),
        content=payload.content.strip(),
        is_pinned=payload.is_pinned,
        expires_at=payload.expires_at,
    )
    db.add(notice)
    db.commit()
    db.refresh(notice)

    record_audit_log(
        db=db,
        action="CREATE_NOTICE",
        resource_type="notices",
        user_id=current_user.id,
        user_email=current_user.email,
        user_role=current_user.role.name if current_user.role else None,
        property_id=notice.property_id,
        resource_id=str(notice.id),
        details={"title": notice.title, "property": property_record.name},
    )

    # Broadcast notification to active residents in property
    active_residents = db.scalars(
        sa.select(Resident).where(
            Resident.property_id == payload.property_id,
            Resident.status.in_(("ACTIVE", "NOTICE_PERIOD")),
        )
    ).all()
    notif_service = NotificationService(db)
    for res in active_residents:
        if res.user_id:
            notif_service.dispatch(
                user_id=res.user_id,
                title=f"Notice: {notice.title}",
                body=notice.content[:200],
                channel="PUSH",
            )

    read_data = NoticeRead(
        id=notice.id,
        property_id=notice.property_id,
        created_by_user_id=notice.created_by_user_id,
        title=notice.title,
        content=notice.content,
        is_pinned=notice.is_pinned,
        expires_at=notice.expires_at,
        created_at=notice.created_at,
        updated_at=notice.updated_at,
        property_name=property_record.name,
    )
    return APIResponse(
        success=True,
        message=f"Notice '{notice.title}' published successfully.",
        data=read_data,
    )


@router.get("", response_model=APIResponse[List[NoticeRead]], status_code=status.HTTP_200_OK)
def list_notices(
    property_id: uuid.UUID = Query(..., description="Property ID filter"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Lists published notices for a property."""
    if current_user.role.name != "RESIDENT":
        verify_property_access(property_id, current_user, db)

    property_record = db.get(Property, property_id)
    prop_name = property_record.name if property_record else None

    notices = (
        db.query(Notice)
        .filter(Notice.property_id == property_id)
        .order_by(Notice.is_pinned.desc(), Notice.created_at.desc())
        .all()
    )

    items = [
        NoticeRead(
            id=n.id,
            property_id=n.property_id,
            created_by_user_id=n.created_by_user_id,
            title=n.title,
            content=n.content,
            is_pinned=n.is_pinned,
            expires_at=n.expires_at,
            created_at=n.created_at,
            updated_at=n.updated_at,
            property_name=prop_name,
        )
        for n in notices
    ]
    return APIResponse(
        success=True,
        message=f"Retrieved {len(items)} notices.",
        data=items,
    )


@router.get("/{notice_id}", response_model=APIResponse[NoticeRead], status_code=status.HTTP_200_OK)
def get_notice(
    notice_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Retrieves single notice details."""
    notice = db.get(Notice, notice_id)
    if not notice:
        raise NotFoundError("Notice not found.")

    if current_user.role.name != "RESIDENT":
        verify_property_access(notice.property_id, current_user, db)

    read_data = NoticeRead(
        id=notice.id,
        property_id=notice.property_id,
        created_by_user_id=notice.created_by_user_id,
        title=notice.title,
        content=notice.content,
        is_pinned=notice.is_pinned,
        expires_at=notice.expires_at,
        created_at=notice.created_at,
        updated_at=notice.updated_at,
        property_name=notice.property.name if notice.property else None,
    )
    return APIResponse(
        success=True,
        message="Notice retrieved successfully.",
        data=read_data,
    )


@router.patch("/{notice_id}", response_model=APIResponse[NoticeRead], status_code=status.HTTP_200_OK)
def update_notice(
    notice_id: uuid.UUID,
    payload: NoticeUpdate,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "ADMIN", "OWNER", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Updates a published notice."""
    notice = db.get(Notice, notice_id)
    if not notice:
        raise NotFoundError("Notice not found.")

    verify_property_access(notice.property_id, current_user, db)

    update_data = payload.model_dump(exclude_unset=True)
    if not update_data:
        read_data = NoticeRead(
            id=notice.id,
            property_id=notice.property_id,
            created_by_user_id=notice.created_by_user_id,
            title=notice.title,
            content=notice.content,
            is_pinned=notice.is_pinned,
            expires_at=notice.expires_at,
            created_at=notice.created_at,
            updated_at=notice.updated_at,
            property_name=notice.property.name if notice.property else None,
        )
        return APIResponse(success=True, message="No changes requested.", data=read_data)

    if "title" in update_data and update_data["title"]:
        notice.title = update_data["title"].strip()
    if "content" in update_data and update_data["content"]:
        notice.content = update_data["content"].strip()
    if "is_pinned" in update_data and update_data["is_pinned"] is not None:
        notice.is_pinned = update_data["is_pinned"]
    if "expires_at" in update_data:
        notice.expires_at = update_data["expires_at"]

    record_audit_log(
        db=db,
        action="UPDATE_NOTICE",
        resource_type="notices",
        user_id=current_user.id,
        user_email=current_user.email,
        user_role=current_user.role.name if current_user.role else None,
        property_id=notice.property_id,
        resource_id=str(notice.id),
        details={"updated_fields": list(update_data.keys())},
    )

    db.commit()
    db.refresh(notice)

    read_data = NoticeRead(
        id=notice.id,
        property_id=notice.property_id,
        created_by_user_id=notice.created_by_user_id,
        title=notice.title,
        content=notice.content,
        is_pinned=notice.is_pinned,
        expires_at=notice.expires_at,
        created_at=notice.created_at,
        updated_at=notice.updated_at,
        property_name=notice.property.name if notice.property else None,
    )
    return APIResponse(
        success=True,
        message="Notice updated successfully.",
        data=read_data,
    )


@router.delete("/{notice_id}", status_code=status.HTTP_200_OK)
def delete_notice(
    notice_id: uuid.UUID,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "ADMIN", "OWNER", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Deletes a notice."""
    notice = db.get(Notice, notice_id)
    if not notice:
        raise NotFoundError("Notice not found.")

    verify_property_access(notice.property_id, current_user, db)

    record_audit_log(
        db=db,
        action="DELETE_NOTICE",
        resource_type="notices",
        user_id=current_user.id,
        user_email=current_user.email,
        user_role=current_user.role.name if current_user.role else None,
        property_id=notice.property_id,
        resource_id=str(notice.id),
        details={"title": notice.title},
    )

    db.delete(notice)
    db.commit()

    return APIResponse(
        success=True,
        message=f"Notice '{notice.title}' deleted successfully.",
        data={"deleted_id": str(notice_id)},
    )
