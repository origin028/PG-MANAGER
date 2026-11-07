import re
import uuid
from datetime import datetime
from typing import Any, Dict, List, Optional
from pydantic import BaseModel, ConfigDict, Field, model_validator


class PropertyBase(BaseModel):
    name: str = Field(..., min_length=2, max_length=150)
    code: str = Field(default="", max_length=50)
    property_type: str = "CO_LIVING"
    address_line1: str = ""
    address_line2: Optional[str] = None
    city: str = "Bangalore"
    state: str = "Karnataka"
    pincode: str = "560001"
    contact_phone: Optional[str] = None
    contact_email: Optional[str] = None
    total_floors: int = 4
    is_active: bool = True
    description: Optional[str] = None
    amenities: Optional[List[str]] = []
    rules: Optional[List[str]] = []
    settings: Dict[str, Any] = {}

    @model_validator(mode="before")
    @classmethod
    def preprocess_property_base(cls, values: Any) -> Any:
        if isinstance(values, dict):
            # Map 'address' to 'address_line1' if address_line1 is missing
            if not values.get("address_line1") and values.get("address"):
                values["address_line1"] = str(values["address"]).strip()
            if not values.get("address_line1"):
                values["address_line1"] = str(values.get("city", "Bangalore")).strip() or "Main Road"

            # Auto-generate unique code if missing or empty
            code_val = values.get("code")
            if not code_val or not str(code_val).strip():
                name_val = str(values.get("name", "PROP"))
                cleaned_name = re.sub(r"[^A-Za-z0-9]", "", name_val).upper()[:6] or "PROP"
                values["code"] = f"{cleaned_name}_{uuid.uuid4().hex[:6].upper()}"
            else:
                values["code"] = str(code_val).strip().upper()

            # Normalize property_type
            pt = values.get("property_type")
            if not pt or str(pt).strip().upper() in ["PG", "HOSTEL", "FLAT", "BOYS PG", "GIRLS PG"]:
                if str(pt).strip().upper() == "GIRLS PG":
                    values["property_type"] = "GIRLS"
                elif str(pt).strip().upper() == "BOYS PG":
                    values["property_type"] = "BOYS"
                else:
                    values["property_type"] = "CO_LIVING"

            # Ensure pincode has fallback
            if not values.get("pincode"):
                values["pincode"] = "560001"

        return values


class PropertyCreate(PropertyBase):
    pass


class PropertyUpdate(BaseModel):
    name: Optional[str] = None
    code: Optional[str] = None
    property_type: Optional[str] = None
    address_line1: Optional[str] = None
    address_line2: Optional[str] = None
    city: Optional[str] = None
    state: Optional[str] = None
    pincode: Optional[str] = None
    contact_phone: Optional[str] = None
    contact_email: Optional[str] = None
    total_floors: Optional[int] = None
    is_active: Optional[bool] = None
    description: Optional[str] = None
    amenities: Optional[List[str]] = None
    rules: Optional[List[str]] = None
    settings: Optional[Dict[str, Any]] = None

    @model_validator(mode="before")
    @classmethod
    def preprocess_property_update(cls, values: Any) -> Any:
        if isinstance(values, dict):
            if not values.get("address_line1") and values.get("address"):
                values["address_line1"] = str(values["address"]).strip()
        return values


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


class PropertyAccessAssignRequest(BaseModel):
    user_id: uuid.UUID
