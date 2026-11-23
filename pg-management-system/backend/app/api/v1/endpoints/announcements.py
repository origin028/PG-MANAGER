import uuid
from typing import List, Optional
from fastapi import APIRouter, Depends, Query, status
import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.core.exceptions import NotFoundError, PermissionDeniedError
from app.dependencies import (
    get_current_active_resident,
    get_current_user,
    get_db,
    require_roles,
    verify_property_access,
)
from app.models.announcement import Announcement
from app.models.property import Property
from app.models.resident import Resident
from app.models.user import User, UserPropertyAccess
from app.schemas.announcement import (
    AnnouncementCreate,
    AnnouncementRead,
    AnnouncementStatusUpdate,
    AnnouncementUpdate,
)
from app.schemas.common import APIResponse
from app.services.audit_service import record_audit_log

router = APIRouter()


def _to_read_dto(ann: Announcement, db: Session) -> AnnouncementRead:
    prop_name = None
    if ann.property_id:
        p = db.get(Property, ann.property_id)
        if p:
            prop_name = p.name
    else:
        prop_name = "All Properties"

    created_by_name = None
    if ann.created_by_user_id:
        u = db.get(User, ann.created_by_user_id)
        if u:
            created_by_name = u.full_name or u.email

    return AnnouncementRead(
        id=ann.id,
        company_id=ann.company_id,
        property_id=ann.property_id,
        property_name=prop_name,
        created_by_user_id=ann.created_by_user_id,
        created_by_name=created_by_name,
        title=ann.title,
        content=ann.content,
        is_active=ann.is_active,
        created_at=ann.created_at,
        updated_at=ann.updated_at,
    )


