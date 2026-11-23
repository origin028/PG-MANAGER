import uuid
from typing import Optional
from sqlalchemy.orm import Session

from app.core.exceptions import NotFoundError
from app.models.resident import Resident
from app.repositories.resident_repository import ResidentRepository


class ResidentService:
    def __init__(self, db: Session):
        self.db = db
        self.repo = ResidentRepository(db)

    def get_resident(self, resident_id: uuid.UUID) -> Optional[Resident]:
        res = self.repo.get_by_id(resident_id)
        if not res:
            raise NotFoundError(f"Resident with ID '{resident_id}' not found.")
        return res

    def get_by_user_id(self, user_id: uuid.UUID) -> Optional[Resident]:
        return self.repo.get_by_user_id(user_id)
