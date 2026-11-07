from fastapi import APIRouter, Depends, Request, status
from sqlalchemy.orm import Session

from app.api.deps import get_current_user, get_db
from app.models.user import User
from app.schemas.auth import (
    LoginRequest,
    PasswordChangeRequest,
    RefreshRequest,
    TokenResponse,
)
from app.schemas.common import APIResponse
from app.schemas.user import UserProfile
from app.services.auth_service import (
    build_user_profile,
    change_password,
    login_user,
    refresh_access_token,
    revoke_token,
)
from pydantic import AliasChoices, BaseModel, EmailStr, Field
from typing import Optional
import uuid
from datetime import datetime, timedelta, timezone
import secrets
import hashlib
import hmac
import sqlalchemy as sa
from app.core.config import settings
from app.core.security import get_password_hash
from app.models.otp import OtpVerification
from app.models.company import Company
from app.models.role import Role
from app.core.exceptions import ValidationError, AuthenticationError, NotFoundError, ConflictError
from app.services.email_service import send_otp_email


router = APIRouter()


@router.post("/login", response_model=APIResponse[TokenResponse], status_code=status.HTTP_200_OK)
def login(
    payload: LoginRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    """
    Authenticate user across Admin Web, Admin Mobile, or Resident Mobile client.
    Enforces role separation: Residents cannot access Admin clients; Admins cannot access Resident app.
    """
    ip_address = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")

    token_data = login_user(
        db=db,
        identifier=payload.identifier,
        password=payload.password,
        client_type=payload.client_type,
        device_info=payload.device_info,
        ip_address=ip_address,
        user_agent=user_agent,
    )
    return APIResponse(
        success=True,
        message=f"Authenticated successfully as {token_data.user.role.display_name}.",
        data=token_data,
    )


@router.post("/refresh", response_model=APIResponse[TokenResponse], status_code=status.HTTP_200_OK)
def refresh(
    payload: RefreshRequest,
    db: Session = Depends(get_db),
):
    """
    Refreshes access token using a valid, unrevoked refresh token.
    """
    token_data = refresh_access_token(
        db=db,
        refresh_token_str=payload.refresh_token,
        client_type=payload.client_type,
    )
    return APIResponse(
        success=True,
        message="Token refreshed successfully.",
        data=token_data,
    )


@router.post("/logout", response_model=APIResponse[dict], status_code=status.HTTP_200_OK)
def logout(
    payload: RefreshRequest,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Logs out the user and revokes the submitted refresh token.
    """
    ip_address = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")

    revoke_token(
        db=db,
        refresh_token_str=payload.refresh_token,
        user=current_user,
        ip_address=ip_address,
        user_agent=user_agent,
    )
    return APIResponse(
        success=True,
        message="Logged out successfully. Refresh token revoked.",
        data={"user_id": str(current_user.id)},
    )


@router.get("/me", response_model=APIResponse[UserProfile], status_code=status.HTTP_200_OK)
def get_current_user_profile(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Returns full profile of the authenticated user, including role and accessible properties.
    """
    profile = build_user_profile(db, current_user)
    return APIResponse(
        success=True,
        message="Profile retrieved successfully.",
        data=profile,
    )


@router.post("/change-password", response_model=APIResponse[dict], status_code=status.HTTP_200_OK)
def update_password(
    payload: PasswordChangeRequest,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Allows authenticated user to change password. All active refresh sessions are revoked.
    """
    ip_address = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")

    change_password(
        db=db,
        user=current_user,
        current_password=payload.current_password,
        new_password=payload.new_password,
        ip_address=ip_address,
        user_agent=user_agent,
    )
    return APIResponse(
        success=True,
        message="Password updated successfully. All active sessions have been revoked.",
        data={"user_id": str(current_user.id)},
    )


class RegisterRequest(BaseModel):
    business_name: str = Field(..., min_length=2, max_length=150)
    email: EmailStr
    password: str = Field(..., min_length=8, max_length=128)
    city: str = Field(..., min_length=1, max_length=100)
    gender: Optional[str] = Field(None, max_length=20)
    dob: Optional[str] = Field(None, max_length=20)
    check_in_time: Optional[str] = Field(None, max_length=20)


class VerifyOtpRequest(BaseModel):
    email: EmailStr
    otp: str = Field(
        ...,
        min_length=4,
        max_length=10,
        validation_alias=AliasChoices("otp", "super_key"),
        description="One-time verification code",
    )


def _as_aware_utc(value: datetime) -> datetime:
    """Normalises naive datetimes read from SQLite into aware UTC datetimes."""
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _generate_unique_phone(db: Session) -> str:
    for _ in range(20):
        candidate = f"9{secrets.randbelow(10 ** 9):09d}"
        exists = db.scalar(sa.select(User).where(User.phone == candidate))
        if not exists:
            return candidate
    raise ConflictError("Unable to allocate a unique account phone number. Please retry.")


@router.post("/register", response_model=APIResponse[dict], status_code=status.HTTP_200_OK)
def register(
    payload: RegisterRequest,
    db: Session = Depends(get_db),
):
    """Registers a new PG owner account and issues an e-mail OTP.

    The account stays inactive until the OTP is verified. The response reports
    ``email_sent`` truthfully: when SMTP delivery is not configured the account
    is still created but no OTP e-mail is claimed to have been sent.
    """
    email = str(payload.email).strip().lower()

    existing = db.scalar(sa.select(User).where(User.email == email))
    if existing:
        raise ConflictError("Email already registered")

    owner_role = db.scalar(sa.select(Role).where(Role.name == "SUPER_ADMIN"))
    if not owner_role:
        raise ValidationError("Owner role is not configured. Run database seeding first.")

    company = Company(
        name=payload.business_name.strip(),
        code=f"COMP-{uuid.uuid4().hex[:8].upper()}",
        email=email,
        phone=None,
        address=payload.city.strip() or None,
        is_active=True,
    )
    db.add(company)
    db.flush()

    user = User(
        company_id=company.id,
        role_id=owner_role.id,
        email=email,
        phone=_generate_unique_phone(db),
        full_name=payload.business_name.strip(),
        password_hash=get_password_hash(payload.password),
        is_active=False,
        is_verified=False,
    )
    db.add(user)
    db.flush()

    # Only the most recently issued unused code may be redeemed.
    db.query(OtpVerification).filter(
        OtpVerification.email == email,
        OtpVerification.is_used == False,
    ).update({"is_used": True}, synchronize_session=False)

    otp_length = max(4, min(int(settings.OTP_LENGTH), 8))
    otp = f"{secrets.randbelow(10 ** otp_length):0{otp_length}d}"
    otp_record = OtpVerification(
        email=email,
        otp_hash=hashlib.sha256(otp.encode("utf-8")).hexdigest(),
        expires_at=datetime.now(timezone.utc) + timedelta(minutes=settings.OTP_EXPIRE_MINUTES),
        is_used=False,
        attempts=0,
    )
    db.add(otp_record)
    db.commit()
    db.refresh(user)
    db.refresh(otp_record)

    email_sent = send_otp_email(email, otp)
    message = (
        "Registration created and OTP e-mail sent."
        if email_sent
        else "Registration created, but e-mail delivery is not configured; no OTP was sent."
    )
    return APIResponse(
        success=True,
        message=message,
        data={
            "user_id": str(user.id),
            "email": email,
            "email_sent": email_sent,
            "otp_expires_at": otp_record.expires_at,
        },
    )


@router.post("/verify-otp", response_model=APIResponse[dict], status_code=status.HTTP_200_OK)
def verify_otp(
    payload: VerifyOtpRequest,
    db: Session = Depends(get_db),
):
    """Verifies an e-mail OTP, enforcing expiry and a bounded attempt count."""
    email = str(payload.email).strip().lower()

    otp_record = db.scalar(
        sa.select(OtpVerification)
        .where(
            OtpVerification.email == email,
            OtpVerification.is_used == False,
        )
        .order_by(OtpVerification.created_at.desc())
    )
    if not otp_record:
        raise AuthenticationError("Invalid or expired OTP")

    if _as_aware_utc(otp_record.expires_at) < datetime.now(timezone.utc):
        raise AuthenticationError("Invalid or expired OTP")

    if otp_record.attempts >= settings.OTP_MAX_ATTEMPTS:
        otp_record.is_used = True
        db.commit()
        raise AuthenticationError("Too many attempts. Request a new verification code.")

    submitted_hash = hashlib.sha256(payload.otp.strip().encode("utf-8")).hexdigest()
    if not hmac.compare_digest(submitted_hash, otp_record.otp_hash):
        otp_record.attempts += 1
        if otp_record.attempts >= settings.OTP_MAX_ATTEMPTS:
            otp_record.is_used = True
        db.commit()
        raise AuthenticationError("Invalid or expired OTP")

    user = db.scalar(sa.select(User).where(User.email == email))
    if not user:
        raise NotFoundError("No account found for this email address.")

    otp_record.is_used = True
    user.is_active = True
    user.is_verified = True
    db.commit()

    return APIResponse(
        success=True,
        message="OTP verified successfully. Your account is now active.",
        data={"user_id": str(user.id), "email": email, "is_verified": True},
    )

