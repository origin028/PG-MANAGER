import uuid
from typing import List, Optional
from sqlalchemy.orm import Session

from app.models.property import Property
from app.models.user import User
from app.repositories.property_repository import PropertyRepository


class PropertyService:
    def __init__(self, db: Session):
        self.db = db
        self.repo = PropertyRepository(db)

    def get_accessible_properties(self, user: User) -> List[Property]:
        return self.repo.list_accessible_properties(user)

    def get_property_by_id(self, property_id: uuid.UUID) -> Optional[Property]:
        return self.repo.get_by_id(property_id)

    def check_access(self, user: User, property_id: uuid.UUID) -> bool:
        return self.repo.check_access(user, property_id)
