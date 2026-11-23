"""Unauthenticated endpoints used by the public website. Every route here is rate-limited."""
import re
import uuid
from typing import Optional

from fastapi import APIRouter, Depends, status
from pydantic import BaseModel, Field, field_validator
from sqlalchemy.orm import Session

from app.core.exceptions import NotFoundError
from app.core.rate_limit import rate_limit
from app.db.session import get_db
from app.models.lead import Lead
from app.models.property import Property
from app.schemas.common import APIResponse

router = APIRouter()


class EnquiryIn(BaseModel):
    name: str = Field(min_length=2, max_length=150)
    phone: str = Field(min_length=10, max_length=15)
    property_id: uuid.UUID
    message: Optional[str] = Field(default=None, max_length=500)
    website: Optional[str] = Field(default=None, max_length=200)  # honeypot: humans leave it empty

    @field_validator("phone")
    @classmethod
    def indian_mobile(cls, v: str) -> str:
        digits = re.sub(r"\D", "", v)[-10:]
        if not re.fullmatch(r"[6-9]\d{9}", digits):
            raise ValueError("Enter a valid 10-digit mobile number.")
        return digits

    @field_validator("name", "message")
    @classmethod
    def strip(cls, v: Optional[str]) -> Optional[str]:
        return v.strip() if v else v


@router.post(
    "/enquiries",
    status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(rate_limit("public-enquiry", 5, 3600))],
)
def create_enquiry(payload: EnquiryIn, db: Session = Depends(get_db)):
    """'Book a visit' form on the website. Lands in the owner's Leads list."""
    if payload.website:  # bot filled the hidden field: pretend success, store nothing
        return APIResponse(success=True, message="Thanks. We will call you shortly.", data=None)
    prop = db.get(Property, payload.property_id)
    if not prop or not prop.is_active:
        raise NotFoundError("Home not found.")
    db.add(
        Lead(
            property_id=prop.id,
            name=payload.name,
            phone=payload.phone,
            status="NEW",
            source="WEBSITE",
            requirement=payload.message,
        )
    )
    db.commit()
    return APIResponse(success=True, message="Thanks. We will call you shortly.", data=None)
