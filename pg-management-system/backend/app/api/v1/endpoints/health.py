from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, status
import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.logging import logger
from app.db.session import get_db
from app.schemas.common import APIResponse

router = APIRouter()


@router.get("/health", status_code=status.HTTP_200_OK)
def health_check(db: Session = Depends(get_db)):
    """Health check endpoint evaluating PostgreSQL connectivity and application status."""
    db_status = "healthy"
    try:
        db.execute(sa.text("SELECT 1"))
    except Exception as e:
        logger.error(f"Health check database ping failed: {e}", exc_info=True)
        db_status = f"unhealthy: {str(e)}" if settings.DEBUG else "unhealthy: database connectivity error"

    payload = {
        "status": "online" if db_status == "healthy" else "degraded",
        "database": db_status,
        "environment": settings.ENVIRONMENT,
        "version": settings.VERSION,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
    return APIResponse(
        success=(db_status == "healthy"),
        message="System health status.",
        data=payload,
    )


@router.get("/health/live", status_code=status.HTTP_200_OK)
def liveness_check():
    """Liveness probe confirming the application process is running and responding to requests."""
    return {
        "status": "alive",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@router.get("/health/ready", status_code=status.HTTP_200_OK)
def readiness_check(db: Session = Depends(get_db)):
    """Readiness probe evaluating database connection pool availability for serving traffic."""
    try:
        db.execute(sa.text("SELECT 1"))
    except Exception as e:
        logger.error(f"Readiness check database connection failed: {e}")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Database service unavailable",
        )
    return {
        "status": "ready",
        "environment": settings.ENVIRONMENT,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
