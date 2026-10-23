import uuid
from typing import List
from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.orm import Session

from app.dependencies import get_current_user, get_db
from app.models.user import User
from app.repositories.room_repository import RoomRepository
from app.schemas.bed import BedSummary
from app.schemas.common import APIResponse

router = APIRouter()


@router.get("", response_model=APIResponse[List[BedSummary]], status_code=status.HTTP_200_OK)
def list_beds_for_room(
    room_id: uuid.UUID = Query(..., description="Room ID to list beds for"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Lists beds for a specific room with live occupancy status."""
    repo = RoomRepository(db)
    beds = repo.list_beds_by_room(room_id)
    summaries = [BedSummary.model_validate(b) for b in beds]
    return APIResponse(
        success=True,
        message=f"Retrieved {len(summaries)} beds.",
        data=summaries,
    )
