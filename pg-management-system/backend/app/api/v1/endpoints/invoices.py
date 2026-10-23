import uuid
from typing import List
from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.orm import Session

from app.dependencies import get_current_user, get_db, verify_property_access
from app.models.invoice import Invoice
from app.models.user import User
from app.schemas.common import APIResponse
from app.schemas.invoice import InvoiceSummary

router = APIRouter()


@router.get("", response_model=APIResponse[List[InvoiceSummary]], status_code=status.HTTP_200_OK)
def list_invoices(
    property_id: uuid.UUID = Query(..., description="Property ID filter"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Lists monthly invoices for a property."""
    verify_property_access(property_id, current_user, db)
    invoices = db.query(Invoice).filter(Invoice.property_id == property_id).order_by(Invoice.due_date.desc()).all()
    summaries = [InvoiceSummary.model_validate(inv) for inv in invoices]
    return APIResponse(
        success=True,
        message=f"Retrieved {len(summaries)} invoices.",
        data=summaries,
    )
