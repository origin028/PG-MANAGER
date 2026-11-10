import uuid
from typing import Optional
from fastapi import APIRouter, Depends, Query, Request, status
from sqlalchemy.orm import Session

from app.dependencies import get_current_user, get_db, require_roles
from app.models.user import User
from app.repositories.user_repository import UserRepository
from app.schemas.common import APIResponse, PaginatedData
from app.schemas.user import (
    UserCreate,
    UserEmailUpdateRequest,
    UserEmailUpdateResponse,
    UserProfile,
    UserSummary,
    UserUpdate,
)
from app.services.auth_service import AuthService
from app.services.user_service import UserService

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


@router.patch("/me", response_model=APIResponse[UserProfile], status_code=status.HTTP_200_OK)
def update_current_user_profile(
    payload: UserUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Updates current authenticated user's profile details."""
    update_data = payload.model_dump(exclude_unset=True)
    if "full_name" in update_data and update_data["full_name"]:
        clean_name = update_data["full_name"].strip()
        current_user.full_name = clean_name
        from app.models.resident import Resident
        import sqlalchemy as sa
        resident = db.scalar(sa.select(Resident).where(Resident.user_id == current_user.id))
        if resident:
            resident.full_name = clean_name
    if "avatar_url" in update_data:
        current_user.avatar_url = update_data["avatar_url"]
    if "phone" in update_data and update_data["phone"]:
        clean_phone = update_data["phone"].strip()
        current_user.phone = clean_phone
        from app.models.resident import Resident
        import sqlalchemy as sa
        resident = db.scalar(sa.select(Resident).where(Resident.user_id == current_user.id))
        if resident:
            resident.phone = clean_phone

    db.commit()
    db.refresh(current_user)

    service = AuthService(db)
    profile = service.build_user_profile(current_user)
    return APIResponse(
        success=True,
        message="Profile updated successfully.",
        data=profile,
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


@router.patch(
    "/{user_id}/email",
    response_model=APIResponse[UserEmailUpdateResponse],
    status_code=status.HTTP_200_OK,
    summary="Update user or resident email address",
)
def update_user_email(
    user_id: uuid.UUID,
    payload: UserEmailUpdateRequest,
    request: Request,
    current_user: User = Depends(require_roles("SUPER_ADMIN")),
    db: Session = Depends(get_db),
):
    """
    Updates the email address of an existing user or resident.
    Strictly restricted to authenticated SUPER_ADMIN users.
    Ensures email uniqueness, normalizes email, updates User.email (used for resident OTP delivery),
    and records an immutable audit log entry in a single atomic database transaction.
    """
    ip_address = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")

    service = UserService(db)
    result = service.update_user_email(
        user_id=user_id,
        new_email=payload.target_email,
        current_admin=current_user,
        reason=payload.reason,
        ip_address=ip_address,
        user_agent=user_agent,
    )

    return APIResponse(
        success=True,
        message=f"User email updated successfully from '{result['old_email'] or 'None'}' to '{result['new_email']}'.",
        data=UserEmailUpdateResponse(**result),
    )
