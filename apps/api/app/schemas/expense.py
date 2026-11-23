import uuid
from datetime import date as dt_date, datetime
from decimal import Decimal
from typing import List, Optional
from pydantic import BaseModel, ConfigDict, Field


class ExpenseBase(BaseModel):
    category: str = Field(..., description="GROCERIES, UTILITIES, MAINTENANCE, SALARY, RENT_TO_OWNER, INTERNET, OTHER")
    title: str = Field(..., max_length=200)
    amount: Decimal = Field(gt=0, max_digits=10, decimal_places=2)
    method: str = Field(default="UPI", description="Payment mode: CASH, UPI, BANK_TRANSFER, CHEQUE")
    date: dt_date = Field(default_factory=dt_date.today)
    notes: Optional[str] = None


class ExpenseCreate(ExpenseBase):
    property_id: uuid.UUID


class ExpenseUpdate(BaseModel):
    category: Optional[str] = None
    title: Optional[str] = None
    amount: Optional[Decimal] = Field(None, gt=0, max_digits=10, decimal_places=2)
    method: Optional[str] = None
    date: Optional[dt_date] = None
    notes: Optional[str] = None


class ExpenseRead(BaseModel):
    id: uuid.UUID
    property_id: Optional[uuid.UUID] = None
    company_id: uuid.UUID
    created_by_id: Optional[uuid.UUID] = None
    category: str
    title: str
    amount: float
    method: str
    date: dt_date
    notes: Optional[str] = None
    created_at: datetime
    property_name: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)


class ExpenseListResponse(BaseModel):
    expenses: List[ExpenseRead]
    total_amount: float
    count: int
