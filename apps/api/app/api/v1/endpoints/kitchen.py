"""Kitchen: scan resident meal passes and see today's meal counts."""
import uuid
from datetime import datetime, timezone

import sqlalchemy as sa
from fastapi import APIRouter, Depends, status
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.core.exceptions import NotFoundError
from app.db.session import get_db
from app.dependencies import require_roles
from app.models.meal_serving import MealServing
from app.models.property import Property
from app.models.resident import Resident
from app.models.user import User, UserPropertyAccess
from app.schemas.common import APIResponse
from app.services.meal_service import MEALS, current_meal, scan, tz

router = APIRouter()
KITCHEN_ROLES = ("SUPER_ADMIN", "PROPERTY_MANAGER", "STAFF", "KITCHEN")


def scanner_homes(db: Session, user: User) -> set[uuid.UUID]:
    """Homes this scanner may serve: explicitly assigned homes, else every home of their company."""
    assigned = set(db.scalars(sa.select(UserPropertyAccess.property_id).where(UserPropertyAccess.user_id == user.id)))
    if assigned and user.role.name != "SUPER_ADMIN":
        return assigned
    return set(db.scalars(sa.select(Property.id).where(Property.company_id == user.company_id)))


class ScanIn(BaseModel):
    token: str = Field(min_length=20, max_length=2000)


@router.post("/scan", status_code=status.HTTP_200_OK)
def scan_meal_pass(payload: ScanIn, current_user: User = Depends(require_roles(*KITCHEN_ROLES)), db: Session = Depends(get_db)):
    """Always 200 with a status the scanner screen shows as green (SERVED) or red (anything else)."""
    r = scan(db, payload.token, scanner_homes(db, current_user), current_user.id)
    res = r.resident
    return APIResponse(
        success=True,
        message=r.message,
        data={
            "status": r.status,
            "ok": r.status == "SERVED",
            "message": r.message,
            "meal": r.meal,
            "served_at": r.served_at.isoformat() if r.served_at else None,
            "resident": {
                "name": res.user.full_name if res and res.user else None,
                "room": None if not res or not res.room else res.room.room_number,
                "bed": None if not res or not res.bed else res.bed.bed_number,
            } if res else None,
        },
    )


@router.get("/today", status_code=status.HTTP_200_OK)
def kitchen_today(property_id: uuid.UUID, current_user: User = Depends(require_roles(*KITCHEN_ROLES)), db: Session = Depends(get_db)):
    if property_id not in scanner_homes(db, current_user):
        raise NotFoundError("Home not found.")
    now = datetime.now(timezone.utc)
    day = now.astimezone(tz()).date()
    current, upcoming = current_meal(db, property_id, now)
    counts = dict(db.execute(
        sa.select(MealServing.meal_type, sa.func.count()).where(MealServing.property_id == property_id, MealServing.meal_date == day)
        .group_by(MealServing.meal_type)).all())
    residents = db.scalar(sa.select(sa.func.count(Resident.id)).where(Resident.property_id == property_id, Resident.status == "ACTIVE")) or 0
    recent = db.execute(
        sa.select(MealServing, Resident).join(Resident, Resident.id == MealServing.resident_id)
        .where(MealServing.property_id == property_id, MealServing.meal_date == day)
        .order_by(MealServing.served_at.desc()).limit(25)).all()
    return APIResponse(
        success=True,
        message="Today's meals.",
        data={
            "date": day.isoformat(),
            "current_meal": current.meal if current else None,
            "next_meal": upcoming.meal if upcoming else None,
            "residents": residents,
            "served": {m: counts.get(m, 0) for m in MEALS},
            "recent": [
                {"name": r.user.full_name if r.user else None, "room": r.room.room_number if r.room else None,
                 "meal": s.meal_type, "served_at": s.served_at.isoformat()}
                for s, r in recent
            ],
        },
    )
