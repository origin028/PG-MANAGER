"""The kitchen module is optional per company. Every kitchen entry point checks this switch."""
import uuid

from sqlalchemy.orm import Session

from app.core.exceptions import PermissionDeniedError
from app.models.property import Company

KITCHEN_OFF_MESSAGE = "The kitchen module is switched off. The owner can turn it on in the app."


def kitchen_enabled(db: Session, company_id: uuid.UUID) -> bool:
    company = db.get(Company, company_id)
    return bool(company and company.kitchen_enabled)


def require_kitchen_enabled(db: Session, company_id: uuid.UUID) -> None:
    if not kitchen_enabled(db, company_id):
        raise PermissionDeniedError(KITCHEN_OFF_MESSAGE)
