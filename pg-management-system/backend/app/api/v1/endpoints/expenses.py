import uuid
from datetime import date
from decimal import Decimal
from typing import List, Optional
from fastapi import APIRouter, Depends, Query, status
import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.core.exceptions import BadRequestError, NotFoundError
from app.dependencies import get_current_user, get_db, require_roles, verify_property_access
from app.models.expense import Expense
from app.models.property import Property
from app.models.user import User
from app.schemas.common import APIResponse
from app.schemas.expense import ExpenseCreate, ExpenseListResponse, ExpenseRead, ExpenseUpdate
from app.services.audit_service import record_audit_log

router = APIRouter()


@router.post("", response_model=APIResponse[ExpenseRead], status_code=status.HTTP_201_CREATED)
def create_expense(
    payload: ExpenseCreate,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "ADMIN", "OWNER", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Creates a new property operational expense."""
    verify_property_access(payload.property_id, current_user, db)

    property_record = db.get(Property, payload.property_id)
    if not property_record:
        raise NotFoundError("Property not found.")

    if payload.amount <= Decimal("0.00"):
        raise BadRequestError("Expense amount must be greater than zero.")

    expense = Expense(
        company_id=property_record.company_id,
        property_id=payload.property_id,
        created_by_id=current_user.id,
        category=payload.category.upper(),
        title=payload.title.strip(),
        amount=payload.amount,
        method=payload.method.upper(),
        date=payload.date,
        notes=payload.notes,
    )
    db.add(expense)
    db.commit()
    db.refresh(expense)

    record_audit_log(
        db=db,
        action="CREATE_EXPENSE",
        resource_type="expenses",
        user_id=current_user.id,
        user_email=current_user.email,
        user_role=current_user.role.name if current_user.role else None,
        property_id=expense.property_id,
        resource_id=str(expense.id),
        details={"title": expense.title, "amount": float(expense.amount), "category": expense.category},
    )

    read_data = ExpenseRead(
        id=expense.id,
        property_id=expense.property_id,
        company_id=expense.company_id,
        created_by_id=expense.created_by_id,
        category=expense.category,
        title=expense.title,
        amount=float(expense.amount),
        method=expense.method,
        date=expense.date,
        notes=expense.notes,
        created_at=expense.created_at,
        property_name=property_record.name,
    )

    return APIResponse(
        success=True,
        message=f"Expense '{expense.title}' recorded successfully.",
        data=read_data,
    )


@router.get("", response_model=APIResponse[ExpenseListResponse], status_code=status.HTTP_200_OK)
def list_expenses(
    property_id: Optional[uuid.UUID] = Query(None, description="Optional property filter"),
    category: Optional[str] = Query(None, description="Filter by category (GROCERIES, UTILITIES, etc.)"),
    date_from: Optional[date] = Query(None, description="Filter start date"),
    date_to: Optional[date] = Query(None, description="Filter end date"),
    current_user: User = Depends(require_roles("SUPER_ADMIN", "ADMIN", "OWNER", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Lists property operational expenses with optional category and date filtering."""
    query = sa.select(Expense)

    if property_id:
        verify_property_access(property_id, current_user, db)
        query = query.where(Expense.property_id == property_id)
    elif current_user.role.name not in ("SUPER_ADMIN", "OWNER"):
        allowed = getattr(current_user, "allowed_properties", []) or []
        allowed_uuids = [uuid.UUID(str(p)) for p in allowed if p]
        query = query.where(Expense.property_id.in_(allowed_uuids))

    if category:
        query = query.where(Expense.category == category.upper())

    if date_from:
        query = query.where(Expense.date >= date_from)

    if date_to:
        query = query.where(Expense.date <= date_to)

    query = query.order_by(Expense.date.desc())
    expenses = db.scalars(query).all()

    items = []
    total_amount = Decimal("0.00")
    for e in expenses:
        total_amount += Decimal(str(e.amount))
        items.append(
            ExpenseRead(
                id=e.id,
                property_id=e.property_id,
                company_id=e.company_id,
                created_by_id=e.created_by_id,
                category=e.category,
                title=e.title,
                amount=float(e.amount),
                method=e.method,
                date=e.date,
                notes=e.notes,
                created_at=e.created_at,
                property_name=e.property.name if e.property else None,
            )
        )

    return APIResponse(
        success=True,
        message=f"Retrieved {len(items)} expense records.",
        data=ExpenseListResponse(
            expenses=items,
            total_amount=float(total_amount),
            count=len(items),
        ),
    )


@router.get("/{expense_id}", response_model=APIResponse[ExpenseRead], status_code=status.HTTP_200_OK)
def get_expense(
    expense_id: uuid.UUID,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "ADMIN", "OWNER", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Retrieves single expense record."""
    expense = db.get(Expense, expense_id)
    if not expense:
        raise NotFoundError("Expense record not found.")

    if expense.property_id:
        verify_property_access(expense.property_id, current_user, db)

    read_data = ExpenseRead(
        id=expense.id,
        property_id=expense.property_id,
        company_id=expense.company_id,
        created_by_id=expense.created_by_id,
        category=expense.category,
        title=expense.title,
        amount=float(expense.amount),
        method=expense.method,
        date=expense.date,
        notes=expense.notes,
        created_at=expense.created_at,
        property_name=expense.property.name if expense.property else None,
    )
    return APIResponse(
        success=True,
        message="Expense details retrieved successfully.",
        data=read_data,
    )


@router.patch("/{expense_id}", response_model=APIResponse[ExpenseRead], status_code=status.HTTP_200_OK)
def update_expense(
    expense_id: uuid.UUID,
    payload: ExpenseUpdate,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "ADMIN", "OWNER", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Updates an existing operational expense record."""
    expense = db.get(Expense, expense_id)
    if not expense:
        raise NotFoundError("Expense record not found.")

    if expense.property_id:
        verify_property_access(expense.property_id, current_user, db)

    update_data = payload.model_dump(exclude_unset=True)
    if not update_data:
        read_data = ExpenseRead(
            id=expense.id,
            property_id=expense.property_id,
            company_id=expense.company_id,
            created_by_id=expense.created_by_id,
            category=expense.category,
            title=expense.title,
            amount=float(expense.amount),
            method=expense.method,
            date=expense.date,
            notes=expense.notes,
            created_at=expense.created_at,
            property_name=expense.property.name if expense.property else None,
        )
        return APIResponse(success=True, message="No changes requested.", data=read_data)

    if "category" in update_data and update_data["category"]:
        expense.category = update_data["category"].upper()
    if "title" in update_data and update_data["title"]:
        expense.title = update_data["title"].strip()
    if "amount" in update_data and update_data["amount"] is not None:
        if update_data["amount"] <= Decimal("0.00"):
            raise BadRequestError("Expense amount must be greater than zero.")
        expense.amount = update_data["amount"]
    if "method" in update_data and update_data["method"]:
        expense.method = update_data["method"].upper()
    if "date" in update_data and update_data["date"]:
        expense.date = update_data["date"]
    if "notes" in update_data:
        expense.notes = update_data["notes"]

    record_audit_log(
        db=db,
        action="UPDATE_EXPENSE",
        resource_type="expenses",
        user_id=current_user.id,
        user_email=current_user.email,
        user_role=current_user.role.name if current_user.role else None,
        property_id=expense.property_id,
        resource_id=str(expense.id),
        details={"updated_fields": list(update_data.keys())},
    )

    db.commit()
    db.refresh(expense)

    read_data = ExpenseRead(
        id=expense.id,
        property_id=expense.property_id,
        company_id=expense.company_id,
        created_by_id=expense.created_by_id,
        category=expense.category,
        title=expense.title,
        amount=float(expense.amount),
        method=expense.method,
        date=expense.date,
        notes=expense.notes,
        created_at=expense.created_at,
        property_name=expense.property.name if expense.property else None,
    )
    return APIResponse(
        success=True,
        message="Expense updated successfully.",
        data=read_data,
    )


@router.delete("/{expense_id}", status_code=status.HTTP_200_OK)
def delete_expense(
    expense_id: uuid.UUID,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "ADMIN", "OWNER")),
    db: Session = Depends(get_db),
):
    """Deletes an operational expense record."""
    expense = db.get(Expense, expense_id)
    if not expense:
        raise NotFoundError("Expense record not found.")

    if expense.property_id:
        verify_property_access(expense.property_id, current_user, db)

    record_audit_log(
        db=db,
        action="DELETE_EXPENSE",
        resource_type="expenses",
        user_id=current_user.id,
        user_email=current_user.email,
        user_role=current_user.role.name if current_user.role else None,
        property_id=expense.property_id,
        resource_id=str(expense.id),
        details={"title": expense.title, "amount": float(expense.amount)},
    )

    db.delete(expense)
    db.commit()

    return APIResponse(
        success=True,
        message=f"Expense '{expense.title}' deleted successfully.",
        data={"deleted_id": str(expense_id)},
    )
