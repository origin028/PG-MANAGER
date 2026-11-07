import hashlib
import uuid
from datetime import datetime, timezone
from typing import Optional
import sqlalchemy as sa
from sqlalchemy.orm import Session
import jwt

from app.core.config import settings
from app.core.exceptions import AuthenticationError, PermissionDeniedError, ValidationError
from app.core.security import (
    create_access_token,
    create_refresh_token,
    decode_token,
    get_password_hash,
    verify_password,
)
from app.models.user import RefreshToken, User
from app.schemas.auth import TokenResponse
from app.schemas.property import PropertySummary
from app.schemas.role import RoleRead
from app.schemas.user import UserProfile
from app.services.audit_service import record_audit_log
from app.services.property_service import get_properties_for_user


def hash_token(token: str) -> str:
    """Returns SHA-256 hash of a token for secure database lookup."""
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def authenticate_user(db: Session, identifier: str, password: str) -> User:
    """Authenticates user by email or phone and password."""
    cleaned_ident = identifier.strip()

    # Find by email (case-insensitive) or exact phone
    stmt = sa.select(User).where(
        sa.or_(
            sa.func.lower(User.email) == cleaned_ident.lower(),
            User.phone == cleaned_ident,
        )
    )
    user = db.scalar(stmt)

    if not user:
        raise AuthenticationError("Invalid email/phone or password.")

    if not user.is_active:
        raise AuthenticationError("Account is inactive. Please contact the administrator.")

    if not verify_password(password, user.password_hash):
        raise AuthenticationError("Invalid email/phone or password.")

    return user


def validate_client_access(user: User, client_type: str) -> None:
    """
    Enforces strict isolation between Admin experiences and Resident mobile app.
    """
    normalized_client = client_type.strip().lower()
    user_role = user.role.name

    if normalized_client in ["admin_web", "admin_mobile"]:
        if user_role == "RESIDENT":
            raise PermissionDeniedError(
                "Residents are not authorized to access Admin applications. Please use the Resident app."
            )
    elif normalized_client == "resident_mobile":
        if user_role != "RESIDENT":
            raise PermissionDeniedError(
                "Staff and Administrator accounts cannot log in to the Resident app. Please use the Admin app."
            )
    else:
        raise ValidationError(
            f"Invalid client_type '{client_type}'. Expected 'admin_web', 'admin_mobile', or 'resident_mobile'."
        )


def build_user_profile(db: Session, user: User) -> UserProfile:
    """Builds a full UserProfile schema with role and accessible properties."""
    accessible_properties = get_properties_for_user(db, user)
    property_summaries = [
        PropertySummary(
            id=p.id,
            name=p.name,
            code=p.code,
            property_type=p.property_type,
            city=p.city,
            is_active=p.is_active,
        )
        for p in accessible_properties
    ]

    return UserProfile(
        id=user.id,
        company_id=user.company_id,
        full_name=user.full_name,
        email=user.email,
        phone=user.phone,
        role=RoleRead.model_validate(user.role),
        allowed_properties=property_summaries,
        is_active=user.is_active,
        is_verified=user.is_verified,
        avatar_url=user.avatar_url,
        last_login_at=user.last_login_at,
        created_at=user.created_at,
    )


def login_user(
    db: Session,
    identifier: str,
    password: str,
    client_type: str = "admin_web",
    device_info: Optional[str] = None,
    ip_address: Optional[str] = None,
    user_agent: Optional[str] = None,
) -> TokenResponse:
    """Full login workflow with client validation, token issuance, and audit tracking."""
    user = authenticate_user(db, identifier, password)
    validate_client_access(user, client_type)

    # Update last login timestamp
    user.last_login_at = datetime.now(timezone.utc)

    # Get allowed property IDs
    properties = get_properties_for_user(db, user)
    prop_ids = ["*"] if user.role.name == "SUPER_ADMIN" else [str(p.id) for p in properties]

    # Create tokens
    claims = {
        "role": user.role.name,
        "company_id": str(user.company_id),
        "allowed_properties": prop_ids,
        "client_type": client_type,
    }
    access_token = create_access_token(subject=str(user.id), claims=claims)
    refresh_token = create_refresh_token(subject=str(user.id), claims={"client_type": client_type})

    # Store refresh token record
    token_hash = hash_token(refresh_token)
    decoded_refresh = decode_token(refresh_token)
    exp_timestamp = decoded_refresh.get("exp")
    expires_at = (
        datetime.fromtimestamp(exp_timestamp, tz=timezone.utc)
        if exp_timestamp
        else datetime.now(timezone.utc)
    )

    db_token = RefreshToken(
        user_id=user.id,
        token_hash=token_hash,
        client_type=client_type,
        device_info=device_info,
        expires_at=expires_at,
        is_revoked=False,
    )
    db.add(db_token)
    db.commit()

    # Record audit log
    record_audit_log(
        db=db,
        action="AUTH_LOGIN",
        resource_type="auth",
        user_id=user.id,
        user_email=user.email,
        user_role=user.role.name,
        company_id=user.company_id,
        resource_id=str(user.id),
        details={"client_type": client_type, "device_info": device_info},
        ip_address=ip_address,
        user_agent=user_agent,
    )

    profile = build_user_profile(db, user)

    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        token_type="bearer",
        expires_in=settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60,
        user=profile,
    )


