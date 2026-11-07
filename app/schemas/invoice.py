import uuid
from datetime import date, datetime
from decimal import Decimal
from typing import Any, Dict, List, Optional
from pydantic import BaseModel, ConfigDict, Field

from app.schemas.payment import PaymentRead


class InvoiceBase(BaseModel):
    billing_month: str = Field(
        ..., pattern=r"^\d{4}-(0[1-9]|1[0-2])$", description="Billing month format YYYY-MM"
    )
    billing_period_start: date
    billing_period_end: date
    issue_date: date
    due_date: date
    invoice_type: str = Field(
        "RENT",
        pattern="^(RENT|SECURITY_DEPOSIT|MAINTENANCE|PENALTY)$",
        description="Type of invoice: RENT, SECURITY_DEPOSIT, MAINTENANCE, PENALTY",
    )
    rent_amount: Decimal = Field(..., ge=0, description="Base rent or charge amount")
    additional_charges: Decimal = Field(Decimal("0.00"), ge=0, description="Utility/addon charges")
    discount_amount: Decimal = Field(Decimal("0.00"), ge=0, description="Discount or waiver")
    notes: Optional[str] = Field(None, max_length=255)


class InvoiceCreate(InvoiceBase):
    property_id: uuid.UUID
    resident_id: uuid.UUID
    is_draft: bool = False


class InvoiceUpdate(BaseModel):
    due_date: Optional[date] = None
    additional_charges: Optional[Decimal] = Field(None, ge=0)
    discount_amount: Optional[Decimal] = Field(None, ge=0)
    notes: Optional[str] = Field(None, max_length=255)


class InvoiceRead(InvoiceBase):
    id: uuid.UUID
    company_id: uuid.UUID
    property_id: uuid.UUID
    resident_id: uuid.UUID
    invoice_number: str
    total_amount: Decimal
    paid_amount: Decimal
    balance_amount: Decimal
    status: str
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)


class InvoiceDetail(InvoiceRead):
    property_name: Optional[str] = None
    resident_name: Optional[str] = None
    room_number: Optional[str] = None
    bed_number: Optional[str] = None
    payments: List[PaymentRead] = []


class PropertyFinancialSummary(BaseModel):
    property_id: uuid.UUID
    property_name: str
    property_code: str
    total_invoiced: Decimal
    total_collected: Decimal
    total_outstanding: Decimal
    total_overdue: Decimal
    invoices_count: int


class InvoiceSummary(BaseModel):
    total_invoiced: Decimal
    total_collected: Decimal
    total_outstanding: Decimal
    total_overdue: Decimal
    invoices_count: int
    paid_invoices_count: int
    partially_paid_invoices_count: int
    overdue_invoices_count: int
    property_summaries: List[PropertyFinancialSummary] = []
