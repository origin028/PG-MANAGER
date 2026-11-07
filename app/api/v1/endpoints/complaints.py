import uuid
from datetime import datetime, timezone
from typing import List, Optional

import sqlalchemy as sa
from fastapi import APIRouter, Depends, Query, Request, status
from pydantic import BaseModel, Field, field_validator
from sqlalchemy.orm import Session

from app.api.deps import get_current_user, get_db
from app.core.exceptions import ConflictError, NotFoundError, PermissionDeniedError, ValidationError
from app.models.complaint import Complaint
from app.models.resident import Resident
from app.models.room import Room
from app.models.user import User
from app.schemas.common import APIResponse
from app.services.audit_service import record_audit_log
from app.services.operations_service import get_permitted_property_ids

router = APIRouter()

PRIORITIES = {"LOW", "MEDIUM", "HIGH", "EMERGENCY"}
STATUSES = {"PENDING", "ASSIGNED", "IN_PROGRESS", "RESOLVED", "CLOSED"}


def _normalize(value: str) -> str:
    return "_".join(value.strip().upper().replace("-", " ").split())


def _status(value: str) -> str:
    normalized = _normalize(value)
    if normalized == "INPROGRESS":
        normalized = "IN_PROGRESS"
    return normalized


class ComplaintCreate(BaseModel):
    resident_id: Optional[uuid.UUID] = None
    room_id: Optional[uuid.UUID] = None
    issue: str = Field(..., min_length=5, max_length=2000)
    priority: str = Field("MEDIUM", description="LOW, MEDIUM, HIGH, EMERGENCY")

    @field_validator("priority")
    @classmethod
    def _validate_priority(cls, value: str) -> str:
        normalized = _status(value)
        if normalized not in PRIORITIES:
            raise ValueError("priority must be one of LOW, MEDIUM, HIGH, EMERGENCY")
        return normalized


class ComplaintUpdate(BaseModel):
    status: Optional[str] = Field(None, description="PENDING, ASSIGNED, IN_PROGRESS, RESOLVED, CLOSED")
    resolution_notes: Optional[str] = Field(None, max_length=2000)
    assigned_to_id: Optional[uuid.UUID] = None

    @field_validator("status")
    @classmethod
    def _validate_status(cls, value: Optional[str]) -> Optional[str]:
        if value is None:
            return None
        normalized = _status(value)
        if normalized not in STATUSES:
            raise ValueError("status must be one of PENDING, ASSIGNED, IN_PROGRESS, RESOLVED, CLOSED")
        return normalized


def _serialize(complaint: Complaint) -> dict:
    return {
        "id": str(complaint.id),
        "company_id": str(complaint.company_id),
        "property_id": str(complaint.property_id),
        "resident_id": str(complaint.resident_id),
        "room_id": str(complaint.room_id),
        "issue": complaint.issue,
        "priority": _status(complaint.priority),
        "status": _status(complaint.status),
        "assigned_to_id": str(complaint.assigned_to_id) if complaint.assigned_to_id else None,
        "resolution_notes": complaint.resolution_notes,
        "resolved_at": complaint.resolved_at.isoformat() if complaint.resolved_at else None,
        "created_at": complaint.created_at.isoformat() if complaint.created_at else None,
        "updated_at": complaint.updated_at.isoformat() if complaint.updated_at else None,
    }


def _resident_for_user(db: Session, user: User) -> Optional[Resident]:
    return db.scalar(
        sa.select(Resident).where(
            sa.or_(Resident.user_id == user.id, Resident.phone == user.phone)
        )
    )


