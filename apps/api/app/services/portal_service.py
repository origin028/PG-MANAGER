"""Resident app access ("portal") and the KYC deadline.

Rules
- A resident the owner adds gets a deadline (company setting, default 7 days) to finish KYC.
- KYC counts as done only when the owner marks it VERIFIED.
- Past the deadline without verified KYC, access turns off automatically (reason KYC_OVERDUE).
  It is enforced on every request (so it is exact to the minute) and by a daily job (which also
  sends the reminder 2 days before and the "access paused" email).
- The owner can switch access off or on at any time. Switching on a resident whose deadline has
  passed gives them a fresh deadline, otherwise they would be switched off again at once.
- Verifying KYC clears the deadline and reopens access that was closed for missing KYC.
- While access is off a resident can still sign in, see why, contact the PG and submit KYC.
"""
import logging
import math
from datetime import datetime, timedelta, timezone
from typing import Optional

import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.models.property import Company, Property
from app.models.resident import Resident

logger = logging.getLogger(__name__)

KYC_OVERDUE = "KYC_OVERDUE"
OWNER = "OWNER"
REMIND_BEFORE = timedelta(days=2)
OPEN_STATUSES = ("ACTIVE", "NOTICE_PERIOD")

# Paths a resident may still use while access is off (prefix match, under /api/v1).
LOCKED_ALLOWED = ("/api/v1/auth/", "/api/v1/resident/portal", "/api/v1/resident/kyc", "/api/v1/resident/property-contacts")


def _now(now: Optional[datetime] = None) -> datetime:
    return _aware(now) if now else datetime.now(timezone.utc)


def _aware(dt: Optional[datetime]) -> Optional[datetime]:
    return dt if dt is None or dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def deadline_days(db: Session, resident: Resident) -> int:
    prop = db.get(Property, resident.property_id)
    company = db.get(Company, prop.company_id) if prop else None
    return max(1, int(company.kyc_deadline_days)) if company and company.kyc_deadline_days else 7


def start_deadline(db: Session, resident: Resident, now: Optional[datetime] = None) -> None:
    """Starts (or restarts) the KYC clock. No clock once KYC is verified."""
    if resident.kyc_status == "VERIFIED":
        resident.kyc_due_at = None
        return
    resident.kyc_due_at = _now(now) + timedelta(days=deadline_days(db, resident))
    resident.kyc_reminder_sent_at = None


def is_overdue(resident: Resident, now: Optional[datetime] = None) -> bool:
    due = _aware(resident.kyc_due_at)
    return bool(due and resident.kyc_status != "VERIFIED" and _now(now) >= due)


def enforce(db: Session, resident: Resident, now: Optional[datetime] = None) -> bool:
    """Turns access off if the KYC deadline has passed. Returns True when it changed something."""
    if resident.portal_enabled and resident.status in OPEN_STATUSES and is_overdue(resident, now):
        resident.portal_enabled = False
        resident.portal_reason = KYC_OVERDUE
        resident.portal_changed_at = _now(now)
        db.commit()
        return True
    return False


def set_access(db: Session, resident: Resident, enabled: bool, now: Optional[datetime] = None) -> None:
    """Owner's on/off switch."""
    now = _now(now)
    if enabled:
        resident.portal_enabled = True
        resident.portal_reason = None
        if is_overdue(resident, now):
            start_deadline(db, resident, now)  # a fresh deadline, otherwise it would close again at once
    else:
        resident.portal_enabled = False
        resident.portal_reason = OWNER
    resident.portal_changed_at = now


def on_kyc_verified(resident: Resident, now: Optional[datetime] = None) -> None:
    resident.kyc_due_at = None
    if not resident.portal_enabled and resident.portal_reason == KYC_OVERDUE:
        resident.portal_enabled = True
        resident.portal_reason = None
        resident.portal_changed_at = _now(now)


def days_left(resident: Resident, now: Optional[datetime] = None) -> Optional[int]:
    due = _aware(resident.kyc_due_at)
    if not due or resident.kyc_status == "VERIFIED":
        return None
    return max(0, math.ceil((due - _now(now)).total_seconds() / 86400))


def kyc_submitted(resident: Resident) -> bool:
    return bool(resident.resident_selfie_path and (resident.passport_path or (resident.aadhaar_front_path and resident.pan_card_path)))


def state(resident: Resident, now: Optional[datetime] = None) -> dict:
    due = _aware(resident.kyc_due_at)
    return {
        "enabled": resident.portal_enabled,
        "reason": resident.portal_reason,
        "kyc_status": resident.kyc_status,
        "kyc_submitted": kyc_submitted(resident),
        "kyc_notes": resident.kyc_notes if resident.kyc_status == "REJECTED" else None,
        "kyc_due_at": due.isoformat() if due and resident.kyc_status != "VERIFIED" else None,
        "days_left": days_left(resident, now),
    }


def run_daily(db: Session, now: Optional[datetime] = None) -> dict:
    """Cron: switch off overdue residents and send reminders. Safe to run more than once a day."""
    from app.services.email_service import EmailService

    now = _now(now)
    email = EmailService()
    closed = reminded = 0
    rows = db.scalars(
        sa.select(Resident).where(
            Resident.portal_enabled.is_(True),
            Resident.kyc_due_at.is_not(None),
            Resident.kyc_status != "VERIFIED",
            Resident.status.in_(OPEN_STATUSES),
        )
    ).all()
    for r in rows:
        prop = db.get(Property, r.property_id)
        pg = prop.name if prop else "your PG"
        to = r.user.email if r.user and r.user.email else r.email
        if enforce(db, r, now):
            closed += 1
            from app.services.alert_service import notify_home

            notify_home(db, r.property_id, "ACCESS_PAUSED", f"Access paused: {r.full_name}",
                        f"{r.full_name}'s KYC wasn't verified in time at {pg}, so their app access is paused.", f"/manage/resident/{r.id}")
            if to:
                _safe(lambda: email.send_notice(
                    to, f"{pg}: your app access is paused", "Your app access is paused", r.full_name,
                    f"Your KYC at {pg} was not completed and verified in time, so your access to the app is paused. "
                    "You can still sign in to upload your documents. Once the owner verifies them, access opens again.",
                    "Questions? Please speak to your PG owner or manager."))
        elif _aware(r.kyc_due_at) - now <= REMIND_BEFORE and not r.kyc_reminder_sent_at:
            r.kyc_reminder_sent_at = now
            db.commit()
            reminded += 1
            if to:
                left = days_left(r, now)
                _safe(lambda: email.send_notice(
                    to, f"{pg}: please finish your KYC", "Please finish your KYC", r.full_name,
                    f"Your KYC at {pg} needs to be done within {left} day{'s' if left != 1 else ''}. Open the app and tap "
                    "'Finish your KYC' to add your details and ID photos. If it is not verified in time, your app access is paused.",
                    "It takes about two minutes."))
    return {"checked": len(rows), "access_paused": closed, "reminders_sent": reminded}


def _safe(send) -> None:
    try:
        send()
    except Exception:  # an email failure must never stop the job
        logger.exception("KYC deadline email failed.")
