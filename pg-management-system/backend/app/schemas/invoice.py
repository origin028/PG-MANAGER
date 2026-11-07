import uuid
from datetime import date, datetime
from typing import Optional
from pydantic import BaseModel, ConfigDict, Field


class InvoiceBase(BaseModel):
    billing_month: str
    invoice_type: str = "RENT"
    amount: float = Field(..., gt=0, description="Invoice amount in INR (must be greater than 0)")
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
    property_id: Optional[uuid.UUID] = None
    property_name: Optional[str] = None
    resident_id: Optional[uuid.UUID] = None
    resident_name: Optional[str] = None
    resident_phone: Optional[str] = None
    room_number: Optional[str] = None
    notes: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)


class ResidentInvoiceItem(BaseModel):
    id: uuid.UUID
    invoice_number: str
    billing_month: str
    invoice_type: str
    amount: float
    paid_amount: float
    remaining_amount: float
    due_date: date
    status: str
    notes: Optional[str] = None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class ResidentInvoiceDetail(BaseModel):
    id: uuid.UUID
    property_id: uuid.UUID
    property_name: str
    resident_id: uuid.UUID
    resident_name: str
    invoice_number: str
    billing_month: str
    invoice_type: str
    amount: float
    paid_amount: float
    remaining_amount: float
    due_date: date
    status: str
    notes: Optional[str] = None
    created_at: datetime
    # Associated payment/receipt details
    receipt_id: Optional[uuid.UUID] = None
    receipt_number: Optional[str] = None
    gateway_order_id: Optional[str] = None
    paid_at: Optional[datetime] = None

    model_config = ConfigDict(from_attributes=True)


class InvoiceUpdate(BaseModel):
    due_date: Optional[date] = None
    notes: Optional[str] = None
    status: Optional[str] = None


