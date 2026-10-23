import uuid
from typing import List, Any
from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.orm import Session

from app.dependencies import get_db, require_roles, verify_property_access
from app.models.expense import Expense
from app.models.user import User
from app.schemas.common import APIResponse

router = APIRouter()


@router.get("", response_model=APIResponse[List[dict]], status_code=status.HTTP_200_OK)
def list_expenses(
    property_id: uuid.UUID = Query(..., description="Property ID filter"),
    current_user: User = Depends(require_roles("SUPER_ADMIN", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Lists property operational expenses."""
    verify_property_access(property_id, current_user, db)
    expenses = db.query(Expense).filter(Expense.property_id == property_id).order_by(Expense.expense_date.desc()).all()
    data = [
        {
            "id": str(e.id),
            "property_id": str(e.property_id),
            "category": e.category,
            "title": e.title,
            "amount": float(e.amount),
            "payment_mode": e.payment_mode,
            "expense_date": e.expense_date.isoformat(),
        }
        for e in expenses
    ]
    return APIResponse(
        success=True,
        message=f"Retrieved {len(data)} expense records.",
        data=data,
    )