@router.get("", response_model=APIResponse[List[dict]], status_code=status.HTTP_200_OK)
def get_complaints(
    property_id: Optional[uuid.UUID] = Query(None, description="Filter by property ID"),
    status_filter: Optional[str] = Query(None, alias="status", description="Filter by status"),
    priority: Optional[str] = Query(None, description="Filter by priority"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Lists complaints with role- and property-level scoping.

    Residents only ever see their own complaints; administrators and staff see
    complaints belonging to their assigned properties, never the whole company.
    """
    stmt = sa.select(Complaint)

    if current_user.role.name == "RESIDENT":
        resident = _resident_for_user(db, current_user)
        if not resident:
            return APIResponse(success=True, message="No complaints found.", data=[])
        stmt = stmt.where(Complaint.resident_id == resident.id)
    else:
        permitted = get_permitted_property_ids(db, current_user, property_id)
        if not permitted:
            return APIResponse(success=True, message="No complaints found.", data=[])
        stmt = stmt.where(Complaint.property_id.in_(permitted))

    if status_filter:
        stmt = stmt.where(Complaint.status == _status(status_filter))
    if priority:
        stmt = stmt.where(Complaint.priority == _status(priority))

    complaints = db.scalars(stmt.order_by(Complaint.created_at.desc())).all()
    result = [_serialize(c) for c in complaints]
    return APIResponse(success=True, message=f"Retrieved {len(result)} complaints.", data=result)


@router.post("", response_model=APIResponse[dict], status_code=status.HTTP_201_CREATED)
def create_complaint(
    payload: ComplaintCreate,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Creates a complaint. Residents may only file complaints for themselves."""
    if current_user.role.name == "RESIDENT":
        resident = _resident_for_user(db, current_user)
        if not resident:
            raise NotFoundError("No resident profile found for the authenticated user.")
        if payload.resident_id and payload.resident_id != resident.id:
            raise PermissionDeniedError("Residents can only file complaints for their own profile.")
    else:
        if not payload.resident_id:
            raise ValidationError("resident_id is required for administrative complaint creation.")
        resident = db.get(Resident, payload.resident_id)
        if not resident:
            raise NotFoundError("Resident not found.")
        get_permitted_property_ids(db, current_user, resident.property_id)

    if current_user.company_id != resident.company_id:
        raise PermissionDeniedError("Resident does not belong to your company.")

    room_id = payload.room_id or resident.room_id
    if not room_id:
        raise ValidationError("A room must be associated with the complaint.")
    if payload.room_id and resident.room_id and payload.room_id != resident.room_id:
        raise ValidationError("The specified room is not the resident's allocated room.")
    room = db.get(Room, room_id)
    if not room or room.property_id != resident.property_id:
        raise ValidationError("The specified room does not belong to the resident's property.")

    complaint = Complaint(
        company_id=resident.company_id,
        property_id=resident.property_id,
        resident_id=resident.id,
        room_id=room.id,
        issue=payload.issue.strip(),
        priority=payload.priority,
        status="PENDING",
    )
    db.add(complaint)
    db.commit()
    db.refresh(complaint)

    record_audit_log(
        db=db,
        action="COMPLAINT_CREATED",
        resource_type="complaint",
        resource_id=str(complaint.id),
        user_id=current_user.id,
        user_email=current_user.email,
        user_role=current_user.role.name,
        company_id=complaint.company_id,
        property_id=complaint.property_id,
        details={
            "resident_id": str(complaint.resident_id),
            "priority": complaint.priority,
            "status": complaint.status,
        },
        ip_address=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent"),
    )
    return APIResponse(success=True, message="Complaint created successfully.", data=_serialize(complaint))


@router.put("/{id}", response_model=APIResponse[dict], status_code=status.HTTP_200_OK)
def update_complaint(
    id: uuid.UUID,
    payload: ComplaintUpdate,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Updates complaint workflow state within the caller's property scope."""
    if current_user.role.name == "RESIDENT":
        raise PermissionDeniedError("Residents cannot update complaint workflow state.")

    complaint = db.get(Complaint, id)
    if not complaint:
        raise NotFoundError("Complaint not found.")
    get_permitted_property_ids(db, current_user, complaint.property_id)

    if payload.assigned_to_id:
        assignee = db.get(User, payload.assigned_to_id)
        if not assignee or assignee.company_id != complaint.company_id:
            raise ValidationError("Assigned user does not belong to this company.")
        complaint.assigned_to_id = assignee.id

    if payload.status:
        previous = _status(complaint.status)
        complaint.status = payload.status
        if payload.status in {"RESOLVED", "CLOSED"} and previous not in {"RESOLVED", "CLOSED"}:
            complaint.resolved_at = datetime.now(timezone.utc)
        elif payload.status not in {"RESOLVED", "CLOSED"}:
            complaint.resolved_at = None

    if payload.resolution_notes is not None:
        complaint.resolution_notes = payload.resolution_notes.strip() or None

    db.commit()
    db.refresh(complaint)

    record_audit_log(
        db=db,
        action="COMPLAINT_UPDATED",
        resource_type="complaint",
        resource_id=str(complaint.id),
        user_id=current_user.id,
        user_email=current_user.email,
        user_role=current_user.role.name,
        company_id=complaint.company_id,
        property_id=complaint.property_id,
        details={
            "status": complaint.status,
            "assigned_to_id": str(complaint.assigned_to_id) if complaint.assigned_to_id else None,
        },
        ip_address=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent"),
    )
    return APIResponse(success=True, message="Complaint updated successfully.", data=_serialize(complaint))
