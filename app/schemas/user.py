import uuid
from datetime import datetime
from typing import List, Optional
from pydantic import BaseModel, ConfigDict, EmailStr, Field

from app.schemas.role import RoleRead
from app.schemas.property import PropertySummary


class UserBase(BaseModel):
    full_name: str
    email: Optional[EmailStr] = None
    phone: str
    is_active: bool = True
    is_verified: bool = False
    avatar_url: Optional[str] = None


class UserCreate(BaseModel):
    full_name: str
    email: Optional[EmailStr] = None
    phone: str = Field(..., description="Indian 10-digit mobile number or standard phone format")
    password: str = Field(..., min_length=6)
    role_id: uuid.UUID
    property_ids: Optional[List[uuid.UUID]] = []


class UserUpdate(BaseModel):
    full_name: Optional[str] = None
    email: Optional[EmailStr] = None
    phone: Optional[str] = None
    is_active: Optional[bool] = None
    avatar_url: Optional[str] = None


class UserPropertyAssign(BaseModel):
    property_ids: List[uuid.UUID]
    access_level: str = "MANAGER"


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
