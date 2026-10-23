import uuid
from typing import Callable, Optional
from fastapi import Depends, Header, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session
import jwt

from app.core.exceptions import AuthenticationError, PermissionDeniedError
from app.core.security import decode_token
from app.db.session import get_db
from app.models.property import Property
from app.models.user import User, UserPropertyAccess

security = HTTPBearer(auto_error=False)


def get_current_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(security),
    db: Session = Depends(get_db),
) -> User:
    """Validates the Bearer access token and returns the authenticated User."""
    if not credentials or not credentials.credentials:
        raise AuthenticationError("Authorization header with Bearer token is required.")

    token = credentials.credentials
    try:
        payload = decode_token(token)
    except jwt.ExpiredSignatureError:
        raise AuthenticationError("Access token has expired. Please refresh your session.")
    except jwt.PyJWTError as e:
        raise AuthenticationError(f"Invalid access token: {str(e)}")

    if payload.get("type") != "access":
        raise AuthenticationError("Invalid token type. Access token expected.")

    user_id_str = payload.get("sub")
    if not user_id_str:
        raise AuthenticationError("Token missing user subject.")

    try:
        user_id = uuid.UUID(user_id_str)
    except ValueError:
        raise AuthenticationError("Invalid user ID format in token.")

    user = db.get(User, user_id)
    if not user:
        raise AuthenticationError("User associated with token does not exist.")

    if not user.is_active:
        raise AuthenticationError("Account has been deactivated. Please contact administrator.")

    return user


def require_roles(*allowed_roles: str) -> Callable[[User], User]:
    """Dependency factory enforcing role-based access control."""

    def role_checker(current_user: User = Depends(get_current_user)) -> User:
        if current_user.role.name not in allowed_roles:
            raise PermissionDeniedError(
                f"Role '{current_user.role.name}' is not authorized. Required: {list(allowed_roles)}"
            )
        return current_user

    return role_checker


def get_property_context(
    x_property_id: Optional[str] = Header(None, alias="X-Property-Id"),
) -> Optional[uuid.UUID]:
    """Extracts optional X-Property-Id header for property-scoped requests."""
    if not x_property_id:
        return None
    try:
        return uuid.UUID(x_property_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Header 'X-Property-Id' is not a valid UUID format.",
        )


def verify_property_access(property_id: uuid.UUID, user: User, db: Session) -> None:
    """Verifies that the current user has access rights for the target property."""
    if user.role.name == "SUPER_ADMIN":
        prop = db.get(Property, property_id)
        if not prop or prop.company_id != user.company_id:
            raise PermissionDeniedError("Access to this property is not permitted.")
        return

    # Check property assignment junction table
    access = db.query(UserPropertyAccess).filter_by(
        user_id=user.id, property_id=property_id
    ).first()
    if not access:
        raise PermissionDeniedError(f"You do not have access rights for property '{property_id}'.")
