"""Alerts for owners and managers: in-app inbox (bell), phone push (Expo) and, for sign-ups, email.

Who is alerted about a home: the company's owners (SUPER_ADMIN) and the managers who look after
that home (assigned to it, or with no assignments = all homes). Sending never raises: an alert
that cannot be delivered must not break the action that caused it.
"""
import json
import logging
import urllib.request
import uuid
from datetime import datetime, timezone
from typing import Iterable

import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.device_token import DeviceToken
from app.models.notification import Notification
from app.models.property import Property
from app.models.role import Role
from app.models.user import User, UserPropertyAccess

logger = logging.getLogger(__name__)
EXPO_PUSH_URL = "https://exp.host/--/api/v2/push/send"


def recipients(db: Session, property_id: uuid.UUID) -> list[User]:
    prop = db.get(Property, property_id)
    if not prop:
        return []
    users = db.scalars(
        sa.select(User).join(Role, User.role_id == Role.id).where(
            User.company_id == prop.company_id, User.is_active.is_(True), Role.name.in_(("SUPER_ADMIN", "PROPERTY_MANAGER"))
        )
    ).all()
    out = []
    for u in users:
        if u.role.name == "PROPERTY_MANAGER":
            assigned = db.scalars(sa.select(UserPropertyAccess.property_id).where(UserPropertyAccess.user_id == u.id)).all()
            if assigned and property_id not in assigned:
                continue
        out.append(u)
    return out


def notify_home(db: Session, property_id: uuid.UUID, kind: str, title: str, body: str, link: str, email: bool = False) -> int:
    """Alerts everyone who runs this home. Returns how many people were alerted."""
    try:
        people = recipients(db, property_id)
        now = datetime.now(timezone.utc)
        for u in people:
            db.add(Notification(user_id=u.id, title=title[:200], body=body, channel="PUSH", status="SENT", kind=kind, link=link, sent_at=now))
        db.commit()
        _push(db, [u.id for u in people], title, body, link)
        if email:
            _email(people, title, body)
        return len(people)
    except Exception:
        db.rollback()
        logger.exception("Could not create owner alert %s", kind)
        return 0


def _push(db: Session, user_ids: Iterable[uuid.UUID], title: str, body: str, link: str) -> None:
    if (settings.PUSH_PROVIDER or "").upper() != "EXPO":
        return
    ids = list(user_ids)
    if not ids:
        return
    tokens = db.scalars(sa.select(DeviceToken.device_token).where(DeviceToken.user_id.in_(ids), DeviceToken.is_active.is_(True))).all()
    messages = [{"to": t, "title": title, "body": body, "sound": "default", "data": {"link": link}}
                for t in tokens if t.startswith(("ExponentPushToken[", "ExpoPushToken["))]
    if not messages:
        return
    try:
        req = urllib.request.Request(EXPO_PUSH_URL, data=json.dumps(messages).encode(), method="POST",
                                     headers={"Content-Type": "application/json", "Accept": "application/json"})
        with urllib.request.urlopen(req, timeout=5):
            pass
    except Exception:
        logger.warning("Expo push failed for %d device(s).", len(messages))


def _email(people: list[User], title: str, body: str) -> None:
    from app.services.email_service import EmailService

    svc = EmailService()
    for u in people:
        if u.email and "@" in u.email:
            try:
                svc.send_notice(u.email, title, title, u.full_name, body, "Open the Origin Living app to review.")
            except Exception:
                logger.warning("Owner alert email failed.")
