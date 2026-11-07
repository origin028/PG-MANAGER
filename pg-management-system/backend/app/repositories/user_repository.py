import uuid
from typing import List, Optional, Tuple
import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.models.user import User, RefreshToken, UserPropertyAccess
from app.models.role import Role


class UserRepository:
    def __init__(self, db: Session):
        self.db = db

    def get_by_id(self, user_id: uuid.UUID) -> Optional[User]:
        return self.db.get(User, user_id)

    def get_by_email(self, email: str) -> Optional[User]:
        return self.db.scalar(sa.select(User).where(sa.func.lower(User.email) == email.lower()))

    def get_by_email_exclude_user(self, email: str, exclude_user_id: uuid.UUID) -> Optional[User]:
        return self.db.scalar(
            sa.select(User).where(
                sa.func.lower(User.email) == email.strip().lower(),
                User.id != exclude_user_id,
            )
        )

    def get_by_phone(self, phone: str) -> Optional[User]:
        return self.db.scalar(sa.select(User).where(User.phone == phone))

    def get_by_identifier(self, identifier: str) -> Optional[User]:
        cleaned = identifier.strip()
        stmt = sa.select(User).where(
            sa.or_(
                sa.func.lower(User.email) == cleaned.lower(),
                User.phone == cleaned,
            )
        )
        return self.db.scalar(stmt)

    def list_users(
        self,
        company_id: uuid.UUID,
        role_name: Optional[str] = None,
        is_active: Optional[bool] = None,
        page: int = 1,
        page_size: int = 20,
    ) -> Tuple[List[User], int]:
        query = sa.select(User).where(User.company_id == company_id)
        if role_name:
            query = query.join(Role).where(Role.name == role_name)
        if is_active is not None:
            query = query.where(User.is_active == is_active)

        total = self.db.scalar(sa.select(sa.func.count()).select_from(query.subquery())) or 0
        offset = (page - 1) * page_size
        users = list(self.db.scalars(query.order_by(User.created_at.desc()).offset(offset).limit(page_size)).all())
        return users, total

    def save_refresh_token(self, token_record: RefreshToken) -> RefreshToken:
        self.db.add(token_record)
        self.db.commit()
        self.db.refresh(token_record)
        return token_record

    def get_refresh_token(self, user_id: uuid.UUID, token_hash: str) -> Optional[RefreshToken]:
        return self.db.scalar(
            sa.select(RefreshToken).where(
                RefreshToken.user_id == user_id,
                RefreshToken.token_hash == token_hash,
            )
        )

    def revoke_refresh_token(self, user_id: uuid.UUID, token_hash: str) -> None:
        token = self.get_refresh_token(user_id, token_hash)
        if token:
            token.is_revoked = True
            self.db.commit()
