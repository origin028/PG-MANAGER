import uuid
from datetime import datetime, timezone
from typing import List, Optional
from fastapi import APIRouter, Depends, Query, status
import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.core.exceptions import BadRequestError, NotFoundError, PermissionDeniedError
from app.dependencies import get_current_user, get_db, require_roles, verify_property_access
from app.models.complaint import Complaint
from app.models.property import Property
from app.models.resident import Resident
from app.models.staff import Staff
from app.models.user import User
from app.schemas.common import APIResponse
from app.schemas.complaint import (
    ComplaintAssignRequest,
    ComplaintCreate,
    ComplaintRead,
    ComplaintResolveRequest,
    ComplaintUpdate,
)
from app.services.audit_service import record_audit_log
from app.services.notification_service import NotificationService

router = APIRouter()


def _enrich_complaint(c: Complaint, db: Session) -> ComplaintRead:
    res = db.get(Resident, c.resident_id)
    res_user = res.user if res else None
    staff = db.get(Staff, c.assigned_staff_id) if c.assigned_staff_id else None
    prop = db.get(Property, c.property_id)

    return ComplaintRead(
        id=c.id,
        property_id=c.property_id,
        resident_id=c.resident_id,
        assigned_staff_id=c.assigned_staff_id,
        category=c.category,
        title=c.title,
        description=c.description,
        priority=c.priority,
        status=c.status,
        resolution_notes=c.resolution_notes,
        photo_path=c.photo_path,
        resolved_at=c.resolved_at if hasattr(c, "resolved_at") else None,
        created_at=c.created_at,
        updated_at=c.updated_at,
        assigned_staff_name=staff.name if staff else None,
        resident_name=res_user.full_name if res_user else None,
        resident_phone=res_user.phone if res_user else None,
        property_name=prop.name if prop else None,
    )


