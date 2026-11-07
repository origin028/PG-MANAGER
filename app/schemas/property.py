import uuid
from datetime import datetime
from typing import Any, Dict, Optional
from pydantic import BaseModel, ConfigDict


class PropertyBase(BaseModel):
    name: str
    code: str
    property_type: str = "CO_LIVING"
    address_line1: str
    address_line2: Optional[str] = None
    city: str = "Bangalore"
    state: str = "Karnataka"
    pincode: str
    contact_phone: Optional[str] = None
    contact_email: Optional[str] = None
    total_floors: int = 4
    is_active: bool = True
    settings: Dict[str, Any] = {}


class PropertyCreate(PropertyBase):
    pass


class PropertySummary(BaseModel):
    id: uuid.UUID
    name: str
    code: str
    property_type: str
    city: str
    is_active: bool

    model_config = ConfigDict(from_attributes=True)


class PropertyRead(PropertyBase):
    id: uuid.UUID
    company_id: uuid.UUID
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)
