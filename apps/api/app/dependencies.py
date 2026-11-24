import uuid
from typing import Callable, Optional
from fastapi import Depends, Header, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session
import sqlalchemy as sa
import jwt

from app.core.config import settings
from app.core.exceptions import AuthenticationError, NotFoundError, PermissionDeniedError
from app.core.security import decode_token
from app.db.session import get_db
from app.models.property import Company, Property
from app.models.role import Role
from app.models.user import User, UserPropertyAccess

security = HTTPBearer(auto_error=False)


# Kitchen staff only ever need these areas; everything else is refused centrally, so a
# forgotten role check on some endpoint can never expose resident or financial data to them.
KITCHEN_ALLOWED_PREFIXES = ("/api/v1/kitchen", "/api/v1/food-menus", "/api/v1/auth/", "/api/v1/properties")


def get_current_user(
    request: Request,
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
        raise AuthenticationError("Invalid access token.")

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

    if not user.is_active or getattr(user, "approval_status", "APPROVED") == "REJECTED":
        raise AuthenticationError("Account has been deactivated or rejected. Please contact administrator.")

    if user.role and user.role.name == "KITCHEN":
        if not request.url.path.startswith(KITCHEN_ALLOWED_PREFIXES):
            raise PermissionDeniedError("Kitchen accounts can only use the kitchen and menu screens.")
        from app.services.kitchen_access import require_kitchen_enabled

        require_kitchen_enabled(db, user.company_id)

    if user.role and user.role.name == "RESIDENT" and user.resident_profile is not None:
        from app.core.exceptions import PortalOffError
        from app.services import portal_service

        resident = user.resident_profile
        portal_service.enforce(db, resident)
        if not resident.portal_enabled and not request.url.path.startswith(portal_service.LOCKED_ALLOWED):
            raise PortalOffError(
                "Your app access is paused until your KYC is verified." if resident.portal_reason == portal_service.KYC_OVERDUE
                else "Your app access has been paused by your PG. Please contact them."
            )

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
    prop = db.get(Property, property_id)
    if not prop:
        raise NotFoundError(f"Target property '{property_id}' not found.")

    # Hard tenant boundary: nobody (owners included) can touch another company's property.
    if prop.company_id != user.company_id:
        raise PermissionDeniedError("Access to this property is not permitted.")

    if user.role.name == "SUPER_ADMIN":
        return

    if user.role.name == "RESIDENT":
        if not user.resident_profile or user.resident_profile.property_id != property_id:
            raise PermissionDeniedError(f"You do not have access rights for property '{property_id}'.")
        return

    # Check property assignment junction table
    has_specific_access = db.query(UserPropertyAccess).filter_by(user_id=user.id).first() is not None
    if has_specific_access:
        access = db.query(UserPropertyAccess).filter_by(
            user_id=user.id, property_id=property_id
        ).first()
        if not access:
            raise PermissionDeniedError(f"You do not have access rights for property '{property_id}'.")
        return


def accessible_property_ids(user: User, db: Session) -> list:
    """Every property this user may see, always inside the user's own company.

    Owners see the whole company, assigned managers/staff only their assigned homes,
    residents only their own home.
    """
    if user.role.name == "RESIDENT":
        rp = user.resident_profile
        return [rp.property_id] if rp and rp.property_id else []
    in_company = sa.select(Property.id).where(Property.company_id == user.company_id)
    if user.role.name != "SUPER_ADMIN":
        assigned = db.scalars(sa.select(UserPropertyAccess.property_id).where(UserPropertyAccess.user_id == user.id)).all()
        if assigned:
            in_company = in_company.where(Property.id.in_(assigned))
    return list(db.scalars(in_company).all())


def get_current_active_resident(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Validates that the authenticated user is an active, fully approved resident.
    Blocks pending, rejected, and suspended resident accounts from protected data.
    """
    import sqlalchemy as sa
    from app.models.resident import Resident

    if current_user.role.name != "RESIDENT":
        raise PermissionDeniedError("Only resident accounts can access this resource.")

    resident = db.scalar(sa.select(Resident).where(Resident.user_id == current_user.id))
    if not resident:
        raise PermissionDeniedError("Resident profile not found for this account.")

    # Strictly check approval status on both User and Resident models
    if getattr(current_user, "approval_status", "APPROVED") == "PENDING_APPROVAL" or resident.status == "PENDING_APPROVAL":
        raise PermissionDeniedError("Your account registration is pending admin approval.")

    if getattr(current_user, "approval_status", "APPROVED") == "REJECTED" or resident.status == "REJECTED":
        raise PermissionDeniedError("Your account registration was rejected by the property administrator.")

    if not current_user.is_active or resident.status != "ACTIVE":
        raise PermissionDeniedError("Resident account is inactive or suspended.")

    return resident
