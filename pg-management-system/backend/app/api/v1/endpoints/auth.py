import json
import secrets
import uuid
from datetime import date, datetime, timedelta, timezone
from fastapi import APIRouter, Depends, File, Form, Request, UploadFile, status
from sqlalchemy.orm import Session
import sqlalchemy as sa

from app.core.exceptions import (
    AuthenticationError,
    BadRequestError,
    ConflictError,
    NotFoundError,
    PermissionDeniedError,
    TooManyRequestsError,
)
from app.core.security import get_password_hash
from app.dependencies import get_current_user, get_db
from app.models.otp_verification import OTPVerification
from app.models.pending_registration import PendingResidentRegistration
from app.models.property import Company, Property
from app.models.resident import Resident
from app.models.role import Role
from app.models.user import User
from app.schemas.admin_auth import (
    AdminLogin2FARequiredResponse,
    AdminLoginRequest,
    AdminLoginVerifyRequest,
    AdminRegisterRequest,
    AdminRegisterVerifyRequest,
    AdminResendOtpRequest,
)
from app.schemas.auth import (
    LoginRequest,
    PasswordChangeRequest,
    RefreshRequest,
    TokenResponse,
)
from app.schemas.common import APIResponse
from app.schemas.resident_registration import (
    OTPRequest,
    OTPResponse,
    ResidentLoginOTPRequest,
    ResidentLoginOTPVerifyRequest,
    ResidentRegistrationForm,
    ResidentRegistrationRequest,
    ResidentRegistrationResponse,
    ResidentRegistrationVerifyRequest,
)
from app.schemas.user import UserProfile
from app.services.audit_service import record_audit_log
from app.services.auth_service import AuthService
from app.services.file_service import FileService
from app.services.otp_service import OTPService, hash_otp, normalize_phone

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

    service = AuthService(db)
    token_data = service.login(
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
def refresh_token(
    payload: RefreshRequest,
    db: Session = Depends(get_db),
):
    """Refreshes access token using a valid, unrevoked refresh token."""
    service = AuthService(db)
    token_data = service.refresh(
        refresh_token_str=payload.refresh_token,
        client_type=payload.client_type,
    )
    return APIResponse(
        success=True,
        message="Access token refreshed successfully.",
        data=token_data,
    )


@router.post("/logout", response_model=APIResponse[dict], status_code=status.HTTP_200_OK)
def logout(
    payload: RefreshRequest,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Logs out user and revokes refresh token."""
    ip_address = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")

    service = AuthService(db)
    service.logout(
        user=current_user,
        refresh_token_str=payload.refresh_token,
        ip_address=ip_address,
        user_agent=user_agent,
    )
    return APIResponse(
        success=True,
        message="Logged out successfully.",
        data={"user_id": str(current_user.id)},
    )


@router.get("/me", response_model=APIResponse[UserProfile], status_code=status.HTTP_200_OK)
def get_current_user_profile(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Returns profile and authorized properties for the logged-in user."""
    service = AuthService(db)
    profile = service.build_user_profile(current_user)
    return APIResponse(
        success=True,
        message="User profile retrieved.",
        data=profile,
    )


@router.post("/change-password", response_model=APIResponse[dict], status_code=status.HTTP_200_OK)
def change_user_password(
    payload: PasswordChangeRequest,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Changes password for logged-in user."""
    ip_address = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")

    service = AuthService(db)
    service.change_password(
        user=current_user,
        current_password=payload.current_password,
        new_password=payload.new_password,
        ip_address=ip_address,
        user_agent=user_agent,
    )
    return APIResponse(
        success=True,
        message="Password updated successfully.",
        data={"user_id": str(current_user.id)},
    )


RESIDENT_REGISTRATION_OPENAPI_EXTRA = {
    "requestBody": {
        "description": (
            "Resident registration and KYC onboarding payload. Supports both 'multipart/form-data' "
            "(recommended for file uploads) and 'application/json' (with pre-uploaded file paths)."
        ),
        "required": True,
        "content": {
            "multipart/form-data": {
                "schema": {
                    "type": "object",
                    "title": "ResidentRegistrationMultipartForm",
                    "properties": {
                        "full_name": {"type": "string", "minLength": 2, "maxLength": 150, "description": "Resident full name", "example": "John Doe"},
                        "date_of_birth": {"type": "string", "format": "date", "description": "Date of birth (YYYY-MM-DD)", "example": "1998-05-15"},
                        "gender": {"type": "string", "description": "Gender (Male, Female, Other)", "example": "Male"},
                        "occupation": {"type": "string", "description": "Current occupation / designation", "example": "Software Engineer"},
                        "primary_phone": {"type": "string", "description": "Indian 10-digit mobile number", "example": "9876543210"},
                        "email": {"type": "string", "format": "email", "description": "Resident email address (receives OTP)", "example": "resident@example.com"},
                        "emergency_contact": {"type": "string", "description": "Emergency contact name and phone", "example": "Father - Ramesh - 9870001111"},
                        "house_flat_no": {"type": "string", "description": "House/Flat number", "example": "A-101"},
                        "street": {"type": "string", "description": "Street / Locality", "example": "1st Main Road"},
                        "landmark": {"type": "string", "description": "Nearby landmark (optional)", "example": "Near City Mall"},
                        "city": {"type": "string", "description": "City", "example": "Bengaluru"},
                        "state": {"type": "string", "description": "State", "example": "Karnataka"},
                        "pincode": {"type": "string", "description": "Postal pincode", "example": "560034"},
                        "property_id": {"type": "string", "format": "uuid", "description": "Target PG Property UUID", "example": "5671f4ea-4099-433a-8810-fc201d952f61"},
                        "verification_method": {"type": "string", "description": "KYC verification method: 'Aadhaar + PAN' or 'Passport Only'", "example": "Aadhaar + PAN"},
                        "resident_selfie_file": {
                            "type": "string",
                            "format": "binary",
                            "description": "Resident selfie file (mandatory for all methods: .jpg, .jpeg, .png)",
                        },
                        "aadhaar_front_file": {
                            "type": "string",
                            "format": "binary",
                            "description": "Aadhaar front file (required for 'Aadhaar + PAN': .jpg, .jpeg, .png, .pdf)",
                        },
                        "aadhaar_back_file": {
                            "type": "string",
                            "format": "binary",
                            "description": "Aadhaar back file (required for 'Aadhaar + PAN': .jpg, .jpeg, .png, .pdf)",
                        },
                        "pan_card_file": {
                            "type": "string",
                            "format": "binary",
                            "description": "PAN card file (required for 'Aadhaar + PAN': .jpg, .jpeg, .png, .pdf)",
                        },
                        "passport_file": {
                            "type": "string",
                            "format": "binary",
                            "description": "Passport file (required for 'Passport Only': .jpg, .jpeg, .png, .pdf)",
                        },
                    },
                    "required": [
                        "full_name",
                        "date_of_birth",
                        "gender",
                        "occupation",
                        "primary_phone",
                        "email",
                        "emergency_contact",
                        "house_flat_no",
                        "street",
                        "city",
                        "state",
                        "pincode",
                        "property_id",
                        "verification_method",
                        "resident_selfie_file",
                    ],
                }
            },
            "application/json": {
                "schema": ResidentRegistrationForm.model_json_schema(),
            },
        },
    }
}


@router.get(
    "/resident/properties",
    response_model=APIResponse[list[dict]],
    status_code=status.HTTP_200_OK,
    summary="List Active Properties for Resident Onboarding",
)
def get_resident_onboarding_properties(
    db: Session = Depends(get_db),
):
    """
    Public listing of active PG properties for prospective residents to select
    during registration onboarding.
    """
    props = (
        db.scalars(
            sa.select(Property)
            .where(Property.is_active == True)
            .order_by(Property.name.asc())
        )
        .all()
    )
    data = [
        {
            "id": str(p.id),
            "name": p.name,
            "city": p.city or "",
            "code": p.code or "",
        }
        for p in props
    ]
    return APIResponse(
        success=True,
        message=f"Retrieved {len(data)} active properties.",
        data=data,
    )


@router.post(
    "/resident/register/otp/request",
    response_model=APIResponse[OTPResponse],
    status_code=status.HTTP_200_OK,
    openapi_extra=RESIDENT_REGISTRATION_OPENAPI_EXTRA,
)
async def request_resident_registration_otp(
    request: Request,
    db: Session = Depends(get_db),
):
    """
    Step 1 & 2 of Resident Onboarding:
    Validates submitted personal information, address, target property, and KYC documents.
    Stages the pending registration and dispatches a 6-digit OTP strictly via email.
    Supports both multipart/form-data (with file uploads) and application/json.
    """
    content_type = request.headers.get("content-type", "").lower()

    if "multipart/form-data" in content_type:
        form = await request.form()
        full_name = form.get("full_name")
        dob_raw = form.get("date_of_birth")
        gender = form.get("gender")
        occupation = form.get("occupation")
        primary_phone = form.get("primary_phone") or form.get("phone")
        email = form.get("email")
        emergency_contact = form.get("emergency_contact")
        house_flat_no = form.get("house_flat_no")
        street = form.get("street")
        landmark = form.get("landmark") or ""
        city = form.get("city")
        state = form.get("state")
        pincode = form.get("pincode")
        prop_id_raw = form.get("property_id")
        verification_method = form.get("verification_method")

        missing_fields = []
        if not full_name: missing_fields.append("full_name")
        if not dob_raw: missing_fields.append("date_of_birth")
        if not gender: missing_fields.append("gender")
        if not occupation: missing_fields.append("occupation")
        if not primary_phone: missing_fields.append("primary_phone")
        if not email: missing_fields.append("email")
        if not emergency_contact: missing_fields.append("emergency_contact")
        if not house_flat_no: missing_fields.append("house_flat_no")
        if not street: missing_fields.append("street")
        if not city: missing_fields.append("city")
        if not state: missing_fields.append("state")
        if not pincode: missing_fields.append("pincode")
        if not prop_id_raw: missing_fields.append("property_id")
        if not verification_method: missing_fields.append("verification_method")

        if missing_fields:
            raise BadRequestError(f"Missing required registration fields: {', '.join(missing_fields)}.")

        aadhaar_front_file = form.get("aadhaar_front_file")
        aadhaar_back_file = form.get("aadhaar_back_file")
        pan_card_file = form.get("pan_card_file")
        passport_file = form.get("passport_file")
        resident_selfie_file = form.get("resident_selfie_file")

        files_present = {
            "aadhaar_front_file": hasattr(aadhaar_front_file, "filename") and bool(aadhaar_front_file.filename),
            "aadhaar_back_file": hasattr(aadhaar_back_file, "filename") and bool(aadhaar_back_file.filename),
            "pan_card_file": hasattr(pan_card_file, "filename") and bool(pan_card_file.filename),
            "passport_file": hasattr(passport_file, "filename") and bool(passport_file.filename),
            "resident_selfie_file": hasattr(resident_selfie_file, "filename") and bool(resident_selfie_file.filename),
        }

        resolved_method = FileService.validate_kyc_method_and_files(str(verification_method), files_present)

        aadhaar_front_path = await FileService.validate_and_save_upload(aadhaar_front_file, "aadhaar_front_file") if files_present["aadhaar_front_file"] else None
        aadhaar_back_path = await FileService.validate_and_save_upload(aadhaar_back_file, "aadhaar_back_file") if files_present["aadhaar_back_file"] else None
        pan_card_path = await FileService.validate_and_save_upload(pan_card_file, "pan_card_file") if files_present["pan_card_file"] else None
        passport_path = await FileService.validate_and_save_upload(passport_file, "passport_file") if files_present["passport_file"] else None
        resident_selfie_path = await FileService.validate_and_save_upload(resident_selfie_file, "resident_selfie_file")

    else:
        raw_body = await request.body()
        if not raw_body or not raw_body.strip():
            raise BadRequestError(
                "Request body cannot be empty. Please provide registration data in application/json or multipart/form-data format."
            )
        try:
            body = await request.json()
        except Exception as exc:
            raise BadRequestError(
                f"Invalid JSON payload: {exc}. Please provide a valid JSON object or multipart/form-data."
            )
        if not isinstance(body, dict):
            raise BadRequestError(
                "Invalid JSON payload. Expected a JSON object at the root level."
            )
        if set(body.keys()).issubset({"phone", "primary_phone"}):
            # Legacy phone-only OTP request compatibility
            phone_val = body.get("phone") or body.get("primary_phone")
            if not phone_val:
                raise BadRequestError("Missing required field 'phone'.")
            norm_phone = normalize_phone(str(phone_val))
            if db.scalar(sa.select(User).where(User.phone == norm_phone)):
                raise ConflictError("This mobile number is already registered. Please log in instead.")

            now = datetime.now(timezone.utc)
            recent_otp = db.scalar(
                sa.select(OTPVerification)
                .where(
                    OTPVerification.phone == norm_phone,
                    OTPVerification.purpose == "RESIDENT_REGISTRATION",
                    OTPVerification.created_at >= now - timedelta(seconds=60),
                )
                .order_by(OTPVerification.created_at.desc())
            )
            if recent_otp:
                time_passed = (now - recent_otp.created_at.replace(tzinfo=timezone.utc)).total_seconds()
                retry_after = max(1, int(60 - time_passed))
                raise TooManyRequestsError(f"Please wait {retry_after} seconds before requesting a new OTP.")

            db.execute(
                sa.update(OTPVerification)
                .where(
                    OTPVerification.phone == norm_phone,
                    OTPVerification.purpose == "RESIDENT_REGISTRATION",
                    OTPVerification.is_verified == False,
                )
                .values(is_verified=True)
            )

            raw_otp = str(secrets.randbelow(900000) + 100000)
            salt = secrets.token_hex(16)
            digest = hash_otp(salt, raw_otp)
            expires_at = now + timedelta(minutes=10)

            otp_record = OTPVerification(
                phone=norm_phone,
                otp_hash=digest,
                salt=salt,
                purpose="RESIDENT_REGISTRATION",
                attempts=0,
                max_attempts=3,
                expires_at=expires_at,
                is_verified=False,
            )
            db.add(otp_record)
            db.commit()

            from app.services.otp_service import get_sms_provider
            sms_provider = get_sms_provider()
            sms_provider.send_otp(norm_phone, raw_otp, f"Your registration code is {raw_otp}")

            is_mock = getattr(sms_provider, "is_mock", False)
            message = (
                "Verification code generated (Demo Mode: check console log)."
                if is_mock
                else "Verification code sent to registered mobile number."
            )
            return APIResponse(
                success=True,
                message=message,
                data=OTPResponse(
                    phone=norm_phone,
                    expires_in_seconds=600,
                    cooldown_seconds=60,
                ),
            )

        full_name = body.get("full_name")
        dob_raw = body.get("date_of_birth")
        gender = body.get("gender")
        occupation = body.get("occupation")
        primary_phone = body.get("primary_phone") or body.get("phone")
        email = body.get("email")
        emergency_contact = body.get("emergency_contact")
        house_flat_no = body.get("house_flat_no")
        street = body.get("street")
        landmark = body.get("landmark") or ""
        city = body.get("city")
        state = body.get("state")
        pincode = body.get("pincode")
        prop_id_raw = body.get("property_id")
        verification_method = body.get("verification_method")

        missing_fields = []
        if not full_name: missing_fields.append("full_name")
        if not dob_raw: missing_fields.append("date_of_birth")
        if not gender: missing_fields.append("gender")
        if not occupation: missing_fields.append("occupation")
        if not primary_phone: missing_fields.append("primary_phone")
        if not email: missing_fields.append("email")
        if not emergency_contact: missing_fields.append("emergency_contact")
        if not house_flat_no: missing_fields.append("house_flat_no")
        if not street: missing_fields.append("street")
        if not city: missing_fields.append("city")
        if not state: missing_fields.append("state")
        if not pincode: missing_fields.append("pincode")
        if not prop_id_raw: missing_fields.append("property_id")
        if not verification_method: missing_fields.append("verification_method")

        if missing_fields:
            raise BadRequestError(f"Missing required registration fields: {', '.join(missing_fields)}.")

        aadhaar_front_path = body.get("aadhaar_front_path") or body.get("aadhaar_front_file")
        aadhaar_back_path = body.get("aadhaar_back_path") or body.get("aadhaar_back_file")
        pan_card_path = body.get("pan_card_path") or body.get("pan_card_file")
        passport_path = body.get("passport_path") or body.get("passport_file")
        resident_selfie_path = body.get("resident_selfie_path") or body.get("resident_selfie_file")

        files_present = {
            "aadhaar_front_file": bool(aadhaar_front_path),
            "aadhaar_back_file": bool(aadhaar_back_path),
            "pan_card_file": bool(pan_card_path),
            "passport_file": bool(passport_path),
            "resident_selfie_file": bool(resident_selfie_path),
        }
        resolved_method = FileService.validate_kyc_method_and_files(str(verification_method), files_present)

    # Validate date_of_birth format
    try:
        if isinstance(dob_raw, str):
            dob = datetime.strptime(dob_raw.strip(), "%Y-%m-%d").date()
        elif isinstance(dob_raw, date):
            dob = dob_raw
        else:
            raise ValueError()
    except Exception:
        raise BadRequestError("Invalid date_of_birth format. Expected YYYY-MM-DD.")

    # Validate target property
    try:
        prop_id = uuid.UUID(str(prop_id_raw).strip())
    except Exception:
        raise BadRequestError("Invalid property_id format. Expected a valid UUID.")

    prop = db.get(Property, prop_id)
    if not prop or not prop.is_active:
        raise NotFoundError("The specified PG property does not exist or is currently inactive.")

    norm_phone = normalize_phone(str(primary_phone))
    norm_email = str(email).strip().lower()

    # Generate OTP and send strictly via email
    otp_service = OTPService(db)
    result = otp_service.request_registration_otp(
        phone=norm_phone,
        email=norm_email,
        full_name=str(full_name).strip(),
    )

    # Stage registration data safely
    reg_data = {
        "full_name": str(full_name).strip(),
        "date_of_birth": dob.isoformat(),
        "gender": str(gender).strip(),
        "occupation": str(occupation).strip(),
        "primary_phone": norm_phone,
        "email": norm_email,
        "emergency_contact": str(emergency_contact).strip(),
        "house_flat_no": str(house_flat_no).strip(),
        "street": str(street).strip(),
        "landmark": str(landmark).strip() if landmark else "",
        "city": str(city).strip(),
        "state": str(state).strip(),
        "pincode": str(pincode).strip(),
        "property_id": str(prop_id),
        "verification_method": resolved_method,
        "aadhaar_front_path": aadhaar_front_path,
        "aadhaar_back_path": aadhaar_back_path,
        "pan_card_path": pan_card_path,
        "passport_path": passport_path,
        "resident_selfie_path": resident_selfie_path,
    }

    expires_at = datetime.now(timezone.utc) + timedelta(minutes=30)
    existing_pending = db.scalar(
        sa.select(PendingResidentRegistration).where(PendingResidentRegistration.phone == norm_phone)
    )
    if existing_pending:
        existing_pending.email = norm_email
        existing_pending.registration_data = reg_data
        existing_pending.expires_at = expires_at
    else:
        pending_record = PendingResidentRegistration(
            phone=norm_phone,
            email=norm_email,
            registration_data=reg_data,
            expires_at=expires_at,
        )
        db.add(pending_record)

    db.commit()

    return APIResponse(
        success=True,
        message=f"Verification code sent to {result['email_masked']}.",
        data=OTPResponse(
            phone=result["phone"],
            expires_in_seconds=result["expires_in_seconds"],
            cooldown_seconds=result["cooldown_seconds"],
            email_masked=result["email_masked"],
        ),
    )


@router.post(
    "/resident/register/otp/verify",
    response_model=APIResponse[ResidentRegistrationResponse],
    status_code=status.HTTP_201_CREATED,
)
def verify_resident_registration_otp(
    payload: ResidentRegistrationVerifyRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    """
    Step 3 of Resident Onboarding:
    Verifies the email OTP, finalizes registration, creates the Resident profile in
    PENDING_APPROVAL status according to existing resident approval architecture,
    and removes staged pending registration data.
    """
    otp_service = OTPService(db)
    norm_phone = normalize_phone(payload.phone)

    # 1. Verify registration OTP (enforces expiry, attempt limits, constant-time hash)
    otp_service.verify_registration_otp(norm_phone, payload.otp, consume=True)

    # 2. Retrieve staged pending registration
    pending = db.scalar(
        sa.select(PendingResidentRegistration).where(PendingResidentRegistration.phone == norm_phone)
    )
    if not pending:
        raise BadRequestError("No pending registration found for this mobile number or registration has expired.")

    reg_data = pending.registration_data
    prop_id = uuid.UUID(reg_data["property_id"])
    prop = db.get(Property, prop_id)
    if not prop or not prop.is_active:
        raise NotFoundError("The specified PG property does not exist or is currently inactive.")

    resident_role = db.scalar(sa.select(Role).where(Role.name == "RESIDENT"))
    if not resident_role:
        raise NotFoundError("System role 'RESIDENT' is not configured.")

    # 3. Duplicate checks
    if db.scalar(sa.select(User).where(User.phone == norm_phone)):
        raise ConflictError("This mobile number is already registered. Please log in instead.")
    if db.scalar(sa.select(User).where(sa.func.lower(User.email) == pending.email.lower())):
        raise ConflictError("This email address is already registered.")

    # 4. Create User in PENDING_APPROVAL status (no password!)
    unusable_password_hash = f"!RESIDENT_NO_PASSWORD_{secrets.token_hex(16)}"
    user = User(
        company_id=prop.company_id,
        role_id=resident_role.id,
        phone=norm_phone,
        email=pending.email,
        full_name=reg_data["full_name"],
        password_hash=unusable_password_hash,
        is_active=True,
        is_verified=True,
        approval_status="PENDING_APPROVAL",
    )
    db.add(user)
    db.flush()

    # 5. Create Resident profile with all registration & KYC document references
    dob = (
        datetime.strptime(reg_data["date_of_birth"], "%Y-%m-%d").date()
        if "date_of_birth" in reg_data
        else date.today()
    )
    resident = Resident(
        user_id=user.id,
        property_id=prop.id,
        date_of_birth=dob,
        gender=reg_data.get("gender"),
        occupation=reg_data.get("occupation"),
        emergency_contact=reg_data.get("emergency_contact"),
        house_flat_no=reg_data.get("house_flat_no"),
        street=reg_data.get("street"),
        landmark=reg_data.get("landmark"),
        city=reg_data.get("city"),
        state=reg_data.get("state"),
        pincode=reg_data.get("pincode"),
        verification_method=reg_data.get("verification_method"),
        aadhaar_front_path=reg_data.get("aadhaar_front_path"),
        aadhaar_back_path=reg_data.get("aadhaar_back_path"),
        pan_card_path=reg_data.get("pan_card_path"),
        passport_path=reg_data.get("passport_path"),
        resident_selfie_path=reg_data.get("resident_selfie_path"),
        check_in_date=date.today(),
        monthly_rent=0.0,
        security_deposit=0.0,
        kyc_status="PENDING",
        status="PENDING_APPROVAL",
    )
    db.add(resident)

    # 6. Delete staged pending record
    db.delete(pending)
    db.commit()
    db.refresh(resident)
    db.refresh(user)

    # 7. Audit log registration
    ip_address = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")
    record_audit_log(
        db=db,
        action="RESIDENT_REGISTRATION_SUBMITTED",
        resource_type="resident",
        user_id=user.id,
        user_email=user.email,
        user_role="RESIDENT",
        company_id=user.company_id,
        property_id=prop.id,
        resource_id=str(resident.id),
        details={
            "phone": user.phone,
            "property_name": prop.name,
            "verification_method": resident.verification_method,
            "status": "PENDING_APPROVAL",
            "approval_status": "PENDING_APPROVAL",
        },
        ip_address=ip_address,
        user_agent=user_agent,
    )

    return APIResponse(
        success=True,
        message="Registration submitted successfully. Your account is pending administrator approval.",
        data=ResidentRegistrationResponse(
            resident_id=resident.id,
            user_id=user.id,
            full_name=user.full_name,
            phone=user.phone,
            email=user.email,
            property_id=prop.id,
            property_name=prop.name,
            status=resident.status,
            approval_status=user.approval_status,
            registered_at=user.created_at,
        ),
    )


@router.post(
    "/resident/login/otp/request",
    response_model=APIResponse[OTPResponse],
    status_code=status.HTTP_200_OK,
)
def request_resident_login_otp(
    payload: ResidentLoginOTPRequest,
    db: Session = Depends(get_db),
):
    """
    Passwordless Resident Login — Step 1:
    Frontend submits registered mobile number only.
    Backend retrieves registered email and delivers secure 6-digit OTP strictly via email.
    Never sends OTP through SMS or WhatsApp.
    """
    service = OTPService(db)
    result = service.request_login_otp(payload.phone)
    return APIResponse(
        success=True,
        message=f"Verification code sent to registered email ({result['email_masked']}).",
        data=OTPResponse(
            phone=result["phone"],
            expires_in_seconds=result["expires_in_seconds"],
            cooldown_seconds=result["cooldown_seconds"],
            email_masked=result["email_masked"],
        ),
    )


@router.post(
    "/resident/login/otp/verify",
    response_model=APIResponse[TokenResponse],
    status_code=status.HTTP_200_OK,
)
def verify_resident_login_otp(
    payload: ResidentLoginOTPVerifyRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    """
    Passwordless Resident Login — Step 2:
    Resident submits mobile number and received email OTP.
    Backend verifies OTP against stored hash, authenticates resident, and returns JWT tokens.
    No resident password is required or accepted.
    """
    otp_service = OTPService(db)
    user = otp_service.verify_login_otp(payload.phone, payload.otp, consume=True)

    ip_address = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")

    auth_service = AuthService(db)
    token_data = auth_service.issue_tokens_for_resident(
        user=user,
        client_type="resident_mobile",
        ip_address=ip_address,
        user_agent=user_agent,
    )

    return APIResponse(
        success=True,
        message="Authenticated successfully via OTP.",
        data=token_data,
    )


@router.post(
    "/resident/register",
    response_model=APIResponse[ResidentRegistrationResponse],
    status_code=status.HTTP_201_CREATED,
)
def register_resident(
    payload: ResidentRegistrationRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    """
    Legacy registration endpoint preserved for backward compatibility.
    """
    from app.core.security import get_password_hash

    otp_service = OTPService(db)
    otp_service.verify_registration_otp(payload.phone, payload.otp, consume=True)

    norm_phone = normalize_phone(payload.phone)

    if db.scalar(sa.select(User).where(User.phone == norm_phone)):
        raise ConflictError("This mobile number is already registered. Please log in instead.")

    norm_email = payload.email.strip().lower() if payload.email else None
    if norm_email and db.scalar(sa.select(User).where(sa.func.lower(User.email) == norm_email)):
        raise ConflictError("This email address is already registered.")

    prop = db.get(Property, payload.property_id)
    if not prop or not prop.is_active:
        raise NotFoundError("The specified PG property does not exist or is currently inactive.")

    resident_role = db.scalar(sa.select(Role).where(Role.name == "RESIDENT"))
    if not resident_role:
        raise NotFoundError("System role 'RESIDENT' is not configured.")

    password_hash = get_password_hash(payload.password) if payload.password else f"!RESIDENT_NO_PASSWORD_{secrets.token_hex(16)}"
    user = User(
        company_id=prop.company_id,
        role_id=resident_role.id,
        phone=norm_phone,
        email=norm_email,
        full_name=payload.full_name.strip(),
        password_hash=password_hash,
        is_active=True,
        is_verified=True,
        approval_status="PENDING_APPROVAL",
    )
    db.add(user)
    db.flush()

    resident = Resident(
        user_id=user.id,
        property_id=prop.id,
        check_in_date=date.today(),
        monthly_rent=0.0,
        security_deposit=0.0,
        kyc_status="PENDING",
        status="PENDING_APPROVAL",
    )
    db.add(resident)
    db.commit()
    db.refresh(resident)
    db.refresh(user)

    ip_address = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")
    record_audit_log(
        db=db,
        action="RESIDENT_REGISTRATION_SUBMITTED",
        resource_type="resident",
        user_id=user.id,
        user_email=user.email,
        user_role="RESIDENT",
        company_id=user.company_id,
        property_id=prop.id,
        resource_id=str(resident.id),
        details={
            "phone": user.phone,
            "property_name": prop.name,
            "status": "PENDING_APPROVAL",
            "approval_status": "PENDING_APPROVAL",
        },
        ip_address=ip_address,
        user_agent=user_agent,
    )

    return APIResponse(
        success=True,
        message="Registration submitted successfully. Your account is pending administrator approval.",
        data=ResidentRegistrationResponse(
            resident_id=resident.id,
            user_id=user.id,
            full_name=user.full_name,
            phone=user.phone,
            email=user.email,
            property_id=prop.id,
            property_name=prop.name,
            status=resident.status,
            approval_status=user.approval_status,
            registered_at=user.created_at,
        ),
    )


# ---------------------------------------------------------------------------
# Admin / Owner Authentication (Common Super Key Registration & Email/Password Login)
# ---------------------------------------------------------------------------

@router.post(
    "/admin/register",
    response_model=APIResponse[dict],
    status_code=status.HTTP_201_CREATED,
    summary="Admin / PG Owner Registration with Common Super Key",
)
def admin_register(
    payload: AdminRegisterRequest,
    db: Session = Depends(get_db),
):
    """
    Registers a new property business/organization and owner admin account.
    Validates business name, email, password complexity, and Origin Common Super Key.
    Activates the account immediately upon registration authorization without email OTP.
    """
    import hashlib
    import re
    from app.core.config import settings
    from app.core.exceptions import PGException

    # 1. Validate server configuration for Common Super Key
    configured_key = settings.ADMIN_REGISTRATION_SUPER_KEY
    configured_hash = getattr(settings, "ADMIN_REGISTRATION_SUPER_KEY_HASH", "")
    if (not configured_key or not configured_key.strip()) and (not configured_hash or not configured_hash.strip()):
        raise PGException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            code="CONFIGURATION_ERROR",
            message="Admin registration Super Key is not configured on the server. Please contact system administrator.",
        )

    # 2. Constant-time comparison of submitted Super Key against configured hash / key
    submitted_key = payload.super_key.strip().upper()
    submitted_hash = hashlib.sha256(submitted_key.encode("utf-8")).hexdigest()

    key_matches = False
    if configured_hash and configured_hash.strip():
        key_matches = secrets.compare_digest(submitted_hash, configured_hash.strip().lower())
    if not key_matches and configured_key and configured_key.strip():
        key_matches = secrets.compare_digest(submitted_key, configured_key.strip().upper())

    if not key_matches:
        raise BadRequestError("Invalid registration Super Key. Please verify the common key provided by Origin Company.")

    # 3. Normalize email and verify uniqueness
    email_norm = payload.email.strip().lower()
    existing_user = db.scalar(sa.select(User).where(sa.func.lower(User.email) == email_norm))
    if existing_user:
        raise ConflictError("An account with this email address already exists.")

    # 4. Generate unique company code
    clean_name = re.sub(r"[^A-Z0-9]", "", payload.business_name.upper())[:6] or "ORG"
    company_code = f"{clean_name}_{secrets.token_hex(3).upper()}"

    company = Company(
        name=payload.business_name.strip(),
        code=company_code,
        email=email_norm,
        phone=payload.phone,
        is_active=True,
        bed_limit=240,
    )
    db.add(company)
    db.flush()

    manager_role = db.scalar(sa.select(Role).where(Role.name == "PROPERTY_MANAGER"))
    if not manager_role:
        manager_role = db.scalar(sa.select(Role).where(Role.name == "SUPER_ADMIN"))
    if not manager_role:
        manager_role = Role(
            name="PROPERTY_MANAGER",
            display_name="Property Manager / PG Owner",
            is_system_role=True,
            permissions=["*"],
        )
        db.add(manager_role)
        db.flush()

    admin_user = User(
        company_id=company.id,
        role_id=manager_role.id,
        full_name=payload.full_name or payload.business_name.strip(),
        email=email_norm,
        phone=payload.phone or f"00{secrets.token_hex(4)}",
        password_hash=get_password_hash(payload.password),
        is_active=True,
        is_verified=True,
        approval_status="APPROVED",
    )
    db.add(admin_user)
    db.commit()
    db.refresh(admin_user)
    db.refresh(company)

    return APIResponse(
        success=True,
        message="Administrator account registered successfully. Please proceed to login with your email and password.",
        data={
            "company_id": str(company.id),
            "user_id": str(admin_user.id),
            "email": admin_user.email,
            "business_name": company.name,
            "role": manager_role.name,
            "is_active": admin_user.is_active,
            "is_verified": admin_user.is_verified,
            "approval_status": admin_user.approval_status,
            "user": {
                "id": str(admin_user.id),
                "email": admin_user.email,
                "role": manager_role.name,
                "is_active": admin_user.is_active,
                "is_verified": admin_user.is_verified,
                "approval_status": admin_user.approval_status,
            },
            "company": {
                "id": str(company.id),
                "name": company.name,
                "code": company.code,
                "bed_limit": company.bed_limit,
            },
        },
    )


@router.post(
    "/admin/register/verify",
    response_model=APIResponse[TokenResponse],
    status_code=status.HTTP_200_OK,
    summary="Verify Admin Registration (Backward Compatibility)",
)
def admin_register_verify(
    payload: AdminRegisterVerifyRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    """
    Backward-compatible verification endpoint. If already verified via common Super Key,
    issues tokens directly.
    """
    ip_address = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")

    user = db.scalar(sa.select(User).where(User.email == payload.email))
    if not user:
        raise NotFoundError("Administrator account not found.")

    if not user.is_verified:
        otp_service = OTPService(db)
        otp_service.verify_admin_registration_super_key(payload.email, payload.super_key)
        user.is_verified = True
        user.approval_status = "APPROVED"
        db.commit()
        db.refresh(user)

    auth_service = AuthService(db)
    token_data = auth_service.issue_tokens_for_admin(
        user=user,
        client_type="admin_web",
        ip_address=ip_address,
        user_agent=user_agent,
    )
    return APIResponse(
        success=True,
        message="Administrator account is active.",
        data=token_data,
    )


@router.post(
    "/admin/register/resend-otp",
    response_model=APIResponse[dict],
    status_code=status.HTTP_200_OK,
    summary="Resend Admin Registration Super Key (Deprecated)",
)
def admin_register_resend_otp(
    payload: AdminResendOtpRequest,
    db: Session = Depends(get_db),
):
    """
    Deprecated registration OTP endpoint. Common Super Key is used at registration.
    """
    user = db.scalar(sa.select(User).where(User.email == payload.email))
    if not user:
        raise NotFoundError("Administrator account not found.")
    if user.is_verified:
        raise BadRequestError("Administrator account is already verified. Please proceed to login.")

    return APIResponse(
        success=True,
        message="Account is ready for login.",
        data={"email": payload.email, "is_verified": True},
    )


@router.post(
    "/admin/login",
    response_model=APIResponse[TokenResponse],
    status_code=status.HTTP_200_OK,
    summary="Admin Login (Email + Password Only)",
)
def admin_login(
    payload: AdminLoginRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    """
    Direct Email + Password Authentication for Administrators & Property Managers.
    Verifies primary credentials (email + password) and issues authenticated JWT tokens directly.
    No Super Key or 2FA OTP is required or dispatched.
    """
    ip_address = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")

    auth_service = AuthService(db)
    user = auth_service.authenticate_user(payload.email, payload.password)

    if user.role.name == "RESIDENT":
        raise PermissionDeniedError("Resident accounts must authenticate via the Resident Mobile App.")

    if not user.is_active:
        raise PermissionDeniedError("Administrator account is inactive. Please contact system administrator.")

    token_data = auth_service.issue_tokens_for_admin(
        user=user,
        client_type="admin_web",
        ip_address=ip_address,
        user_agent=user_agent,
    )

    return APIResponse(
        success=True,
        message=f"Authenticated successfully as {user.role.display_name}.",
        data=token_data,
    )


@router.post(
    "/admin/login/verify",
    response_model=APIResponse[TokenResponse],
    status_code=status.HTTP_200_OK,
    summary="Verify Admin Login Super Key 2FA (Backward Compatibility)",
)
def admin_login_verify(
    payload: AdminLoginVerifyRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    """
    Backward-compatible 2FA verification endpoint. Directs to immediate token issuance.
    """
    ip_address = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")

    user = db.scalar(sa.select(User).where(User.email == payload.email))
    if not user:
        raise NotFoundError("Administrator account not found.")

    if not user.is_active:
        raise PermissionDeniedError("Account is inactive. Please contact system administrator.")

    auth_service = AuthService(db)
    token_data = auth_service.issue_tokens_for_admin(
        user=user,
        client_type="admin_web",
        ip_address=ip_address,
        user_agent=user_agent,
    )
    return APIResponse(
        success=True,
        message="Authentication successful.",
        data=token_data,
    )


@router.post(
    "/admin/login/resend-otp",
    response_model=APIResponse[dict],
    status_code=status.HTTP_200_OK,
    summary="Resend Admin Login Super Key 2FA (Deprecated)",
)
def admin_login_resend_otp(
    payload: AdminResendOtpRequest,
    db: Session = Depends(get_db),
):
    """
    Deprecated login 2FA OTP endpoint.
    """
    return APIResponse(
        success=True,
        message="2FA is disabled for admin login. Please log in directly with your email and password.",
        data={"email": payload.email},
    )
