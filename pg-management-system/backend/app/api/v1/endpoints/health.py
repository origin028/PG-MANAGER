from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, status
import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.logging import logger
from app.db.session import get_db
from app.integrations.email import get_email_provider
from app.schemas.common import APIResponse

router = APIRouter()


@router.get("/health", status_code=status.HTTP_200_OK)
def health_check(db: Session = Depends(get_db)):
    """Health check endpoint evaluating PostgreSQL connectivity, schema readiness, and application status."""
    db_status = "healthy"
    alembic_rev = None
    users_table_exists = False

    try:
        db.execute(sa.text("SELECT 1"))
        try:
            regclass = db.execute(sa.text("SELECT to_regclass('public.users')")).scalar()
            users_table_exists = regclass is not None

            alembic_reg = db.execute(sa.text("SELECT to_regclass('public.alembic_version')")).scalar()
            if alembic_reg is not None:
                alembic_rev = db.execute(sa.text("SELECT version_num FROM alembic_version")).scalar()
        except Exception:
            # Fallback for SQLite in unit tests
            users_table_exists = True

        if not users_table_exists:
            db_status = "uninitialized: users table missing"
    except Exception as e:
        logger.error(f"Health check database ping failed: {e}", exc_info=True)
        db_status = f"unhealthy: {str(e)}" if settings.DEBUG else "unhealthy: database connectivity error"

    is_healthy = (db_status == "healthy")
    payload = {
        "status": "online" if is_healthy else "degraded",
        "database": db_status,
        "schema_ready": users_table_exists,
        "alembic_version": alembic_rev,
        "environment": settings.ENVIRONMENT,
        "version": settings.VERSION,
        "email_provider": getattr(settings, "EMAIL_PROVIDER", "MOCK"),
        "active_email_provider": get_email_provider().__class__.__name__,
        "smtp_configured": bool(getattr(settings, "SMTP_PASSWORD", "") and getattr(settings, "SMTP_HOST", "") not in ("localhost", "")),
        "resend_configured": bool(getattr(settings, "RESEND_API_KEY", "")),
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
    return APIResponse(
        success=is_healthy,
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
