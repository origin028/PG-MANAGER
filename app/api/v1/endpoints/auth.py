from fastapi import APIRouter, Depends, Request, status
from sqlalchemy.orm import Session

from app.api.deps import get_current_user, get_db
from app.models.user import User
from app.schemas.auth import (
    LoginRequest,
    PasswordChangeRequest,
    RefreshRequest,
    TokenResponse,
)
from app.schemas.common import APIResponse
from app.schemas.user import UserProfile
from app.services.auth_service import (
    build_user_profile,
    change_password,
    login_user,
    refresh_access_token,
    revoke_token,
)

router = APIRouter()


@router.post("/login", response_model=APIResponse[TokenResponse], status_code=status.HTTP_200_OK)
def login(
    payload: LoginRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    """
    Authenticate user across Admin Web, Admin Mobile, or Resident Mobile client.
    Enforces role separation: Residents cannot access Admin clients; Admins cannot access Resident app.
    """
    ip_address = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")

    token_data = login_user(
        db=db,
        identifier=payload.identifier,
        password=payload.password,
        client_type=payload.client_type,
        device_info=payload.device_info,
        ip_address=ip_address,
        user_agent=user_agent,
    )
    return APIResponse(
        success=True,
        message=f"Authenticated successfully as {token_data.user.role.display_name}.",
        data=token_data,
    )


@router.post("/refresh", response_model=APIResponse[TokenResponse], status_code=status.HTTP_200_OK)
def refresh(
    payload: RefreshRequest,
    db: Session = Depends(get_db),
):
    """
    Refreshes access token using a valid, unrevoked refresh token.
    """
    token_data = refresh_access_token(
        db=db,
        refresh_token_str=payload.refresh_token,
        client_type=payload.client_type,
    )
    return APIResponse(
        success=True,
        message="Token refreshed successfully.",
        data=token_data,
    )


@router.post("/logout", response_model=APIResponse[dict], status_code=status.HTTP_200_OK)
def logout(
    payload: RefreshRequest,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Logs out the user and revokes the submitted refresh token.
    """
    ip_address = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")

    revoke_token(
        db=db,
        refresh_token_str=payload.refresh_token,
        user=current_user,
        ip_address=ip_address,
        user_agent=user_agent,
    )
    return APIResponse(
        success=True,
        message="Logged out successfully. Refresh token revoked.",
        data={"user_id": str(current_user.id)},
    )


@router.get("/me", response_model=APIResponse[UserProfile], status_code=status.HTTP_200_OK)
def get_current_user_profile(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Returns full profile of the authenticated user, including role and accessible properties.
    """
    profile = build_user_profile(db, current_user)
    return APIResponse(
        success=True,
        message="Profile retrieved successfully.",
        data=profile,
    )


@router.post("/change-password", response_model=APIResponse[dict], status_code=status.HTTP_200_OK)
def update_password(
    payload: PasswordChangeRequest,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Allows authenticated user to change password. All active refresh sessions are revoked.
    """
    ip_address = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")

    change_password(
        db=db,
        user=current_user,
        current_password=payload.current_password,
        new_password=payload.new_password,
        ip_address=ip_address,
        user_agent=user_agent,
    )
    return APIResponse(
        success=True,
        message="Password updated successfully. All active sessions have been revoked.",
        data={"user_id": str(current_user.id)},
    )
