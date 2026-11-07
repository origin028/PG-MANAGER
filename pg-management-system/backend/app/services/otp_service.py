import hashlib
import hmac
import re
import secrets
from datetime import datetime, timedelta, timezone
from typing import Dict, Optional
import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.core.exceptions import (
    AccountPendingApprovalError,
    AccountRejectedError,
    AuthenticationError,
    BadRequestError,
    ConflictError,
    NotFoundError,
    TooManyRequestsError,
)
from app.integrations.email import get_email_provider, mask_email
from app.integrations.sms import get_sms_provider
from app.models.otp_verification import OTPVerification
from app.models.user import User
from app.services.email_service import EmailService


def normalize_phone(phone: str) -> str:
    """Normalizes phone number to clean string. Accepts 10-digit Indian numbers or E.164 format."""
    cleaned = re.sub(r"[^\d+]", "", phone.strip())
    if cleaned.startswith("+91") and len(cleaned) == 13:
        cleaned = cleaned[3:]
    elif cleaned.startswith("91") and len(cleaned) == 12:
        cleaned = cleaned[2:]
    elif cleaned.startswith("0") and len(cleaned) == 11:
        cleaned = cleaned[1:]

    if not re.match(r"^[6-9]\d{9}$", cleaned):
        raise BadRequestError("Invalid mobile number format. A valid 10-digit Indian phone number is required.")
    return cleaned


def hash_otp(salt: str, otp: str) -> str:
    """Computes HMAC-SHA256 digest of OTP using cryptographic salt."""
    return hmac.new(salt.encode("utf-8"), otp.encode("utf-8"), hashlib.sha256).hexdigest()


