import uuid
from datetime import datetime
from typing import Optional
from pydantic import BaseModel, ConfigDict


class ReceiptSummaryRead(BaseModel):
    id: uuid.UUID
    receipt_number: str
    amount: float
    issued_at: datetime
    invoice_id: uuid.UUID
    invoice_number: str
    billing_month: str
    payment_mode: str

    model_config = ConfigDict(from_attributes=True)


class ReceiptDetailRead(BaseModel):
    id: uuid.UUID
    receipt_number: str
    amount: float
    issued_at: datetime
    # Invoice details
    invoice_id: uuid.UUID
    invoice_number: str
    billing_month: str
    invoice_type: str
    property_name: str
    property_address: Optional[str] = None
    room_number: Optional[str] = None
    bed_number: Optional[str] = None
    # Resident details
    resident_id: uuid.UUID
    resident_name: str
    resident_phone: str
    resident_email: Optional[str] = None
    # Payment details
    payment_id: uuid.UUID
    payment_number: str
    payment_mode: str
    gateway_payment_id: Optional[str] = None
    paid_at: Optional[datetime] = None

    model_config = ConfigDict(from_attributes=True)
