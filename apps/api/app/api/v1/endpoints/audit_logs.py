import uuid
from typing import Optional
from fastapi import APIRouter, Depends, Query, status
import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.dependencies import get_db, require_roles
from app.models.audit_log import AuditLog
from app.models.user import User
from app.schemas.common import APIResponse, PaginatedData

router = APIRouter()


@router.get("", response_model=APIResponse[PaginatedData[dict]], status_code=status.HTTP_200_OK)
def get_audit_logs(
    action: Optional[str] = Query(None, description="Action filter"),
    resource_type: Optional[str] = Query(None, description="Resource type filter"),
    property_id: Optional[uuid.UUID] = Query(None, description="Property filter"),
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=1, le=100),
    current_user: User = Depends(require_roles("SUPER_ADMIN")),
    db: Session = Depends(get_db),
):
    """Retrieves operational audit trail. Restricted to Super Admin."""
    query = sa.select(AuditLog).where(AuditLog.company_id == current_user.company_id)
    if action:
        query = query.where(AuditLog.action == action)
    if resource_type:
        query = query.where(AuditLog.resource_type == resource_type)
    if property_id:
        query = query.where(AuditLog.property_id == property_id)

    total = db.scalar(sa.select(sa.func.count()).select_from(query.subquery())) or 0
    offset = (page - 1) * page_size
    logs = list(db.scalars(query.order_by(AuditLog.created_at.desc()).offset(offset).limit(page_size)).all())

    items = [
        {
            "id": str(log.id),
            "action": log.action,
            "resource_type": log.resource_type,
            "resource_id": log.resource_id,
            "user_email": log.user_email,
            "user_role": log.user_role,
            "property_id": str(log.property_id) if log.property_id else None,
            "details": log.details,
            "created_at": log.created_at.isoformat(),
        }
        for log in logs
    ]
    total_pages = (total + page_size - 1) // page_size if total > 0 else 1

    return APIResponse(
        success=True,
        message=f"Retrieved {len(items)} audit logs.",
        data=PaginatedData(
            items=items,
            total=total,
            page=page,
            page_size=page_size,
            total_pages=total_pages,
        ),
    )
