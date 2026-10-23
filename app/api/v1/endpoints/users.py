import uuid
from typing import Optional
from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.orm import Session

from app.api.deps import get_current_user, get_db, require_roles
from app.models.user import User
from app.schemas.common import APIResponse, PaginatedData
from app.schemas.user import UserCreate, UserProfile, UserPropertyAssign, UserSummary
from app.services.auth_service import build_user_profile
from app.services.user_service import (
    assign_user_properties,
    create_user,
    get_user_by_id,
    list_users,
)

router = APIRouter()


@router.get("", response_model=APIResponse[PaginatedData[UserSummary]], status_code=status.HTTP_200_OK)
def get_users(
    role_name: Optional[str] = Query(None, description="Filter by role name (SUPER_ADMIN, PROPERTY_MANAGER, STAFF, RESIDENT)"),
    is_active: Optional[bool] = Query(None, description="Filter by active status"),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    current_user: User = Depends(require_roles("SUPER_ADMIN", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """
    List users within the company. Accessible to Super Admin and Property Managers.
    """
    users, total = list_users(
        db=db,
        company_id=current_user.company_id,
        role_name=role_name,
        is_active=is_active,
        page=page,
        page_size=page_size,
    )

    summaries = [
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
        message=f"Retrieved {len(summaries)} users.",
        data=PaginatedData(
            items=summaries,
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
    """
    Get full profile and property assignments for a user.
    """
    user = get_user_by_id(db, user_id)
    profile = build_user_profile(db, user)
    return APIResponse(
        success=True,
        message="User profile retrieved.",
        data=profile,
    )


@router.post("", response_model=APIResponse[UserProfile], status_code=status.HTTP_201_CREATED)
def create_new_user(
    payload: UserCreate,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """
    Create a new user (manager, staff, or resident).
    """
    user = create_user(
        db=db,
        company_id=current_user.company_id,
        data=payload,
        created_by_user=current_user,
    )
    profile = build_user_profile(db, user)
    return APIResponse(
        success=True,
        message="User created successfully.",
        data=profile,
    )


@router.post("/{user_id}/assign-properties", response_model=APIResponse[UserProfile], status_code=status.HTTP_200_OK)
def assign_properties_to_user(
    user_id: uuid.UUID,
    payload: UserPropertyAssign,
    current_user: User = Depends(require_roles("SUPER_ADMIN")),
    db: Session = Depends(get_db),
):
    """
    Assign/reassign properties to a Property Manager or Staff user. Super Admin only.
    """
    user = assign_user_properties(
        db=db,
        user_id=user_id,
        property_ids=payload.property_ids,
        access_level=payload.access_level,
        assigned_by_user=current_user,
    )
    profile = build_user_profile(db, user)
    return APIResponse(
        success=True,
        message="Property assignments updated successfully.",
        data=profile,
    )
