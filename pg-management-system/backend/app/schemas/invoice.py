import uuid
from datetime import date, datetime
from typing import Optional
from pydantic import BaseModel, ConfigDict


class InvoiceBase(BaseModel):
    billing_month: str
    invoice_type: str = "RENT"
    amount: float
    due_date: date
    notes: Optional[str] = None


class InvoiceCreate(InvoiceBase):
    property_id: uuid.UUID
    resident_id: uuid.UUID


class InvoiceRead(InvoiceBase):
    id: uuid.UUID
    property_id: uuid.UUID
    resident_id: uuid.UUID
    invoice_number: str
    paid_amount: float
    status: str
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class InvoiceSummary(BaseModel):
    id: uuid.UUID
    invoice_number: str
    billing_month: str
    invoice_type: str
    amount: float
    paid_amount: float
    due_date: date
    status: str

    model_config = ConfigDict(from_attributes=True)
