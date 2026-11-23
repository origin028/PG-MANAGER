"""Fingerprint-machine attendance: device ingestion + owner views."""
import hmac
import uuid
from datetime import date, datetime, time, timedelta, timezone
from typing import List, Optional

import sqlalchemy as sa
from fastapi import APIRouter, Depends, Header, Query, status
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.exceptions import AuthenticationError, BadRequestError, NotFoundError
from app.db.session import get_db
from app.dependencies import require_roles, verify_property_access
from app.models.attendance import AttendanceLog
from app.models.property import Property
from app.models.resident import Resident
from app.models.user import User
from app.schemas.common import APIResponse

router = APIRouter()


class Punch(BaseModel):
    device_user_id: str = Field(min_length=1, max_length=64)
    punched_at: datetime
    direction: Optional[str] = Field(default=None, pattern="^(IN|OUT)$")


class PunchBatch(BaseModel):
    property_id: uuid.UUID
    punches: List[Punch] = Field(min_length=1, max_length=500)


def _utc(dt: datetime) -> datetime:
    return dt.replace(tzinfo=timezone.utc) if dt.tzinfo is None else dt.astimezone(timezone.utc)


@router.post("/punches", status_code=status.HTTP_200_OK)
def ingest_punches(
    payload: PunchBatch,
    x_device_key: str = Header("", alias="X-Device-Key"),
    db: Session = Depends(get_db),
):
    """Called by the fingerprint machine / bridge script. Authenticated with the shared device key."""
    configured = settings.ATTENDANCE_DEVICE_KEY
    if not configured or not hmac.compare_digest(x_device_key.encode(), configured.encode()):
        raise AuthenticationError("Invalid device key.")
    if not db.get(Property, payload.property_id):
        raise NotFoundError("Property not found.")

    residents = {
        r.biometric_id: r.id
        for r in db.scalars(
            sa.select(Resident).where(Resident.property_id == payload.property_id, Resident.biometric_id.is_not(None))
        )
    }
    accepted = duplicates = unmatched = 0
    for punch in sorted(payload.punches, key=lambda p: _utc(p.punched_at)):
        at = _utc(punch.punched_at)
        exists = db.scalar(
            sa.select(AttendanceLog.id).where(
                AttendanceLog.property_id == payload.property_id,
                AttendanceLog.device_user_id == punch.device_user_id,
                AttendanceLog.punched_at == at,
            )
        )
        if exists:
            duplicates += 1
            continue
        direction = punch.direction
        if direction is None:
            # Single-button machines send no direction: alternate IN/OUT per person per day.
            last = db.scalar(
                sa.select(AttendanceLog)
                .where(
                    AttendanceLog.property_id == payload.property_id,
                    AttendanceLog.device_user_id == punch.device_user_id,
                    AttendanceLog.punched_at >= datetime.combine(at.date(), time.min, tzinfo=timezone.utc),
                    AttendanceLog.punched_at < at,
                )
                .order_by(AttendanceLog.punched_at.desc())
            )
            direction = "OUT" if last is not None and last.direction == "IN" else "IN"
        resident_id = residents.get(punch.device_user_id)
        if resident_id is None:
            unmatched += 1
        db.add(
            AttendanceLog(
                property_id=payload.property_id,
                resident_id=resident_id,
                device_user_id=punch.device_user_id,
                punched_at=at,
                direction=direction,
            )
        )
        db.flush()  # session has autoflush off; later punches in this batch must see this one
        accepted += 1
    db.commit()
    return {"success": True, "data": {"accepted": accepted, "duplicates": duplicates, "unmatched": unmatched}}


@router.get("", status_code=status.HTTP_200_OK)
def list_attendance(
    property_id: uuid.UUID,
    day: Optional[date] = Query(None, description="Defaults to today (UTC)"),
    current_user: User = Depends(require_roles("SUPER_ADMIN", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Punches for one property and day, plus who is currently in / out."""
    verify_property_access(property_id, current_user, db)
    day = day or datetime.now(timezone.utc).date()
    start = datetime.combine(day, time.min, tzinfo=timezone.utc)
    rows = db.scalars(
        sa.select(AttendanceLog)
        .where(
            AttendanceLog.property_id == property_id,
            AttendanceLog.punched_at >= start,
            AttendanceLog.punched_at < start + timedelta(days=1),
        )
        .order_by(AttendanceLog.punched_at)
    ).all()
    names = {
        r.id: (r.user.full_name if r.user else None)
        for r in db.scalars(sa.select(Resident).where(Resident.property_id == property_id))
    }
    latest = {}
    for row in rows:
        latest[row.device_user_id] = row
    return APIResponse(
        success=True,
        message="Attendance retrieved.",
        data={
            "date": str(day),
            "punches": [
                {
                    "resident_id": str(r.resident_id) if r.resident_id else None,
                    "resident_name": names.get(r.resident_id),
                    "device_user_id": r.device_user_id,
                    "direction": r.direction,
                    "punched_at": r.punched_at.isoformat(),
                }
                for r in rows
            ],
            "currently_in": sum(1 for r in latest.values() if r.direction == "IN"),
            "currently_out": sum(1 for r in latest.values() if r.direction == "OUT"),
        },
    )


class BiometricAssign(BaseModel):
    biometric_id: Optional[str] = Field(default=None, max_length=64)


@router.put("/residents/{resident_id}/biometric-id", status_code=status.HTTP_200_OK)
def assign_biometric_id(
    resident_id: uuid.UUID,
    payload: BiometricAssign,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Links a resident to the user id enrolled on the fingerprint machine."""
    resident = db.get(Resident, resident_id)
    if not resident:
        raise NotFoundError("Resident not found.")
    verify_property_access(resident.property_id, current_user, db)
    bio = (payload.biometric_id or "").strip() or None
    if bio:
        clash = db.scalar(
            sa.select(Resident.id).where(
                Resident.property_id == resident.property_id, Resident.biometric_id == bio, Resident.id != resident.id
            )
        )
        if clash:
            raise BadRequestError("That fingerprint id is already assigned to another resident in this property.")
    resident.biometric_id = bio
    db.commit()
    return APIResponse(success=True, message="Fingerprint id updated.", data={"biometric_id": bio})
