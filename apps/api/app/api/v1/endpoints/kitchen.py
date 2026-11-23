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
from app.services.kitchen_access import require_kitchen_enabled

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
    require_kitchen_enabled(db, current_user.company_id)
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
    require_kitchen_enabled(db, current_user.company_id)
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


# ---------------------------------------------------------------------------
# Owner controls: switch the module on/off and manage kitchen staff logins.
# ---------------------------------------------------------------------------
OWNER_ROLES = ("SUPER_ADMIN", "PROPERTY_MANAGER")


def _staff(db: Session, company_id: uuid.UUID) -> list[User]:
    from app.models.role import Role

    return list(db.scalars(
        sa.select(User).join(Role, Role.id == User.role_id)
        .where(User.company_id == company_id, Role.name == "KITCHEN").order_by(User.created_at)))


def _staff_out(u: User) -> dict:
    return {"id": str(u.id), "name": u.full_name, "username": u.email, "phone": u.phone, "is_active": u.is_active}


@router.get("/settings", status_code=status.HTTP_200_OK)
def get_kitchen_settings(current_user: User = Depends(require_roles(*OWNER_ROLES)), db: Session = Depends(get_db)):
    from app.models.property import Company

    company = db.get(Company, current_user.company_id)
    return APIResponse(success=True, message="Kitchen settings.", data={
        "enabled": bool(company and company.kitchen_enabled),
        "staff": [_staff_out(u) for u in _staff(db, current_user.company_id)],
    })


class KitchenToggle(BaseModel):
    enabled: bool


@router.put("/settings", status_code=status.HTTP_200_OK)
def set_kitchen_settings(payload: KitchenToggle, current_user: User = Depends(require_roles(*OWNER_ROLES)), db: Session = Depends(get_db)):
    from app.models.property import Company
    from app.services.audit_service import record_audit_log

    company = db.get(Company, current_user.company_id)
    company.kitchen_enabled = payload.enabled
    db.commit()
    record_audit_log(db=db, action="KITCHEN_MODULE_ENABLED" if payload.enabled else "KITCHEN_MODULE_DISABLED", resource_type="company",
                     user_id=current_user.id, user_email=current_user.email, user_role=current_user.role.name,
                     company_id=company.id, resource_id=str(company.id), details={"enabled": payload.enabled})
    return APIResponse(success=True, message="Kitchen turned on." if payload.enabled else "Kitchen turned off.", data={"enabled": payload.enabled})


class StaffCreate(BaseModel):
    full_name: str = Field(min_length=2, max_length=150)
    username: str = Field(min_length=3, max_length=60, pattern=r"^[A-Za-z0-9._@-]+$")
    phone: str = Field(min_length=10, max_length=15)
    password: str = Field(min_length=6, max_length=128)


class StaffUpdate(BaseModel):
    password: str | None = Field(default=None, min_length=6, max_length=128)
    is_active: bool | None = None


@router.post("/staff", status_code=status.HTTP_201_CREATED)
def create_kitchen_staff(payload: StaffCreate, current_user: User = Depends(require_roles(*OWNER_ROLES)), db: Session = Depends(get_db)):
    import re

    from app.core.exceptions import ConflictError
    from app.core.security import get_password_hash
    from app.models.role import Role

    phone = re.sub(r"\D", "", payload.phone)[-10:]
    username = payload.username.strip().lower()
    if db.scalar(sa.select(User.id).where(sa.or_(sa.func.lower(User.email) == username, User.phone == phone))):
        raise ConflictError("That username or mobile number is already in use.")
    role = db.scalar(sa.select(Role).where(Role.name == "KITCHEN"))
    if role is None:  # databases created before the kitchen module
        from app.services.role_service import ensure_system_roles_exist

        ensure_system_roles_exist(db)
        role = db.scalar(sa.select(Role).where(Role.name == "KITCHEN"))
    u = User(company_id=current_user.company_id, role_id=role.id, email=username, phone=phone, full_name=payload.full_name.strip(),
             password_hash=get_password_hash(payload.password), is_active=True, approval_status="APPROVED")
    db.add(u)
    db.commit()
    return APIResponse(success=True, message="Kitchen login created.", data=_staff_out(u))


@router.patch("/staff/{staff_id}", status_code=status.HTTP_200_OK)
def update_kitchen_staff(staff_id: uuid.UUID, payload: StaffUpdate, current_user: User = Depends(require_roles(*OWNER_ROLES)), db: Session = Depends(get_db)):
    from app.core.security import get_password_hash
    from app.repositories.user_repository import UserRepository

    u = next((x for x in _staff(db, current_user.company_id) if x.id == staff_id), None)
    if not u:
        raise NotFoundError("Kitchen staff not found.")
    if payload.password:
        u.password_hash = get_password_hash(payload.password)
    if payload.is_active is not None:
        u.is_active = payload.is_active
    db.commit()
    if payload.password or payload.is_active is False:
        UserRepository(db).revoke_all_refresh_tokens(u.id)  # sign them out everywhere
    return APIResponse(success=True, message="Kitchen login updated.", data=_staff_out(u))
