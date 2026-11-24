from typing import Optional
from pydantic import field_validator, BaseModel, Field
from app.schemas.user import UserProfile


class LoginRequest(BaseModel):
    identifier: str = Field(..., description="Registered email address or mobile phone number")
    password: str = Field(..., min_length=4)
    client_type: str = Field(
        default="admin_web",
        description="Target client application: 'admin_web', 'admin_mobile', or 'resident_mobile'",
    )
    device_info: Optional[str] = None


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int
    user: UserProfile


class RefreshRequest(BaseModel):
    refresh_token: str
    client_type: Optional[str] = "admin_web"


class PasswordChangeRequest(BaseModel):
    current_password: str
    new_password: str = Field(..., min_length=6)


class PasswordChangeOtpRequest(BaseModel):
    email: str = Field(..., description="Registered administrator email address")


class PasswordChangeOtpVerifyRequest(BaseModel):
    email: str = Field(..., description="Registered administrator email address")
    otp: str = Field(..., min_length=4, max_length=10, description="6-digit verification code")


class PasswordChangeWithOtpRequest(BaseModel):
    email: str = Field(..., description="Account email address")
    otp: str = Field(..., min_length=4, max_length=10, description="6-digit code from the email")
    new_password: str = Field(..., min_length=8, max_length=128, description="New password: 8+ characters with a letter and a number")

    @field_validator("new_password")
    @classmethod
    def letters_and_numbers(cls, v: str) -> str:
        if not (any(c.isalpha() for c in v) and any(c.isdigit() for c in v)):
            raise ValueError("Password needs at least one letter and one number.")
        return v

