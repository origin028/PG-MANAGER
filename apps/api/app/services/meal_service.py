"""Meal passes: rotating signed QR tokens for residents, validated by kitchen staff at serving time."""
import uuid
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta, timezone
from typing import Optional
from zoneinfo import ZoneInfo

import jwt
import sqlalchemy as sa
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.food_menu import FoodMenu
from app.models.meal_serving import MealServing
from app.models.resident import Resident

MEALS = ("BREAKFAST", "LUNCH", "DINNER")
DEFAULT_WINDOWS = {"BREAKFAST": (time(7, 0), time(10, 0)), "LUNCH": (time(12, 0), time(15, 0)), "DINNER": (time(19, 30), time(22, 30))}
DAYS = ("MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY", "SUNDAY")


def tz() -> ZoneInfo:
    return ZoneInfo(settings.PG_TIMEZONE)


def _parse(t: Optional[str]) -> Optional[time]:
    if not t:
        return None
    for fmt in ("%I:%M %p", "%H:%M", "%I %p"):
        try:
            return datetime.strptime(t.strip().upper(), fmt).time()
        except ValueError:
            continue
    return None


@dataclass(frozen=True)
class MealWindow:
    meal: str
    start: datetime  # local, timezone-aware
    end: datetime


def windows_for(db: Session, property_id: uuid.UUID, day: date) -> list[MealWindow]:
    """Serving windows for a day from the property's menu timings (defaults when not set), with grace."""
    rows = db.scalars(
        sa.select(FoodMenu).where(FoodMenu.property_id == property_id, FoodMenu.day_of_week == DAYS[day.weekday()], FoodMenu.is_active.is_(True))
    ).all()
    by_meal = {r.meal_type.upper(): r for r in rows}
    grace = timedelta(minutes=settings.MEAL_GRACE_MINUTES)
    out = []
    for meal in MEALS:
        r = by_meal.get(meal)
        start = (_parse(r.start_time) if r else None) or DEFAULT_WINDOWS[meal][0]
        end = (_parse(r.end_time) if r else None) or DEFAULT_WINDOWS[meal][1]
        out.append(MealWindow(meal, datetime.combine(day, start, tz()) - grace, datetime.combine(day, end, tz()) + grace))
    return out


def current_meal(db: Session, property_id: uuid.UUID, now: Optional[datetime] = None) -> tuple[Optional[MealWindow], Optional[MealWindow]]:
    """(meal being served now, next meal today) in the PG's local time."""
    now = (now or datetime.now(timezone.utc)).astimezone(tz())
    wins = windows_for(db, property_id, now.date())
    current = next((w for w in wins if w.start <= now <= w.end), None)
    upcoming = next((w for w in wins if w.start > now), None)
    if current is None and settings.MEAL_DEMO_OPEN and not settings.is_production:
        # Demo: serve the next meal (or dinner late at night) right now.
        meal = upcoming.meal if upcoming else "DINNER"
        current = MealWindow(meal, now - timedelta(hours=1), now + timedelta(hours=1))
    return current, upcoming


def issue_pass(resident: Resident, meal: str, meal_day: date, now: Optional[datetime] = None) -> tuple[str, int]:
    now = now or datetime.now(timezone.utc)
    ttl = settings.MEAL_PASS_TTL_SECONDS
    token = jwt.encode(
        {"type": "meal_pass", "rid": str(resident.id), "pid": str(resident.property_id), "meal": meal,
         "d": meal_day.isoformat(), "iat": now, "exp": now + timedelta(seconds=ttl), "jti": uuid.uuid4().hex},
        settings.SECRET_KEY, algorithm=settings.JWT_ALGORITHM,
    )
    return token, ttl


@dataclass
class ScanResult:
    status: str  # SERVED | ALREADY_SERVED | EXPIRED | INVALID | WRONG_HOME | NOT_ACTIVE | NOT_SERVING_NOW | WRONG_MEAL
    message: str
    resident: Optional[Resident] = None
    meal: Optional[str] = None
    served_at: Optional[datetime] = None


def scan(db: Session, token: str, scanner_property_ids: Optional[set[uuid.UUID]], served_by: uuid.UUID, now: Optional[datetime] = None) -> ScanResult:
    """Validates a meal pass and records the serving exactly once. `scanner_property_ids=None` means any home."""
    now = now or datetime.now(timezone.utc)
    try:
        # Signature is always verified; expiry is checked below against the same clock as the meal window.
        claims = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.JWT_ALGORITHM],
                            options={"require": ["exp", "type", "rid", "meal", "d"], "verify_exp": False})
    except jwt.PyJWTError:
        return ScanResult("INVALID", "Not a valid Origin Living meal pass.")
    if now.timestamp() > float(claims["exp"]):
        return ScanResult("EXPIRED", "This pass has expired. Ask them to reopen the meal pass.")
    if claims.get("type") != "meal_pass":
        return ScanResult("INVALID", "Not a valid Origin Living meal pass.")

    resident = db.get(Resident, uuid.UUID(claims["rid"]))
    if not resident:
        return ScanResult("INVALID", "Resident not found.")
    if scanner_property_ids is not None and resident.property_id not in scanner_property_ids:
        return ScanResult("WRONG_HOME", "This resident does not live in this home.", resident)
    if resident.status != "ACTIVE" or not (resident.user and resident.user.is_active):
        return ScanResult("NOT_ACTIVE", "This person is not an active resident.", resident)

    current, _ = current_meal(db, resident.property_id, now)
    if current is None:
        return ScanResult("NOT_SERVING_NOW", "No meal is being served right now.", resident)
    meal_day = now.astimezone(tz()).date()
    if claims["meal"] != current.meal or claims["d"] != meal_day.isoformat():
        return ScanResult("WRONG_MEAL", f"This pass is for {claims['meal'].lower()}, not {current.meal.lower()}.", resident)

    existing = db.scalar(sa.select(MealServing).where(
        MealServing.resident_id == resident.id, MealServing.meal_date == meal_day, MealServing.meal_type == current.meal))
    if existing:
        return ScanResult("ALREADY_SERVED", f"Already had {current.meal.lower()} today.", resident, current.meal, existing.served_at)

    serving = MealServing(property_id=resident.property_id, resident_id=resident.id, meal_date=meal_day,
                          meal_type=current.meal, served_at=now, served_by_id=served_by)
    db.add(serving)
    try:
        db.commit()
    except IntegrityError:  # two scanners at once: the database keeps exactly one
        db.rollback()
        return ScanResult("ALREADY_SERVED", f"Already had {current.meal.lower()} today.", resident, current.meal)
    return ScanResult("SERVED", f"Enjoy your {current.meal.lower()}!", resident, current.meal, now)
