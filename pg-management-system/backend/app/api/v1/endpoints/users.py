import uuid
from typing import Optional
from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.orm import Session

from app.dependencies import get_db, require_roles
from app.models.user import User
from app.repositories.user_repository import UserRepository
from app.schemas.common import APIResponse, PaginatedData
from app.schemas.user import UserProfile, UserSummary
from app.services.auth_service import AuthService

router = APIRouter()


@router.get("", response_model=APIResponse[PaginatedData[UserSummary]], status_code=status.HTTP_200_OK)
def get_users(
    role_name: Optional[str] = Query(None, description="Filter by role name"),
    is_active: Optional[bool] = Query(None, description="Filter by active status"),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    current_user: User = Depends(require_roles("SUPER_ADMIN", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Lists company users with filtering and pagination."""
    repo = UserRepository(db)
    users, total = repo.list_users(
        company_id=current_user.company_id,
        role_name=role_name,
        is_active=is_active,
        page=page,
        page_size=page_size,
    )
    items = [
        UserSummary(
            id=u.id,
            full_name=u.full_name,
            email=u.email,
            phone=u.phone,
            role_name=u.role.name,
            is_active=u.is_active,
        )
        for u in users
    ]
    total_pages = (total + page_size - 1) // page_size if total > 0 else 1

    return APIResponse(
        success=True,
        message=f"Retrieved {len(items)} users.",
        data=PaginatedData(
            items=items,
            total=total,
            page=page,
            page_size=page_size,
            total_pages=total_pages,
        ),
    )


@router.get("/{user_id}", response_model=APIResponse[UserProfile], status_code=status.HTTP_200_OK)
def get_user_detail(
    user_id: uuid.UUID,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Retrieves full profile of a user by UUID."""
    repo = UserRepository(db)
    user = repo.get_by_id(user_id)
    if not user:
        from app.core.exceptions import NotFoundError
        raise NotFoundError(f"User with ID '{user_id}' not found.")

    service = AuthService(db)
    profile = service.build_user_profile(user)
    return APIResponse(
        success=True,
        message="User profile retrieved.",
        data=profile,
    )