@router.post("", response_model=APIResponse[AnnouncementRead], status_code=status.HTTP_201_CREATED)
def create_announcement(
    payload: AnnouncementCreate,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "ADMIN", "OWNER", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Creates a new property or company-wide announcement."""
    if payload.property_id:
        verify_property_access(payload.property_id, current_user, db)
    else:
        # Only Super Admin or Owner can create company-wide announcements
        if current_user.role.name not in ("SUPER_ADMIN", "ADMIN", "OWNER"):
            raise PermissionDeniedError("Property managers must specify a property for announcements.")

    announcement = Announcement(
        company_id=current_user.company_id,
        property_id=payload.property_id,
        created_by_user_id=current_user.id,
        title=payload.title.strip(),
        content=payload.content.strip(),
        is_active=payload.is_active,
    )
    db.add(announcement)
    db.commit()
    db.refresh(announcement)

    record_audit_log(
        db=db,
        action="CREATE_ANNOUNCEMENT",
        resource_type="announcements",
        user_id=current_user.id,
        user_email=current_user.email,
        user_role=current_user.role.name if current_user.role else None,
        property_id=announcement.property_id,
        resource_id=str(announcement.id),
        details={"title": announcement.title, "property_id": str(announcement.property_id) if announcement.property_id else None},
    )

    return APIResponse(
        success=True,
        message=f"Announcement '{announcement.title}' created successfully.",
        data=_to_read_dto(announcement, db),
    )


@router.get("", response_model=APIResponse[List[AnnouncementRead]], status_code=status.HTTP_200_OK)
def list_announcements(
    property_id: Optional[uuid.UUID] = Query(None, description="Filter by property ID"),
    is_active: Optional[bool] = Query(None, description="Filter by active status"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Lists announcements. Scoped to authorized properties for managers and residents."""
    query = db.query(Announcement).filter(Announcement.company_id == current_user.company_id)

    if current_user.role.name == "RESIDENT":
        # Resident must only see active announcements for their assigned property or company-wide
        res_profile = current_user.resident_profile
        if not res_profile or not res_profile.property_id:
            return APIResponse(success=True, message="No property assigned.", data=[])
        query = query.filter(
            Announcement.is_active == True,
            sa.or_(
                Announcement.property_id == res_profile.property_id,
                Announcement.property_id.is_(None),
            ),
        )
    elif current_user.role.name == "PROPERTY_MANAGER":
        has_specific_access = db.query(UserPropertyAccess).filter_by(user_id=current_user.id).first() is not None
        if has_specific_access:
            allowed_prop_ids = [
                row.property_id
                for row in db.query(UserPropertyAccess.property_id).filter_by(user_id=current_user.id).all()
            ]
            query = query.filter(
                sa.or_(
                    Announcement.property_id.in_(allowed_prop_ids),
                    Announcement.property_id.is_(None),
                )
            )

        if property_id:
            verify_property_access(property_id, current_user, db)
            query = query.filter(Announcement.property_id == property_id)
        if is_active is not None:
            query = query.filter(Announcement.is_active == is_active)
    else:
        # SUPER_ADMIN / OWNER
        if property_id:
            query = query.filter(Announcement.property_id == property_id)
        if is_active is not None:
            query = query.filter(Announcement.is_active == is_active)

    announcements = query.order_by(Announcement.created_at.desc()).all()
    items = [_to_read_dto(a, db) for a in announcements]

    return APIResponse(
        success=True,
        message=f"Retrieved {len(items)} announcements.",
        data=items,
    )


@router.get("/resident", response_model=APIResponse[List[AnnouncementRead]], status_code=status.HTTP_200_OK)
def get_resident_announcements(
    active_resident: Resident = Depends(get_current_active_resident),
    db: Session = Depends(get_db),
):
    """Returns active announcements for the resident's assigned property and company-wide."""
    if not active_resident.property_id:
        return APIResponse(success=True, message="Resident not assigned to a property.", data=[])

    company_id = None
    if active_resident.property:
        company_id = active_resident.property.company_id
    elif active_resident.user:
        company_id = active_resident.user.company_id
    elif active_resident.property_id:
        prop = db.get(Property, active_resident.property_id)
        if prop:
            company_id = prop.company_id

    query = db.query(Announcement).filter(
        Announcement.is_active == True,
        sa.or_(
            Announcement.property_id == active_resident.property_id,
            Announcement.property_id.is_(None),
        ),
    )
    if company_id:
        query = query.filter(Announcement.company_id == company_id)

    announcements = query.order_by(Announcement.created_at.desc()).all()

    items = [_to_read_dto(a, db) for a in announcements]
    return APIResponse(
        success=True,
        message=f"Retrieved {len(items)} active announcements.",
        data=items,
    )


@router.get("/{announcement_id}", response_model=APIResponse[AnnouncementRead], status_code=status.HTTP_200_OK)
def get_announcement(
    announcement_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Retrieves single announcement."""
    ann = db.get(Announcement, announcement_id)
    if not ann or ann.company_id != current_user.company_id:
        raise NotFoundError("Announcement not found.")

    if current_user.role.name == "RESIDENT":
        res_profile = current_user.resident_profile
        if not res_profile or not ann.is_active:
            raise NotFoundError("Announcement not found.")
        if ann.property_id and ann.property_id != res_profile.property_id:
            raise NotFoundError("Announcement not found.")
    elif current_user.role.name == "PROPERTY_MANAGER" and ann.property_id:
        verify_property_access(ann.property_id, current_user, db)

    return APIResponse(
        success=True,
        message="Announcement retrieved successfully.",
        data=_to_read_dto(ann, db),
    )


@router.put("/{announcement_id}", response_model=APIResponse[AnnouncementRead], status_code=status.HTTP_200_OK)
def update_announcement(
    announcement_id: uuid.UUID,
    payload: AnnouncementUpdate,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "ADMIN", "OWNER", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Updates an existing announcement."""
    ann = db.get(Announcement, announcement_id)
    if not ann or ann.company_id != current_user.company_id:
        raise NotFoundError("Announcement not found.")

    if ann.property_id:
        verify_property_access(ann.property_id, current_user, db)

    if payload.property_id is not None:
        verify_property_access(payload.property_id, current_user, db)
        ann.property_id = payload.property_id

    if payload.title is not None:
        ann.title = payload.title.strip()
    if payload.content is not None:
        ann.content = payload.content.strip()
    if payload.is_active is not None:
        ann.is_active = payload.is_active

    db.commit()
    db.refresh(ann)

    record_audit_log(
        db=db,
        action="UPDATE_ANNOUNCEMENT",
        resource_type="announcements",
        user_id=current_user.id,
        user_email=current_user.email,
        user_role=current_user.role.name if current_user.role else None,
        property_id=ann.property_id,
        resource_id=str(ann.id),
        details={"title": ann.title, "is_active": ann.is_active},
    )

    return APIResponse(
        success=True,
        message=f"Announcement '{ann.title}' updated successfully.",
        data=_to_read_dto(ann, db),
    )


@router.patch("/{announcement_id}/status", response_model=APIResponse[AnnouncementRead], status_code=status.HTTP_200_OK)
def update_announcement_status(
    announcement_id: uuid.UUID,
    payload: AnnouncementStatusUpdate,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "ADMIN", "OWNER", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Toggles or sets active/inactive status."""
    ann = db.get(Announcement, announcement_id)
    if not ann or ann.company_id != current_user.company_id:
        raise NotFoundError("Announcement not found.")

    if ann.property_id:
        verify_property_access(ann.property_id, current_user, db)

    ann.is_active = payload.is_active
    db.commit()
    db.refresh(ann)

    record_audit_log(
        db=db,
        action="UPDATE_ANNOUNCEMENT_STATUS",
        resource_type="announcements",
        user_id=current_user.id,
        user_email=current_user.email,
        user_role=current_user.role.name if current_user.role else None,
        property_id=ann.property_id,
        resource_id=str(ann.id),
        details={"is_active": ann.is_active},
    )

    return APIResponse(
        success=True,
        message=f"Announcement status updated to {'Active' if ann.is_active else 'Inactive'}.",
        data=_to_read_dto(ann, db),
    )


@router.delete("/{announcement_id}", response_model=APIResponse[dict], status_code=status.HTTP_200_OK)
def delete_announcement(
    announcement_id: uuid.UUID,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "ADMIN", "OWNER", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Deletes an announcement permanently."""
    ann = db.get(Announcement, announcement_id)
    if not ann or ann.company_id != current_user.company_id:
        raise NotFoundError("Announcement not found.")

    if ann.property_id:
        verify_property_access(ann.property_id, current_user, db)

    db.delete(ann)
    db.commit()

    record_audit_log(
        db=db,
        action="DELETE_ANNOUNCEMENT",
        resource_type="announcements",
        user_id=current_user.id,
        user_email=current_user.email,
        user_role=current_user.role.name if current_user.role else None,
        property_id=ann.property_id,
        resource_id=str(ann.id),
        details={"title": ann.title},
    )

    return APIResponse(
        success=True,
        message="Announcement deleted successfully.",
        data={"id": str(announcement_id)},
    )
