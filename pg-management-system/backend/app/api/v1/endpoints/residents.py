import uuid
from typing import Optional
from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.orm import Session

from app.dependencies import get_current_user, get_db, verify_property_access
from app.models.user import User
from app.repositories.resident_repository import ResidentRepository
from app.schemas.common import APIResponse, PaginatedData
from app.schemas.resident import ResidentSummary

router = APIRouter()


@router.get("", response_model=APIResponse[PaginatedData[ResidentSummary]], status_code=status.HTTP_200_OK)
def list_residents(
    property_id: uuid.UUID = Query(..., description="Property ID filter"),
    status: Optional[str] = Query(None, description="Resident status filter (ACTIVE, NOTICE_PERIOD, CHECKED_OUT)"),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Lists residents in a property."""
    verify_property_access(property_id, current_user, db)
    repo = ResidentRepository(db)
    residents, total = repo.list_by_property(property_id=property_id, status=status, page=page, page_size=page_size)
    summaries = [ResidentSummary.model_validate(r) for r in residents]
    total_pages = (total + page_size - 1) // page_size if total > 0 else 1

    return APIResponse(
        success=True,
        message=f"Retrieved {len(summaries)} residents.",
        data=PaginatedData(
            items=summaries,
            total=total,
            page=page,
            page_size=page_size,
            total_pages=total_pages,
        ),
    )