@router.get("", response_model=APIResponse[List[ComplaintRead]], status_code=status.HTTP_200_OK)
def list_complaints(
    property_id: Optional[uuid.UUID] = Query(None, description="Property ID filter"),
    status: Optional[str] = Query(None, description="Status filter (PENDING, ASSIGNED, IN_PROGRESS, RESOLVED, CLOSED)"),
    category: Optional[str] = Query(None, description="Category filter"),
    priority: Optional[str] = Query(None, description="Priority filter"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Lists maintenance complaints with optional filters."""
    query = sa.select(Complaint)

    if property_id:
        verify_property_access(property_id, current_user, db)
        query = query.where(Complaint.property_id == property_id)
    elif current_user.role.name not in ("SUPER_ADMIN", "OWNER"):
        allowed = getattr(current_user, "allowed_properties", []) or []
        allowed_uuids = [uuid.UUID(str(p)) for p in allowed if p]
        query = query.where(Complaint.property_id.in_(allowed_uuids))

    if status:
        query = query.where(Complaint.status == status.strip().upper())
    if category:
        query = query.where(Complaint.category == category.strip().upper())
    if priority:
        query = query.where(Complaint.priority == priority.strip().upper())

    query = query.order_by(Complaint.created_at.desc())
    complaints = db.scalars(query).all()
    items = [_enrich_complaint(c, db) for c in complaints]

    return APIResponse(
        success=True,
        message=f"Retrieved {len(items)} complaints.",
        data=items,
    )


@router.get("/{complaint_id}", response_model=APIResponse[ComplaintRead], status_code=status.HTTP_200_OK)
def get_complaint(
    complaint_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Retrieves full details of a single complaint."""
    complaint = db.get(Complaint, complaint_id)
    if not complaint:
        raise NotFoundError("Complaint not found.")

    if current_user.role.name == "RESIDENT":
        res = db.get(Resident, complaint.resident_id)
        if not res or res.user_id != current_user.id:
            raise PermissionDeniedError("Access denied.")
    else:
        verify_property_access(complaint.property_id, current_user, db)

    read_data = _enrich_complaint(complaint, db)
    return APIResponse(
        success=True,
        message="Complaint details retrieved successfully.",
        data=read_data,
    )


@router.patch("/{complaint_id}", response_model=APIResponse[ComplaintRead], status_code=status.HTTP_200_OK)
def update_complaint(
    complaint_id: uuid.UUID,
    payload: ComplaintUpdate,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "ADMIN", "OWNER", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Updates complaint attributes such as priority, status, or staff assignment."""
    complaint = db.get(Complaint, complaint_id)
    if not complaint:
        raise NotFoundError("Complaint not found.")

    verify_property_access(complaint.property_id, current_user, db)

    update_data = payload.model_dump(exclude_unset=True)
    if not update_data:
        return APIResponse(success=True, message="No changes requested.", data=_enrich_complaint(complaint, db))

    if "category" in update_data and update_data["category"]:
        complaint.category = update_data["category"].strip().upper()
    if "title" in update_data and update_data["title"]:
        complaint.title = update_data["title"].strip()
    if "description" in update_data and update_data["description"]:
        complaint.description = update_data["description"].strip()
    if "priority" in update_data and update_data["priority"]:
        complaint.priority = update_data["priority"].strip().upper()
    if "status" in update_data and update_data["status"]:
        complaint.status = update_data["status"].strip().upper()
    if "resolution_notes" in update_data:
        complaint.resolution_notes = update_data["resolution_notes"]
    if "assigned_staff_id" in update_data:
        if update_data["assigned_staff_id"]:
            staff = db.get(Staff, update_data["assigned_staff_id"])
            if not staff:
                raise NotFoundError("Assigned staff member not found.")
            complaint.assigned_staff_id = staff.id
            if complaint.status == "PENDING":
                complaint.status = "ASSIGNED"
        else:
            complaint.assigned_staff_id = None

    record_audit_log(
        db=db,
        action="UPDATE_COMPLAINT",
        resource_type="complaints",
        user_id=current_user.id,
        user_email=current_user.email,
        user_role=current_user.role.name if current_user.role else None,
        property_id=complaint.property_id,
        resource_id=str(complaint.id),
        details={"updated_fields": list(update_data.keys())},
    )

    db.commit()
    db.refresh(complaint)

    return APIResponse(
        success=True,
        message="Complaint updated successfully.",
        data=_enrich_complaint(complaint, db),
    )


@router.post("/{complaint_id}/assign", response_model=APIResponse[ComplaintRead], status_code=status.HTTP_200_OK)
def assign_complaint(
    complaint_id: uuid.UUID,
    payload: ComplaintAssignRequest,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "ADMIN", "OWNER", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Assigns a complaint to a specific staff member."""
    complaint = db.get(Complaint, complaint_id)
    if not complaint:
        raise NotFoundError("Complaint not found.")

    verify_property_access(complaint.property_id, current_user, db)

    staff = db.get(Staff, payload.assigned_staff_id)
    if not staff:
        raise NotFoundError("Staff member not found.")

    complaint.assigned_staff_id = staff.id
    if complaint.status == "PENDING":
        complaint.status = "ASSIGNED"

    record_audit_log(
        db=db,
        action="ASSIGN_COMPLAINT",
        resource_type="complaints",
        user_id=current_user.id,
        user_email=current_user.email,
        user_role=current_user.role.name if current_user.role else None,
        property_id=complaint.property_id,
        resource_id=str(complaint.id),
        details={"staff_id": str(staff.id), "staff_name": staff.name},
    )

    db.commit()
    db.refresh(complaint)

    # In-app notification to resident
    res = db.get(Resident, complaint.resident_id)
    if res and res.user_id:
        NotificationService(db).dispatch(
            user_id=res.user_id,
            title="Complaint Assigned",
            body=f"Your complaint '{complaint.title}' has been assigned to {staff.name}.",
            channel="PUSH",
        )

    return APIResponse(
        success=True,
        message=f"Complaint assigned to staff '{staff.name}'.",
        data=_enrich_complaint(complaint, db),
    )


@router.post("/{complaint_id}/resolve", response_model=APIResponse[ComplaintRead], status_code=status.HTTP_200_OK)
def resolve_complaint(
    complaint_id: uuid.UUID,
    payload: ComplaintResolveRequest,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "ADMIN", "OWNER", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Marks a complaint as RESOLVED or CLOSED and dispatches notification."""
    complaint = db.get(Complaint, complaint_id)
    if not complaint:
        raise NotFoundError("Complaint not found.")

    verify_property_access(complaint.property_id, current_user, db)

    complaint.status = payload.status.upper()
    complaint.resolution_notes = payload.resolution_notes.strip()
    complaint.resolved_at = datetime.now(timezone.utc)

    record_audit_log(
        db=db,
        action="RESOLVE_COMPLAINT",
        resource_type="complaints",
        user_id=current_user.id,
        user_email=current_user.email,
        user_role=current_user.role.name if current_user.role else None,
        property_id=complaint.property_id,
        resource_id=str(complaint.id),
        details={"resolution_notes": complaint.resolution_notes, "status": complaint.status},
    )

    db.commit()
    db.refresh(complaint)

    # In-app notification to resident
    res = db.get(Resident, complaint.resident_id)
    if res and res.user_id:
        NotificationService(db).dispatch(
            user_id=res.user_id,
            title="Complaint Resolved",
            body=f"Your complaint '{complaint.title}' has been marked as resolved: {complaint.resolution_notes}",
            channel="PUSH",
        )

    return APIResponse(
        success=True,
        message=f"Complaint marked as {complaint.status}.",
        data=_enrich_complaint(complaint, db),
    )
