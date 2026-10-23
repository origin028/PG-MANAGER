import uuid
from datetime import datetime
from typing import List, Optional
from pydantic import BaseModel, ConfigDict, EmailStr, Field


class RoleRead(BaseModel):
    id: uuid.UUID
    name: str
    display_name: str
    description: Optional[str] = None
    permissions: List[str] = []
    is_system_role: bool

    model_config = ConfigDict(from_attributes=True)


class PropertySummary(BaseModel):
    id: uuid.UUID
    name: str
    code: str
    property_type: str
    city: str
    is_active: bool

    model_config = ConfigDict(from_attributes=True)


class UserProfile(BaseModel):
    id: uuid.UUID
    company_id: uuid.UUID
    full_name: str
    email: Optional[str] = None
    phone: str
    role: RoleRead
    allowed_properties: List[PropertySummary] = []
    is_active: bool
    is_verified: bool
    avatar_url: Optional[str] = None
    last_login_at: Optional[datetime] = None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class UserSummary(BaseModel):
    id: uuid.UUID
    full_name: str
    email: Optional[str] = None
    phone: str
    role_name: str
    is_active: bool

    model_config = ConfigDict(from_attributes=True)


class UserCreate(BaseModel):
    full_name: str
    email: Optional[EmailStr] = None
    phone: str = Field(..., description="Indian 10-digit mobile number")
    password: str = Field(..., min_length=6)
    role_id: uuid.UUID
    property_ids: Optional[List[uuid.UUID]] = []


class UserUpdate(BaseModel):
    full_name: Optional[str] = None
    email: Optional[EmailStr] = None
    phone: Optional[str] = None
    is_active: Optional[bool] = None
    avatar_url: Optional[str] = None
