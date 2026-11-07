import hashlib
import uuid
from datetime import datetime, timezone
from typing import Optional
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
from app.repositories.property_repository import PropertyRepository
from app.repositories.user_repository import UserRepository
from app.schemas.auth import TokenResponse
from app.schemas.property import PropertySummary
from app.schemas.user import RoleRead, UserProfile
from app.services.audit_service import record_audit_log


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


class AuthService:
    def __init__(self, db: Session):
        self.db = db
        self.user_repo = UserRepository(db)
        self.prop_repo = PropertyRepository(db)

    def authenticate_user(self, identifier: str, password: str) -> User:
        user = self.user_repo.get_by_identifier(identifier)
        if not user:
            raise AuthenticationError("Invalid email/phone or password.")
        if not user.is_active:
            raise AuthenticationError("Account is inactive. Please contact the administrator.")
        if not verify_password(password, user.password_hash):
            raise AuthenticationError("Invalid email/phone or password.")
        return user

    def validate_client_access(self, user: User, client_type: str) -> None:
        normalized = client_type.strip().lower()
        if normalized in ["admin_web", "admin_mobile"]:
            if user.role.name == "RESIDENT":
                raise PermissionDeniedError(
                    "Residents cannot access the Admin panel. Please log in via the Resident mobile application."
                )
        elif normalized == "resident_mobile":
            if user.role.name != "RESIDENT":
                raise PermissionDeniedError(
                    "Administrative accounts must log in via the Admin portal."
                )
        else:
            raise ValidationError(f"Invalid client_type '{client_type}'.")

    def build_user_profile(self, user: User) -> UserProfile:
        props = self.prop_repo.list_accessible_properties(user)
        summaries = [
            PropertySummary(
                id=p.id,
                name=p.name,
                code=p.code,
                property_type=p.property_type,
                city=p.city,
                is_active=p.is_active,
            )
            for p in props
        ]
        return UserProfile(
            id=user.id,
            company_id=user.company_id,
            full_name=user.full_name,
            email=user.email,
            phone=user.phone,
            role=RoleRead.model_validate(user.role),
            allowed_properties=summaries,
            is_active=user.is_active,
            is_verified=user.is_verified,
            approval_status=getattr(user, "approval_status", "APPROVED"),
            avatar_url=user.avatar_url,
            last_login_at=user.last_login_at,
            created_at=user.created_at,
        )

    def login(
        self,
        identifier: str,
        password: str,
        client_type: str = "admin_web",
        device_info: Optional[str] = None,
        ip_address: Optional[str] = None,
        user_agent: Optional[str] = None,
    ) -> TokenResponse:
        user = self.authenticate_user(identifier, password)
        self.validate_client_access(user, client_type)

        user.last_login_at = datetime.now(timezone.utc)
        props = self.prop_repo.list_accessible_properties(user)
        prop_ids = ["*"] if user.role.name == "SUPER_ADMIN" else [str(p.id) for p in props]

        claims = {
            "role": user.role.name,
            "company_id": str(user.company_id),
            "allowed_properties": prop_ids,
            "client_type": client_type,
        }
        access_token = create_access_token(subject=str(user.id), claims=claims)
        refresh_token = create_refresh_token(subject=str(user.id), claims={"client_type": client_type})

        decoded_refresh = decode_token(refresh_token)
        exp_timestamp = decoded_refresh.get("exp")
        expires_at = (
            datetime.fromtimestamp(exp_timestamp, tz=timezone.utc)
            if exp_timestamp
            else datetime.now(timezone.utc)
        )

        db_token = RefreshToken(
            user_id=user.id,
            token_hash=hash_token(refresh_token),
            client_type=client_type,
            device_info=device_info,
            expires_at=expires_at,
            is_revoked=False,
        )
        self.user_repo.save_refresh_token(db_token)

        record_audit_log(
            db=self.db,
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

        profile = self.build_user_profile(user)
        return TokenResponse(
            access_token=access_token,
            refresh_token=refresh_token,
            token_type="bearer",
            expires_in=settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60,
            user=profile,
        )

    def issue_tokens_for_admin(
        self,
        user: User,
        client_type: str = "admin_web",
        device_info: Optional[str] = None,
        ip_address: Optional[str] = None,
        user_agent: Optional[str] = None,
    ) -> TokenResponse:
        """Issues authentication tokens for an admin user authenticated via 2FA Super Key."""
        self.validate_client_access(user, client_type)

        user.last_login_at = datetime.now(timezone.utc)
        props = self.prop_repo.list_accessible_properties(user)
        prop_ids = ["*"] if user.role.name == "SUPER_ADMIN" else [str(p.id) for p in props]

        claims = {
            "role": user.role.name,
            "company_id": str(user.company_id),
            "allowed_properties": prop_ids,
            "client_type": client_type,
        }
        access_token = create_access_token(subject=str(user.id), claims=claims)
        refresh_token = create_refresh_token(subject=str(user.id), claims={"client_type": client_type})

        decoded_refresh = decode_token(refresh_token)
        exp_timestamp = decoded_refresh.get("exp")
        expires_at = (
            datetime.fromtimestamp(exp_timestamp, tz=timezone.utc)
            if exp_timestamp
            else datetime.now(timezone.utc)
        )

        db_token = RefreshToken(
            user_id=user.id,
            token_hash=hash_token(refresh_token),
            client_type=client_type,
            device_info=device_info,
            expires_at=expires_at,
            is_revoked=False,
        )
        self.user_repo.save_refresh_token(db_token)

        record_audit_log(
            db=self.db,
            action="AUTH_ADMIN_2FA_LOGIN",
            resource_type="auth",
            user_id=user.id,
            user_email=user.email,
            user_role=user.role.name,
            company_id=user.company_id,
            resource_id=str(user.id),
            details={"client_type": client_type, "auth_method": "SUPER_KEY_2FA"},
            ip_address=ip_address,
            user_agent=user_agent,
        )

        profile = self.build_user_profile(user)
        return TokenResponse(
            access_token=access_token,
            refresh_token=refresh_token,
            token_type="bearer",
            expires_in=settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60,
            user=profile,
        )

    def issue_tokens_for_resident(
        self,
        user: User,
        client_type: str = "resident_mobile",
        device_info: Optional[str] = None,
        ip_address: Optional[str] = None,
        user_agent: Optional[str] = None,
    ) -> TokenResponse:
        """Issues authentication tokens for a resident authenticated via OTP without password."""
        self.validate_client_access(user, client_type)

        if getattr(user, "approval_status", "APPROVED") == "PENDING_APPROVAL":
            raise PermissionDeniedError("Your registration is awaiting admin approval. Please wait for approval before logging in.")
        if getattr(user, "approval_status", "APPROVED") == "REJECTED":
            raise PermissionDeniedError("Your resident registration has been rejected. Please contact PG administrator.")
        if not user.is_active:
            raise PermissionDeniedError("Resident account is inactive. Please contact PG administrator.")

        user.last_login_at = datetime.now(timezone.utc)
        props = self.prop_repo.list_accessible_properties(user)
        prop_ids = ["*"] if user.role.name == "SUPER_ADMIN" else [str(p.id) for p in props]

        claims = {
            "role": user.role.name,
            "company_id": str(user.company_id),
            "allowed_properties": prop_ids,
            "client_type": client_type,
        }
        access_token = create_access_token(subject=str(user.id), claims=claims)
        refresh_token = create_refresh_token(subject=str(user.id), claims={"client_type": client_type})

        decoded_refresh = decode_token(refresh_token)
        exp_timestamp = decoded_refresh.get("exp")
        expires_at = (
            datetime.fromtimestamp(exp_timestamp, tz=timezone.utc)
            if exp_timestamp
            else datetime.now(timezone.utc)
        )

        db_token = RefreshToken(
            user_id=user.id,
            token_hash=hash_token(refresh_token),
            client_type=client_type,
            device_info=device_info,
            expires_at=expires_at,
            is_revoked=False,
        )
        self.user_repo.save_refresh_token(db_token)

        record_audit_log(
            db=self.db,
            action="AUTH_RESIDENT_LOGIN_OTP",
            resource_type="auth",
            user_id=user.id,
            user_email=user.email,
            user_role=user.role.name,
            company_id=user.company_id,
            resource_id=str(user.id),
            details={"client_type": client_type, "device_info": device_info, "method": "email_otp"},
            ip_address=ip_address,
            user_agent=user_agent,
        )

        profile = self.build_user_profile(user)
        return TokenResponse(
            access_token=access_token,
            refresh_token=refresh_token,
            token_type="bearer",
            expires_in=settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60,
            user=profile,
        )

    def refresh(self, refresh_token_str: str, client_type: Optional[str] = None) -> TokenResponse:
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
        db_token = self.user_repo.get_refresh_token(user_id, token_hash)

        if not db_token or db_token.is_revoked:
            raise AuthenticationError("Refresh token has been revoked or is invalid.")

        user = self.user_repo.get_by_id(user_id)
        if not user or not user.is_active:
            raise AuthenticationError("User is inactive or no longer exists.")

        resolved_client = client_type or db_token.client_type
        self.validate_client_access(user, resolved_client)

        props = self.prop_repo.list_accessible_properties(user)
        prop_ids = ["*"] if user.role.name == "SUPER_ADMIN" else [str(p.id) for p in props]

        claims = {
            "role": user.role.name,
            "company_id": str(user.company_id),
            "allowed_properties": prop_ids,
            "client_type": resolved_client,
        }
        new_access_token = create_access_token(subject=str(user.id), claims=claims)
        profile = self.build_user_profile(user)

        return TokenResponse(
            access_token=new_access_token,
            refresh_token=refresh_token_str,
            token_type="bearer",
            expires_in=settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60,
            user=profile,
        )

    def logout(self, user: User, refresh_token_str: str, ip_address: Optional[str] = None, user_agent: Optional[str] = None) -> None:
        token_hash = hash_token(refresh_token_str)
        self.user_repo.revoke_refresh_token(user.id, token_hash)
        record_audit_log(
            db=self.db,
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

    def change_password(self, user: User, current_password: str, new_password: str, ip_address: Optional[str] = None, user_agent: Optional[str] = None) -> None:
        if not verify_password(current_password, user.password_hash):
            raise AuthenticationError("Incorrect current password.")
        if current_password == new_password:
            raise ValidationError("New password cannot be identical to current password.")

        user.password_hash = get_password_hash(new_password)
        self.db.commit()

        record_audit_log(
            db=self.db,
            action="AUTH_PASSWORD_CHANGE",
            resource_type="user",
            user_id=user.id,
            user_email=user.email,
            user_role=user.role.name,
            company_id=user.company_id,
            resource_id=str(user.id),
            details={"status": "password_changed"},
            ip_address=ip_address,
            user_agent=user_agent,
        )
