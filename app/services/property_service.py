import uuid
from typing import List, Optional
import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.models.property import Property
from app.models.user import User, UserPropertyAccess


def get_properties_for_user(db: Session, user: User) -> List[Property]:
    """
    Returns properties accessible by the given user:
    - SUPER_ADMIN: All active properties in the company portfolio.
    - PROPERTY_MANAGER / STAFF: Explicitly assigned properties via user_property_access.
    - RESIDENT: Only properties assigned or scoped to resident.
    """
    if user.role.name == "SUPER_ADMIN":
        query = (
            sa.select(Property)
            .where(Property.company_id == user.company_id, Property.is_active == True)
            .order_by(Property.name.asc())
        )
        return list(db.scalars(query).all())

    # For managers, staff, or residents
    query = (
        sa.select(Property)
        .join(UserPropertyAccess, UserPropertyAccess.property_id == Property.id)
        .where(
            UserPropertyAccess.user_id == user.id,
            Property.is_active == True,
        )
        .order_by(Property.name.asc())
    )
    return list(db.scalars(query).all())


def check_user_property_access(db: Session, user: User, property_id: uuid.UUID) -> bool:
    """Verifies if a user has access to a specific property."""
    if user.role.name == "SUPER_ADMIN":
        prop = db.scalar(
            sa.select(Property).where(
                Property.id == property_id,
                Property.company_id == user.company_id,
                Property.is_active == True,
            )
        )
        return prop is not None

    access = db.scalar(
        sa.select(UserPropertyAccess).where(
            UserPropertyAccess.user_id == user.id,
            UserPropertyAccess.property_id == property_id,
        )
    )
    return access is not None


def get_property_by_id(db: Session, property_id: uuid.UUID) -> Optional[Property]:
    return db.scalar(sa.select(Property).where(Property.id == property_id))
