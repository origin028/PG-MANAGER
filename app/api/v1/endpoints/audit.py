import uuid
from typing import Optional
from fastapi import APIRouter, Depends, Query, status
import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.api.deps import get_db, require_roles
from app.models.audit_log import AuditLog
from app.models.user import User
from app.schemas.audit import AuditLogRead
from app.schemas.common import APIResponse, PaginatedData

router = APIRouter()


@router.get("", response_model=APIResponse[PaginatedData[AuditLogRead]], status_code=status.HTTP_200_OK)
def get_audit_logs(
    action: Optional[str] = Query(None, description="Filter by action name"),
    resource_type: Optional[str] = Query(None, description="Filter by resource type"),
    property_id: Optional[uuid.UUID] = Query(None, description="Filter by property ID"),
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=1, le=100),
    current_user: User = Depends(require_roles("SUPER_ADMIN")),
    db: Session = Depends(get_db),
):
    """
    Retrieve system audit logs. Super Admin only.
    """
    query = sa.select(AuditLog).where(AuditLog.company_id == current_user.company_id)

    if action:
        query = query.where(AuditLog.action == action)
    if resource_type:
        query = query.where(AuditLog.resource_type == resource_type)
    if property_id:
        query = query.where(AuditLog.property_id == property_id)

    total = db.scalar(sa.select(sa.func.count()).select_from(query.subquery())) or 0
    offset = (page - 1) * page_size
    logs = list(
        db.scalars(
            query.order_by(AuditLog.created_at.desc()).offset(offset).limit(page_size)
        ).all()
    )

    items = [AuditLogRead.model_validate(log) for log in logs]
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
