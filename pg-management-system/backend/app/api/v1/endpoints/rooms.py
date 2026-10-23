import uuid
from typing import List
from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.orm import Session

from app.dependencies import get_current_user, get_db, verify_property_access
from app.models.user import User
from app.repositories.room_repository import RoomRepository
from app.schemas.common import APIResponse
from app.schemas.room import RoomSummary

router = APIRouter()


@router.get("", response_model=APIResponse[List[RoomSummary]], status_code=status.HTTP_200_OK)
def list_rooms(
    property_id: uuid.UUID = Query(..., description="Property ID to filter rooms"),
    floor_number: int = Query(None, description="Optional floor filter"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Lists rooms for a property by floor breakdown."""
    verify_property_access(property_id, current_user, db)
    repo = RoomRepository(db)
    rooms = repo.list_by_property(property_id, floor_number)
    summaries = [RoomSummary.model_validate(r) for r in rooms]
    return APIResponse(
        success=True,
        message=f"Retrieved {len(summaries)} rooms.",
        data=summaries,
    )
