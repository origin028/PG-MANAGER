import uuid
from typing import Optional
from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.orm import Session

from app.dependencies import get_current_user, get_db, verify_property_access
from app.models.user import User
from app.repositories.payment_repository import PaymentRepository
from app.schemas.common import APIResponse, PaginatedData
from app.schemas.payment import PaymentSummary

router = APIRouter()


@router.get("", response_model=APIResponse[PaginatedData[PaymentSummary]], status_code=status.HTTP_200_OK)
def list_payments(
    property_id: uuid.UUID = Query(..., description="Property ID filter"),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Lists payments recorded for a property."""
    verify_property_access(property_id, current_user, db)
    repo = PaymentRepository(db)
    payments, total = repo.list_by_property(property_id=property_id, page=page, page_size=page_size)
    summaries = [PaymentSummary.model_validate(p) for p in payments]
    total_pages = (total + page_size - 1) // page_size if total > 0 else 1

    return APIResponse(
        success=True,
        message=f"Retrieved {len(summaries)} payments.",
        data=PaginatedData(
            items=summaries,
            total=total,
            page=page,
            page_size=page_size,
            total_pages=total_pages,
        ),
    )