def refresh_access_token(
    db: Session,
    refresh_token_str: str,
    client_type: Optional[str] = None,
) -> TokenResponse:
    """Validates refresh token and issues a fresh access token."""
    try:
        payload = decode_token(refresh_token_str)
    except jwt.PyJWTError as e:
        raise AuthenticationError(f"Invalid or expired refresh token: {str(e)}")

    if payload.get("type") != "refresh":
        raise AuthenticationError("Invalid token type. Refresh token required.")

    user_id_str = payload.get("sub")
    if not user_id_str:
        raise AuthenticationError("Invalid token subject.")

    user_id = uuid.UUID(user_id_str)
    token_hash = hash_token(refresh_token_str)

    db_token = db.scalar(
        sa.select(RefreshToken).where(
            RefreshToken.user_id == user_id,
            RefreshToken.token_hash == token_hash,
        )
    )

    if not db_token or db_token.is_revoked:
        raise AuthenticationError("Refresh token has been revoked or is invalid.")

    user = db.scalar(sa.select(User).where(User.id == user_id))
    if not user or not user.is_active:
        raise AuthenticationError("User is inactive or no longer exists.")

    resolved_client = client_type or db_token.client_type
    validate_client_access(user, resolved_client)

    properties = get_properties_for_user(db, user)
    prop_ids = ["*"] if user.role.name == "SUPER_ADMIN" else [str(p.id) for p in properties]

    claims = {
        "role": user.role.name,
        "company_id": str(user.company_id),
        "allowed_properties": prop_ids,
        "client_type": resolved_client,
    }
    new_access_token = create_access_token(subject=str(user.id), claims=claims)
    profile = build_user_profile(db, user)

    return TokenResponse(
        access_token=new_access_token,
        refresh_token=refresh_token_str,
        token_type="bearer",
        expires_in=settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60,
        user=profile,
    )


def revoke_token(
    db: Session,
    refresh_token_str: str,
    user: User,
    ip_address: Optional[str] = None,
    user_agent: Optional[str] = None,
) -> None:
    """Revokes a refresh token on logout."""
    token_hash = hash_token(refresh_token_str)
    db_token = db.scalar(
        sa.select(RefreshToken).where(
            RefreshToken.user_id == user.id,
            RefreshToken.token_hash == token_hash,
        )
    )
    if db_token:
        db_token.is_revoked = True
        db.commit()

    record_audit_log(
        db=db,
        action="AUTH_LOGOUT",
        resource_type="auth",
        user_id=user.id,
        user_email=user.email,
        user_role=user.role.name,
        company_id=user.company_id,
        resource_id=str(user.id),
        details={"logout_time": datetime.now(timezone.utc).isoformat()},
        ip_address=ip_address,
        user_agent=user_agent,
    )


def change_password(
    db: Session,
    user: User,
    current_password: str,
    new_password: str,
    ip_address: Optional[str] = None,
    user_agent: Optional[str] = None,
) -> None:
    """Changes password, revokes existing refresh tokens, and records audit trail."""
    if not verify_password(current_password, user.password_hash):
        raise AuthenticationError("Incorrect current password.")

    if current_password == new_password:
        raise ValidationError("New password cannot be identical to current password.")

    user.password_hash = get_password_hash(new_password)

    # Revoke all existing refresh tokens for security
    stmt = (
        sa.update(RefreshToken)
        .where(RefreshToken.user_id == user.id)
        .values(is_revoked=True)
    )
    db.execute(stmt)
    db.commit()

    record_audit_log(
        db=db,
        action="AUTH_PASSWORD_CHANGE",
        resource_type="user",
        user_id=user.id,
        user_email=user.email,
        user_role=user.role.name,
        company_id=user.company_id,
        resource_id=str(user.id),
        details={"status": "password_changed_all_sessions_revoked"},
        ip_address=ip_address,
        user_agent=user_agent,
    )
