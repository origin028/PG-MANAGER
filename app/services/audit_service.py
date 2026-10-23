import uuid
from typing import Any, Dict, Optional
from sqlalchemy.orm import Session

from app.models.audit_log import AuditLog
from app.core.logging import logger


def record_audit_log(
    db: Session,
    action: str,
    resource_type: str,
    user_id: Optional[uuid.UUID] = None,
    user_email: Optional[str] = None,
    user_role: Optional[str] = None,
    company_id: Optional[uuid.UUID] = None,
    property_id: Optional[uuid.UUID] = None,
    resource_id: Optional[str] = None,
    details: Optional[Dict[str, Any]] = None,
    ip_address: Optional[str] = None,
    user_agent: Optional[str] = None,
) -> AuditLog:
    """Records an audit log entry within the current transaction."""
    try:
        log_entry = AuditLog(
            company_id=company_id,
            property_id=property_id,
            user_id=user_id,
            user_email=user_email,
            user_role=user_role,
            action=action,
            resource_type=resource_type,
            resource_id=resource_id,
            details=details or {},
            ip_address=ip_address,
            user_agent=user_agent,
        )
        db.add(log_entry)
        db.commit()
        db.refresh(log_entry)
        return log_entry
    except Exception as e:
        logger.error(f"Failed to record audit log: {e}", exc_info=True)
        db.rollback()
        raise
