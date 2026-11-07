import uuid
from typing import List, Optional, Tuple
import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.core.exceptions import ConflictError, NotFoundError, ValidationError
from app.core.security import get_password_hash
from app.models.role import Role
from app.models.property import Property
from app.models.user import User, UserPropertyAccess
from app.schemas.user import UserCreate, UserUpdate
from app.services.audit_service import record_audit_log


def list_users(
    db: Session,
    company_id: uuid.UUID,
    role_name: Optional[str] = None,
    is_active: Optional[bool] = None,
    page: int = 1,
    page_size: int = 20,
) -> Tuple[List[User], int]:
    """Lists users with filtering and pagination."""
    query = sa.select(User).where(User.company_id == company_id)

    if role_name:
        query = query.join(Role).where(Role.name == role_name)
    if is_active is not None:
        query = query.where(User.is_active == is_active)

    total = db.scalar(sa.select(sa.func.count()).select_from(query.subquery())) or 0

    offset = (page - 1) * page_size
    users = list(
        db.scalars(
            query.order_by(User.created_at.desc()).offset(offset).limit(page_size)
        ).all()
    )
    return users, total


def get_user_by_id(db: Session, user_id: uuid.UUID) -> User:
    user = db.scalar(sa.select(User).where(User.id == user_id))
    if not user:
        raise NotFoundError(f"User with ID '{user_id}' not found.")
    return user


def create_user(
    db: Session,
    company_id: uuid.UUID,
    data: UserCreate,
    created_by_user: Optional[User] = None,
) -> User:
    """Creates a new user, hashes password, assigns role and optional properties."""
    # Check phone uniqueness
    existing_phone = db.scalar(sa.select(User).where(User.phone == data.phone))
    if existing_phone:
        raise ConflictError(f"A user with phone number '{data.phone}' already exists.")

    # Check email uniqueness if provided
    if data.email:
        existing_email = db.scalar(
            sa.select(User).where(sa.func.lower(User.email) == data.email.lower())
        )
        if existing_email:
            raise ConflictError(f"A user with email '{data.email}' already exists.")

    # Verify role exists
    role = db.scalar(sa.select(Role).where(Role.id == data.role_id))
    if not role:
        raise NotFoundError("Specified role does not exist.")

    # Hash password
    pwd_hash = get_password_hash(data.password)

    new_user = User(
        company_id=company_id,
        role_id=data.role_id,
        full_name=data.full_name,
        email=data.email.lower() if data.email else None,
        phone=data.phone,
        password_hash=pwd_hash,
        is_active=True,
        is_verified=False,
    )
    db.add(new_user)
    db.flush()

    # Assign properties if provided
    if data.property_ids:
        for prop_id in data.property_ids:
            # Verify property belongs to company
            prop = db.scalar(
                sa.select(Property).where(
                    Property.id == prop_id, Property.company_id == company_id
                )
            )
            if not prop:
                raise ValidationError(f"Property '{prop_id}' is invalid or does not belong to company.")

            access = UserPropertyAccess(
                user_id=new_user.id,
                property_id=prop_id,
                access_level="MANAGER" if role.name == "PROPERTY_MANAGER" else "STAFF",
            )
            db.add(access)

    db.commit()
    db.refresh(new_user)

    if created_by_user:
        record_audit_log(
            db=db,
            action="USER_CREATED",
            resource_type="user",
            user_id=created_by_user.id,
            user_email=created_by_user.email,
            user_role=created_by_user.role.name,
            company_id=company_id,
            resource_id=str(new_user.id),
            details={"new_user_phone": new_user.phone, "role": role.name},
        )

    return new_user


def assign_user_properties(
    db: Session,
    user_id: uuid.UUID,
    property_ids: List[uuid.UUID],
    access_level: str = "MANAGER",
    assigned_by_user: Optional[User] = None,
) -> User:
    """Updates property assignments for a user."""
    user = get_user_by_id(db, user_id)

    # Delete existing property assignments
    stmt = sa.delete(UserPropertyAccess).where(UserPropertyAccess.user_id == user_id)
    db.execute(stmt)

    # Re-assign
    for prop_id in property_ids:
        prop = db.scalar(
            sa.select(Property).where(
                Property.id == prop_id, Property.company_id == user.company_id
            )
        )
        if not prop:
            raise ValidationError(f"Property ID '{prop_id}' not found in company portfolio.")

        access = UserPropertyAccess(
            user_id=user.id,
            property_id=prop_id,
            access_level=access_level,
        )
        db.add(access)

    db.commit()
    db.refresh(user)

    if assigned_by_user:
        record_audit_log(
            db=db,
            action="USER_PROPERTY_ACCESS_UPDATED",
            resource_type="user_property_access",
            user_id=assigned_by_user.id,
            user_email=assigned_by_user.email,
            user_role=assigned_by_user.role.name,
            company_id=user.company_id,
            resource_id=str(user.id),
            details={"assigned_properties": [str(pid) for pid in property_ids]},
        )

    return user
