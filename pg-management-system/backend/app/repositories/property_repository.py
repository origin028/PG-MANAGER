import uuid
from typing import List, Optional
import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.models.property import Property
from app.models.user import User, UserPropertyAccess


class PropertyRepository:
    def __init__(self, db: Session):
        self.db = db

    def get_by_id(self, property_id: uuid.UUID) -> Optional[Property]:
        return self.db.get(Property, property_id)

    def get_by_code(self, code: str) -> Optional[Property]:
        return self.db.scalar(sa.select(Property).where(Property.code == code.upper()))

    def list_accessible_properties(self, user: User) -> List[Property]:
        if user.role.name == "SUPER_ADMIN":
            query = (
                sa.select(Property)
                .where(Property.company_id == user.company_id, Property.is_active == True)
                .order_by(Property.name.asc())
            )
            return list(self.db.scalars(query).all())

        query = (
            sa.select(Property)
            .join(UserPropertyAccess, UserPropertyAccess.property_id == Property.id)
            .where(UserPropertyAccess.user_id == user.id, Property.is_active == True)
            .order_by(Property.name.asc())
        )
        return list(self.db.scalars(query).all())

    def check_access(self, user: User, property_id: uuid.UUID) -> bool:
        if user.role.name == "SUPER_ADMIN":
            prop = self.get_by_id(property_id)
            return prop is not None and prop.company_id == user.company_id

        access = self.db.scalar(
            sa.select(UserPropertyAccess).where(
                UserPropertyAccess.user_id == user.id,
                UserPropertyAccess.property_id == property_id,
            )
        )
        return access is not None