class OTPService:
    COOLDOWN_SECONDS = 60
    EXPIRY_MINUTES = 10
    MAX_ATTEMPTS = 3

    def __init__(self, db: Session):
        self.db = db
        self.email_service = EmailService()

    def request_registration_otp(
        self,
        phone: str,
        email: str,
        full_name: Optional[str] = None,
    ) -> Dict[str, any]:
        """
        Validates mobile number and email, enforces cooldown rate-limiting,
        generates cryptographically secure salted OTP, and sends OTP to the provided email.
        """
        norm_phone = normalize_phone(phone)
        norm_email = email.strip().lower()

        # Prevent duplicate registration with existing active verified account
        existing_user = self.db.scalar(
            sa.select(User).where(
                sa.or_(
                    User.phone == norm_phone,
                    sa.func.lower(User.email) == norm_email,
                )
            )
        )
        if existing_user:
            if existing_user.phone == norm_phone:
                raise ConflictError("This mobile number is already registered. Please log in instead.")
            else:
                raise ConflictError("This email address is already registered.")

        now = datetime.now(timezone.utc)

        # Enforce cooldown rate-limiting between requests
        recent_otp = self.db.scalar(
            sa.select(OTPVerification)
            .where(
                OTPVerification.phone == norm_phone,
                OTPVerification.purpose == "RESIDENT_REGISTRATION",
                OTPVerification.created_at >= now - timedelta(seconds=self.COOLDOWN_SECONDS),
            )
            .order_by(OTPVerification.created_at.desc())
        )
        if recent_otp:
            time_passed = (now - recent_otp.created_at.replace(tzinfo=timezone.utc)).total_seconds()
            retry_after = max(1, int(self.COOLDOWN_SECONDS - time_passed))
            raise TooManyRequestsError(
                f"Please wait {retry_after} seconds before requesting a new OTP."
            )

        # Generate 6-digit secure OTP & cryptographic salt
        raw_otp = str(secrets.randbelow(900000) + 100000)
        salt = secrets.token_hex(16)
        digest = hash_otp(salt, raw_otp)
        expires_at = now + timedelta(minutes=self.EXPIRY_MINUTES)

        otp_record = OTPVerification(
            phone=norm_phone,
            otp_hash=digest,
            salt=salt,
            purpose="RESIDENT_REGISTRATION",
            attempts=0,
            max_attempts=self.MAX_ATTEMPTS,
            expires_at=expires_at,
            is_verified=False,
        )

        # Dispatch OTP strictly via email BEFORE saving to database
        try:
            self.email_service.send_registration_otp(
                to_email=norm_email,
                otp=raw_otp,
                full_name=full_name,
            )
        except Exception:
            self.db.rollback()
            raise

        # Invalidate prior active unverified registration OTPs for this phone
        self.db.execute(
            sa.update(OTPVerification)
            .where(
                OTPVerification.phone == norm_phone,
                OTPVerification.purpose == "RESIDENT_REGISTRATION",
                OTPVerification.is_verified == False,
            )
            .values(is_verified=True)
        )

        self.db.add(otp_record)
        self.db.commit()

        provider = get_email_provider()
        return {
            "phone": norm_phone,
            "email_masked": mask_email(norm_email),
            "expires_in_seconds": self.EXPIRY_MINUTES * 60,
            "cooldown_seconds": self.COOLDOWN_SECONDS,
            "is_mock": getattr(provider, "is_mock", False),
        }

    def verify_registration_otp(self, phone: str, otp: str, consume: bool = True) -> bool:
        """
        Validates registration OTP against secure salted hash in constant time.
        Enforces maximum attempt thresholds and single-use invalidation.
        """
        return self._verify_otp(phone=phone, otp=otp, purpose="RESIDENT_REGISTRATION", consume=consume)

    def request_login_otp(self, phone: str) -> Dict[str, any]:
        """
        Finds registered resident by mobile number, retrieves registered email,
        enforces cooldown, generates OTP, and dispatches OTP strictly via email.
        """
        norm_phone = normalize_phone(phone)

        # 1. Find registered resident user
        user = self.db.scalar(
            sa.select(User).where(User.phone == norm_phone)
        )
        if not user or user.role.name != "RESIDENT":
            raise NotFoundError("No registered resident found with this mobile number. Please register first.")

        if not user.email:
            raise BadRequestError("No email address registered for this resident. Please contact PG administrator.")

        # Check approval status on both User and Resident models
        resident = user.resident_profile
        app_status = getattr(user, "approval_status", "APPROVED")
        res_status = resident.status if resident else "ACTIVE"

        if app_status == "PENDING_APPROVAL" or res_status == "PENDING_APPROVAL":
            raise AccountPendingApprovalError(
                "Your registration is awaiting admin approval. Please wait for approval before logging in."
            )

        if app_status == "REJECTED" or res_status == "REJECTED":
            rejection_reason = resident.kyc_notes if resident and resident.kyc_notes else None
            msg = (
                f"Your resident registration was rejected: {rejection_reason}"
                if rejection_reason
                else "Your resident registration has been rejected. Please contact PG administrator."
            )
            raise AccountRejectedError(msg)

        if not user.is_active:
            raise AuthenticationError("Account is inactive. Please contact PG administrator.")

        now = datetime.now(timezone.utc)

        # 2. Enforce cooldown rate-limiting
        recent_otp = self.db.scalar(
            sa.select(OTPVerification)
            .where(
                OTPVerification.phone == norm_phone,
                OTPVerification.purpose == "RESIDENT_LOGIN",
                OTPVerification.created_at >= now - timedelta(seconds=self.COOLDOWN_SECONDS),
            )
            .order_by(OTPVerification.created_at.desc())
        )
        if recent_otp:
            time_passed = (now - recent_otp.created_at.replace(tzinfo=timezone.utc)).total_seconds()
            retry_after = max(1, int(self.COOLDOWN_SECONDS - time_passed))
            raise TooManyRequestsError(
                f"Please wait {retry_after} seconds before requesting a new login OTP."
            )

        # 3. Generate 6-digit secure OTP & salt
        raw_otp = str(secrets.randbelow(900000) + 100000)
        salt = secrets.token_hex(16)
        digest = hash_otp(salt, raw_otp)
        expires_at = now + timedelta(minutes=self.EXPIRY_MINUTES)

        otp_record = OTPVerification(
            phone=norm_phone,
            otp_hash=digest,
            salt=salt,
            purpose="RESIDENT_LOGIN",
            attempts=0,
            max_attempts=self.MAX_ATTEMPTS,
            expires_at=expires_at,
            is_verified=False,
        )

        # 4. Dispatch strictly via email BEFORE saving to database
        try:
            self.email_service.send_login_otp(
                to_email=user.email,
                otp=raw_otp,
                full_name=user.full_name,
            )
        except Exception:
            self.db.rollback()
            raise

        # 5. Invalidate prior unverified login OTPs for this phone
        self.db.execute(
            sa.update(OTPVerification)
            .where(
                OTPVerification.phone == norm_phone,
                OTPVerification.purpose == "RESIDENT_LOGIN",
                OTPVerification.is_verified == False,
            )
            .values(is_verified=True)
        )

        self.db.add(otp_record)
        self.db.commit()

        provider = get_email_provider()
        return {
            "phone": norm_phone,
            "email_masked": mask_email(user.email),
            "expires_in_seconds": self.EXPIRY_MINUTES * 60,
            "cooldown_seconds": self.COOLDOWN_SECONDS,
            "is_mock": getattr(provider, "is_mock", False),
        }

    def verify_login_otp(self, phone: str, otp: str, consume: bool = True) -> User:
        """
        Validates login OTP against stored hash, consumes OTP, and returns authenticated resident User.
        """
        norm_phone = normalize_phone(phone)
        self._verify_otp(phone=norm_phone, otp=otp, purpose="RESIDENT_LOGIN", consume=consume)

        user = self.db.scalar(
            sa.select(User).where(User.phone == norm_phone)
        )
        if not user or user.role.name != "RESIDENT":
            raise NotFoundError("Resident account not found.")

        resident = user.resident_profile
        app_status = getattr(user, "approval_status", "APPROVED")
        res_status = resident.status if resident else "ACTIVE"

        if app_status == "PENDING_APPROVAL" or res_status == "PENDING_APPROVAL":
            raise AccountPendingApprovalError(
                "Your registration is awaiting admin approval. Please wait for approval before logging in."
            )

        if app_status == "REJECTED" or res_status == "REJECTED":
            rejection_reason = resident.kyc_notes if resident and resident.kyc_notes else None
            msg = (
                f"Your resident registration was rejected: {rejection_reason}"
                if rejection_reason
                else "Your resident registration has been rejected. Please contact PG administrator."
            )
            raise AccountRejectedError(msg)

        if not user.is_active:
            raise AuthenticationError("Account is inactive. Please contact PG administrator.")

        return user

    def _verify_otp(self, phone: str, otp: str, purpose: str, consume: bool = True) -> bool:
        """Core verification logic with attempt limits and constant-time HMAC check."""
        norm_phone = normalize_phone(phone)
        now = datetime.now(timezone.utc)

        otp_record = self.db.scalar(
            sa.select(OTPVerification)
            .where(
                OTPVerification.phone == norm_phone,
                OTPVerification.purpose == purpose,
                OTPVerification.is_verified == False,
            )
            .order_by(OTPVerification.created_at.desc())
        )

        if not otp_record:
            raise BadRequestError("OTP has expired or does not exist. Please request a new verification code.")

        record_exp = otp_record.expires_at.replace(tzinfo=timezone.utc) if otp_record.expires_at.tzinfo is None else otp_record.expires_at
        if record_exp < now:
            raise BadRequestError("OTP has expired. Please request a new verification code.")

        if otp_record.attempts >= otp_record.max_attempts:
            raise BadRequestError("Maximum verification attempts exceeded. Please request a new verification code.")

        candidate_digest = hash_otp(otp_record.salt, otp.strip())
        if not hmac.compare_digest(candidate_digest, otp_record.otp_hash):
            otp_record.attempts += 1
            self.db.commit()
            remaining = max(0, otp_record.max_attempts - otp_record.attempts)
            if remaining == 0:
                raise BadRequestError("Maximum verification attempts exceeded. This OTP has been invalidated.")
            raise BadRequestError(f"Invalid verification code. {remaining} attempt(s) remaining.")

        if consume:
            otp_record.is_verified = True
            self.db.commit()

        return True

    def _verify_email_otp(self, email: str, otp: str, purpose: str, consume: bool = True) -> bool:
        """Email-based OTP verification with attempt limits and constant-time HMAC check."""
        norm_email = email.strip().lower()
        now = datetime.now(timezone.utc)

        otp_record = self.db.scalar(
            sa.select(OTPVerification)
            .where(
                OTPVerification.email == norm_email,
                OTPVerification.purpose == purpose,
                OTPVerification.is_verified == False,
            )
            .order_by(OTPVerification.created_at.desc())
        )

        if not otp_record:
            raise BadRequestError("Super Key has expired or does not exist. Please request a new verification code.")

        record_exp = otp_record.expires_at.replace(tzinfo=timezone.utc) if otp_record.expires_at.tzinfo is None else otp_record.expires_at
        if record_exp < now:
            raise BadRequestError("Super Key has expired. Please request a new verification code.")

        if otp_record.attempts >= otp_record.max_attempts:
            raise BadRequestError("Maximum verification attempts exceeded. Please request a new Super Key.")

        candidate_digest = hash_otp(otp_record.salt, otp.strip())
        if not hmac.compare_digest(candidate_digest, otp_record.otp_hash):
            otp_record.attempts += 1
            self.db.commit()
            remaining = max(0, otp_record.max_attempts - otp_record.attempts)
            if remaining == 0:
                raise BadRequestError("Maximum verification attempts exceeded. This Super Key has been invalidated.")
            raise BadRequestError(f"Invalid Super Key. {remaining} attempt(s) remaining.")

        if consume:
            otp_record.is_verified = True
            self.db.commit()

        return True

    def request_admin_registration_super_key(self, email: str, business_name: str) -> Dict[str, any]:
        """Dispatches registration Super Key to admin email with rate limiting and secure hashing."""
        norm_email = email.strip().lower()
        now = datetime.now(timezone.utc)

        # 1. Rate-limiting: Cooldown check
        recent_otp = self.db.scalar(
            sa.select(OTPVerification)
            .where(
                OTPVerification.email == norm_email,
                OTPVerification.purpose == "ADMIN_REGISTRATION",
                OTPVerification.is_verified == False,
            )
            .order_by(OTPVerification.created_at.desc())
        )
        if recent_otp:
            rec_created = recent_otp.created_at.replace(tzinfo=timezone.utc) if recent_otp.created_at.tzinfo is None else recent_otp.created_at
            elapsed = (now - rec_created).total_seconds()
            if elapsed < self.COOLDOWN_SECONDS:
                wait_sec = int(self.COOLDOWN_SECONDS - elapsed)
                raise TooManyRequestsError(f"Please wait {wait_sec} seconds before requesting a new Super Key.")

        # 2. Generate 6-digit secure code & salt
        raw_otp = str(secrets.randbelow(900000) + 100000)
        salt = secrets.token_hex(16)
        digest = hash_otp(salt, raw_otp)
        expires_at = now + timedelta(minutes=self.EXPIRY_MINUTES)

        otp_record = OTPVerification(
            email=norm_email,
            phone=None,
            otp_hash=digest,
            salt=salt,
            purpose="ADMIN_REGISTRATION",
            attempts=0,
            max_attempts=self.MAX_ATTEMPTS,
            expires_at=expires_at,
            is_verified=False,
        )

        # 3. Dispatch via email
        try:
            self.email_service.send_admin_registration_super_key(
                to_email=norm_email,
                super_key=raw_otp,
                business_name=business_name,
            )
        except Exception:
            self.db.rollback()
            raise

        # 4. Invalidate prior unverified registration OTPs for this email
        self.db.execute(
            sa.update(OTPVerification)
            .where(
                OTPVerification.email == norm_email,
                OTPVerification.purpose == "ADMIN_REGISTRATION",
                OTPVerification.is_verified == False,
            )
            .values(is_verified=True)
        )

        self.db.add(otp_record)
        self.db.commit()

        provider = get_email_provider()
        return {
            "email": norm_email,
            "email_masked": mask_email(norm_email),
            "expires_in_seconds": self.EXPIRY_MINUTES * 60,
            "cooldown_seconds": self.COOLDOWN_SECONDS,
            "is_mock": getattr(provider, "is_mock", False),
        }

    def verify_admin_registration_super_key(self, email: str, super_key: str, consume: bool = True) -> bool:
        """Validates admin registration Super Key against stored hash."""
        return self._verify_email_otp(email=email, otp=super_key, purpose="ADMIN_REGISTRATION", consume=consume)

    def request_admin_login_super_key(self, user: User) -> Dict[str, any]:
        """Dispatches login 2FA Super Key to admin registered email with cooldown and secure hashing."""
        norm_email = user.email.strip().lower()
        now = datetime.now(timezone.utc)

        # Cooldown check
        recent_otp = self.db.scalar(
            sa.select(OTPVerification)
            .where(
                OTPVerification.email == norm_email,
                OTPVerification.purpose == "ADMIN_LOGIN",
                OTPVerification.is_verified == False,
            )
            .order_by(OTPVerification.created_at.desc())
        )
        if recent_otp:
            rec_created = recent_otp.created_at.replace(tzinfo=timezone.utc) if recent_otp.created_at.tzinfo is None else recent_otp.created_at
            elapsed = (now - rec_created).total_seconds()
            if elapsed < self.COOLDOWN_SECONDS:
                wait_sec = int(self.COOLDOWN_SECONDS - elapsed)
                raise TooManyRequestsError(f"Please wait {wait_sec} seconds before requesting a new Super Key.")

        raw_otp = str(secrets.randbelow(900000) + 100000)
        salt = secrets.token_hex(16)
        digest = hash_otp(salt, raw_otp)
        expires_at = now + timedelta(minutes=self.EXPIRY_MINUTES)

        otp_record = OTPVerification(
            email=norm_email,
            phone=user.phone,
            otp_hash=digest,
            salt=salt,
            purpose="ADMIN_LOGIN",
            attempts=0,
            max_attempts=self.MAX_ATTEMPTS,
            expires_at=expires_at,
            is_verified=False,
        )

        try:
            self.email_service.send_admin_login_super_key(
                to_email=norm_email,
                super_key=raw_otp,
                admin_name=user.full_name,
            )
        except Exception:
            self.db.rollback()
            raise

        # Invalidate prior unverified login OTPs
        self.db.execute(
            sa.update(OTPVerification)
            .where(
                OTPVerification.email == norm_email,
                OTPVerification.purpose == "ADMIN_LOGIN",
                OTPVerification.is_verified == False,
            )
            .values(is_verified=True)
        )

        self.db.add(otp_record)
        self.db.commit()

        provider = get_email_provider()
        return {
            "email": norm_email,
            "email_masked": mask_email(norm_email),
            "expires_in_seconds": self.EXPIRY_MINUTES * 60,
            "cooldown_seconds": self.COOLDOWN_SECONDS,
            "is_mock": getattr(provider, "is_mock", False),
        }

    def verify_admin_login_super_key(self, email: str, super_key: str, consume: bool = True) -> User:
        """Validates login 2FA Super Key, consumes code, and returns authenticated admin User."""
        norm_email = email.strip().lower()
        self._verify_email_otp(email=norm_email, otp=super_key, purpose="ADMIN_LOGIN", consume=consume)

        user = self.db.scalar(
            sa.select(User).where(User.email == norm_email)
        )
        if not user:
            raise NotFoundError("Administrator account not found.")

        return user
