import uuid
from typing import List, Optional, Tuple
import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.models.resident import Resident


class ResidentRepository:
    def __init__(self, db: Session):
        self.db = db

    def get_by_id(self, resident_id: uuid.UUID) -> Optional[Resident]:
        return self.db.get(Resident, resident_id)

    def get_by_user_id(self, user_id: uuid.UUID) -> Optional[Resident]:
        return self.db.scalar(sa.select(Resident).where(Resident.user_id == user_id))

    def list_by_property(
        self,
        property_id: uuid.UUID,
        status: Optional[str] = None,
        page: int = 1,
        page_size: int = 20,
    ) -> Tuple[List[Resident], int]:
        query = sa.select(Resident).where(Resident.property_id == property_id)
        if status:
            query = query.where(Resident.status == status)

        total = self.db.scalar(sa.select(sa.func.count()).select_from(query.subquery())) or 0
        offset = (page - 1) * page_size
        residents = list(
            self.db.scalars(
                query.order_by(Resident.created_at.desc()).offset(offset).limit(page_size)
            ).all()
        )
        return residents, total
