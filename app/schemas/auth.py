from typing import Optional
from pydantic import BaseModel, Field

from app.schemas.user import UserProfile


class LoginRequest(BaseModel):
    identifier: str = Field(..., description="Email address or phone number")
    password: str = Field(..., min_length=4)
    client_type: str = Field(
        default="admin_web",
        description="Client experience: 'admin_web', 'admin_mobile', or 'resident_mobile'",
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
