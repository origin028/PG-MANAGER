import re
from typing import Optional
from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator


class AdminRegisterRequest(BaseModel):
    business_name: str = Field(..., min_length=2, max_length=150, description="Business or PG Organization Name")
    email: EmailStr = Field(..., description="Administrator work email address")
    password: str = Field(..., min_length=8, max_length=128, description="Strong password (min 8 characters)")
    confirm_password: Optional[str] = Field(None, min_length=8, max_length=128, description="Confirmation password")
    super_key: str = Field(..., min_length=1, max_length=128, description="Common Registration Super Key provided by Origin")
    phone: Optional[str] = Field(None, max_length=30, description="Contact phone number")
    full_name: Optional[str] = Field(None, max_length=150, description="Administrator full name")

    @field_validator("confirm_password")
    @classmethod
    def passwords_match(cls, v: Optional[str], info) -> Optional[str]:
        if v is not None and "password" in info.data and v != info.data["password"]:
            raise ValueError("Passwords do not match.")
        return v

    @field_validator("super_key")
    @classmethod
    def validate_super_key(cls, v: str) -> str:
        clean = v.strip().upper()
        if not clean:
            raise ValueError("Common Super Key is required.")
        return clean

    @field_validator("password")
    @classmethod
    def password_complexity(cls, v: str) -> str:
        if not re.search(r"[A-Za-z]", v) or not re.search(r"\d", v):
            raise ValueError("Password must contain at least one letter and one number.")
        return v

    @field_validator("email")
    @classmethod
    def normalize_email(cls, v: str) -> str:
        return v.strip().lower()


class AdminRegisterVerifyRequest(BaseModel):
    email: EmailStr = Field(..., description="Administrator email address")
    super_key: str = Field(..., min_length=6, max_length=6, description="6-digit Super Key verification code")

    @field_validator("super_key")
    @classmethod
    def validate_code(cls, v: str) -> str:
        clean = v.strip()
        if not clean.isdigit() or len(clean) != 6:
            raise ValueError("Super Key must be a 6-digit numeric code.")
        return clean

    @field_validator("email")
    @classmethod
    def normalize_email(cls, v: str) -> str:
        return v.strip().lower()


class AdminResendOtpRequest(BaseModel):
    email: EmailStr = Field(..., description="Registered administrator email address")

    @field_validator("email")
    @classmethod
    def normalize_email(cls, v: str) -> str:
        return v.strip().lower()


class AdminLoginRequest(BaseModel):
    email: EmailStr = Field(..., description="Registered administrator email address")
    password: str = Field(..., min_length=1, description="Account password")

    @field_validator("email")
    @classmethod
    def normalize_email(cls, v: str) -> str:
        return v.strip().lower()


class AdminLogin2FARequiredResponse(BaseModel):
    email: str
    requires_2fa: bool = True
    expires_in_seconds: int = 600
    message: str = "Super Key 2FA sent to your registered email address."

    model_config = ConfigDict(from_attributes=True)


class AdminLoginVerifyRequest(BaseModel):
    email: EmailStr = Field(..., description="Registered administrator email address")
    super_key: str = Field(..., min_length=6, max_length=6, description="6-digit Super Key verification code")

    @field_validator("super_key")
    @classmethod
    def validate_code(cls, v: str) -> str:
        clean = v.strip()
        if not clean.isdigit() or len(clean) != 6:
            raise ValueError("Super Key must be a 6-digit numeric code.")
        return clean

    @field_validator("email")
    @classmethod
    def normalize_email(cls, v: str) -> str:
        return v.strip().lower()
