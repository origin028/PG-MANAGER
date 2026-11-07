import uuid
from datetime import date, datetime
from decimal import Decimal
from typing import Optional
from pydantic import BaseModel, ConfigDict, Field


class PaymentBase(BaseModel):
    amount: Decimal = Field(..., gt=0, description="Payment amount must be strictly greater than zero")
    payment_method: str = Field(
        ...,
        pattern="^(UPI|CASH|BANK_TRANSFER|CARD|OTHER)$",
        description="Supported modes: UPI, CASH, BANK_TRANSFER, CARD, OTHER",
    )
    transaction_reference: Optional[str] = Field(None, max_length=150)
    payment_date: Optional[date] = None
    notes: Optional[str] = Field(None, max_length=255)


class PaymentCreate(PaymentBase):
    invoice_id: uuid.UUID


class PaymentRead(PaymentBase):
    id: uuid.UUID
    company_id: uuid.UUID
    property_id: uuid.UUID
    invoice_id: uuid.UUID
    resident_id: uuid.UUID
    payment_number: str
    status: str
    recorded_by_user_id: Optional[uuid.UUID] = None
    payment_date: date
    paid_at: datetime
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class PaymentDetail(PaymentRead):
    property_name: Optional[str] = None
    resident_name: Optional[str] = None
    invoice_number: Optional[str] = None
    recorded_by_name: Optional[str] = None


class PaymentRefundRequest(BaseModel):
    reason: Optional[str] = Field(None, max_length=255)
