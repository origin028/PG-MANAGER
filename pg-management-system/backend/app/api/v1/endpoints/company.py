from fastapi import APIRouter, Depends, status
from sqlalchemy.orm import Session

from app.core.exceptions import BadRequestError
from app.dependencies import get_current_user, get_db
from app.models.user import User
from app.schemas.common import APIResponse
from app.schemas.company import CompanyBedCapacity
from app.services.bed_capacity_service import BedCapacityService

router = APIRouter()


@router.get(
    "/bed-capacity",
    response_model=APIResponse[CompanyBedCapacity],
    status_code=status.HTTP_200_OK,
    summary="Get Organization Bed Capacity",
)
def get_bed_capacity(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Returns the organization's fixed 240-bed capacity, total used beds,
    remaining beds, and usage percentage across all company properties.
    Strictly isolated to the authenticated user's organization.
    """
    if not current_user.company_id:
        raise BadRequestError("Authenticated user is not associated with an organization.")

    capacity_data = BedCapacityService.get_company_bed_usage(current_user.company_id, db)
    return APIResponse(
        success=True,
        message="Bed capacity retrieved successfully.",
        data=CompanyBedCapacity(**capacity_data),
    )
