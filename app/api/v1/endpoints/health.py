from datetime import datetime, timezone
from fastapi import APIRouter, Depends, status
import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.core.config import settings
from app.db.session import get_db
from app.schemas.common import APIResponse

router = APIRouter()


@router.get("/health", status_code=status.HTTP_200_OK)
def health_check(db: Session = Depends(get_db)):
    """Health check endpoint checking application and database connectivity."""
    db_status = "healthy"
    try:
        db.execute(sa.text("SELECT 1"))
    except Exception as e:
        db_status = f"unhealthy: {str(e)}"

    data = {
        "status": "online" if db_status == "healthy" else "degraded",
        "database": db_status,
        "environment": settings.ENVIRONMENT,
        "version": settings.VERSION,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
    return APIResponse(
        success=(db_status == "healthy"),
        message="System health status",
        data=data,
    )
