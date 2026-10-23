import uuid
from datetime import datetime
from typing import Optional
from pydantic import BaseModel, ConfigDict


class PaymentBase(BaseModel):
    amount: float
    payment_mode: str = "UPI"


class PaymentCreate(PaymentBase):
    invoice_id: uuid.UUID
    property_id: uuid.UUID
    resident_id: uuid.UUID
    gateway_order_id: Optional[str] = None
    gateway_payment_id: Optional[str] = None


class PaymentRead(PaymentBase):
    id: uuid.UUID
    property_id: uuid.UUID
    invoice_id: uuid.UUID
    resident_id: uuid.UUID
    payment_number: str
    gateway_order_id: Optional[str] = None
    gateway_payment_id: Optional[str] = None
    status: str
    receipt_url: Optional[str] = None
    paid_at: Optional[datetime] = None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class PaymentSummary(BaseModel):
    id: uuid.UUID
    payment_number: str
    amount: float
    payment_mode: str
    status: str
    paid_at: Optional[datetime] = None

    model_config = ConfigDict(from_attributes=True)
