import uuid
from datetime import date
from decimal import Decimal
from typing import List, Optional

import sqlalchemy as sa
from fastapi import APIRouter, Depends, Query, Request, status
from pydantic import BaseModel, Field, field_validator
from sqlalchemy.orm import Session

from app.api.deps import get_db, require_roles
from app.core.exceptions import ValidationError
from app.models.expense import Expense
from app.models.user import User
from app.schemas.common import APIResponse
from app.services.audit_service import record_audit_log
from app.services.operations_service import get_permitted_property_ids

router = APIRouter()

EXPENSE_CATEGORIES = {
    "GROCERIES",
    "UTILITIES",
    "MAINTENANCE",
    "SALARY",
    "RENT_TO_OWNER",
    "OTHER",
}
PAYMENT_METHODS = {"CASH", "UPI", "BANK_TRANSFER", "CARD", "OTHER"}


def _normalize(value: str) -> str:
    return "_".join(value.strip().upper().replace("-", " ").split())


class ExpenseCreate(BaseModel):
    property_id: Optional[uuid.UUID] = None
    title: str = Field(..., min_length=3, max_length=150)
    category: str
    amount: Decimal = Field(..., gt=0, description="Expense amount in INR")
    date: date
    method: str
    notes: Optional[str] = Field(None, max_length=1000)

    @field_validator("category")
    @classmethod
    def _validate_category(cls, value: str) -> str:
        normalized = _normalize(value)
        if normalized not in EXPENSE_CATEGORIES:
            raise ValueError(
                "category must be one of GROCERIES, UTILITIES, MAINTENANCE, SALARY, RENT_TO_OWNER, OTHER"
            )
        return normalized

    @field_validator("method")
    @classmethod
    def _validate_method(cls, value: str) -> str:
        normalized = _normalize(value)
        if normalized not in PAYMENT_METHODS:
            raise ValueError("method must be one of CASH, UPI, BANK_TRANSFER, CARD, OTHER")
        return normalized


def _serialize(expense: Expense) -> dict:
    return {
        "id": str(expense.id),
        "company_id": str(expense.company_id),
        "property_id": str(expense.property_id) if expense.property_id else None,
        "title": expense.title,
        "category": expense.category,
        "amount": float(expense.amount),
        "date": expense.date.isoformat(),
        "method": expense.method,
        "notes": expense.notes,
        "created_by_id": str(expense.created_by_id) if expense.created_by_id else None,
        "created_at": expense.created_at.isoformat() if expense.created_at else None,
    }


@router.get("", response_model=APIResponse[List[dict]], status_code=status.HTTP_200_OK)
def get_expenses(
    property_id: Optional[uuid.UUID] = Query(None, description="Filter by property ID"),
    current_user: User = Depends(require_roles("SUPER_ADMIN", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Lists expenses scoped to the caller's company and assigned properties."""
    permitted = get_permitted_property_ids(db, current_user, property_id)
    stmt = sa.select(Expense).where(Expense.company_id == current_user.company_id)
    if property_id:
        stmt = stmt.where(Expense.property_id == property_id)
    elif permitted:
        stmt = stmt.where(
            sa.or_(Expense.property_id.in_(permitted), Expense.property_id.is_(None))
        )
    expenses = db.scalars(stmt.order_by(Expense.date.desc(), Expense.created_at.desc())).all()
    result = [_serialize(e) for e in expenses]
    return APIResponse(success=True, message=f"Retrieved {len(result)} expenses.", data=result)


@router.post("", response_model=APIResponse[dict], status_code=status.HTTP_201_CREATED)
def create_expense(
    payload: ExpenseCreate,
    request: Request,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Records a property expense. Managers must target one of their properties."""
    if payload.property_id:
        get_permitted_property_ids(db, current_user, payload.property_id)
    elif current_user.role.name != "SUPER_ADMIN":
        raise ValidationError("property_id is required for property managers.")

    expense = Expense(
        company_id=current_user.company_id,
        property_id=payload.property_id,
        title=payload.title.strip(),
        category=payload.category,
        amount=payload.amount,
        date=payload.date,
        method=payload.method,
        notes=payload.notes.strip() if payload.notes else None,
        created_by_id=current_user.id,
    )
    db.add(expense)
    db.commit()
    db.refresh(expense)

    record_audit_log(
        db=db,
        action="EXPENSE_CREATED",
        resource_type="expense",
        resource_id=str(expense.id),
        user_id=current_user.id,
        user_email=current_user.email,
        user_role=current_user.role.name,
        company_id=expense.company_id,
        property_id=expense.property_id,
        details={
            "title": expense.title,
            "category": expense.category,
            "amount": str(expense.amount),
        },
        ip_address=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent"),
    )
    return APIResponse(success=True, message="Expense created successfully.", data=_serialize(expense))
