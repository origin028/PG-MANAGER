from contextlib import asynccontextmanager
from fastapi import FastAPI, HTTPException, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.api.router import api_router
from app.core.config import settings
from app.core.exceptions import PGException
from app.core.http import RequestContextMiddleware
from app.core.logging import logger, setup_logging
from app.schemas.common import ErrorDetail, ErrorResponse


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup lifecycle
    setup_logging()
    logger.info(f"Starting {settings.PROJECT_NAME} v{settings.VERSION} [{settings.ENVIRONMENT}]")

    # 1. Non-destructive database connectivity ping
    try:
        from app.db.session import engine
        import sqlalchemy as sa
        with engine.connect() as conn:
            conn.execute(sa.text("SELECT 1"))
        logger.info("Database connection verified successfully.")
    except Exception as exc:
        logger.error(f"Database connectivity verification check failed: {type(exc).__name__}")
        if settings.is_production:
            raise RuntimeError("Database connectivity check failed on startup.") from exc

    # 2. Idempotent system role bootstrap (schema is migrated by the release step, never at boot)
    try:
        from app.db.session import SessionLocal
        from app.services.role_service import ensure_system_roles_exist

        with SessionLocal() as db:
            ensure_system_roles_exist(db)
        logger.info("System roles verified and active.")
    except Exception as exc:
        logger.error(f"Error ensuring system roles on startup: {exc}", exc_info=True)
        if settings.is_production:
            raise RuntimeError("System role bootstrap failed. Run `alembic upgrade head` first.") from exc

    yield
    # Shutdown lifecycle
    logger.info("Application shutdown completed.")


app = FastAPI(
    title=settings.PROJECT_NAME,
    version=settings.VERSION,
    description="Unified backend API for the Origin PG Management System (admin web/app and resident web/app).",
    openapi_url="/api/v1/openapi.json" if settings.docs_enabled else None,
    docs_url="/api/v1/docs" if settings.docs_enabled else None,
    redoc_url=None,
    lifespan=lifespan,
)

# Explicit allow-list only. Never reflect arbitrary origins.
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "X-Property-Id", "X-Request-ID", "Idempotency-Key"],
    expose_headers=["X-Request-ID"],
    max_age=600,
)
app.add_middleware(RequestContextMiddleware)


_HTTP_ERROR_CODES = {
    400: "BAD_REQUEST", 401: "UNAUTHENTICATED", 403: "FORBIDDEN", 404: "NOT_FOUND",
    405: "METHOD_NOT_ALLOWED", 409: "CONFLICT", 413: "PAYLOAD_TOO_LARGE",
    415: "UNSUPPORTED_MEDIA_TYPE", 422: "VALIDATION_ERROR", 429: "RATE_LIMITED",
}


# Global Exception Handlers
@app.exception_handler(PGException)
async def pg_exception_handler(request: Request, exc: PGException):
    res = JSONResponse(
        status_code=exc.status_code,
        content=ErrorResponse(
            success=False,
            error=ErrorDetail(
                code=exc.code,
                message=exc.message,
                details=exc.details,
            ),
        ).model_dump(mode="json"),
    )
    return res


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    errors = []
    for err in exc.errors():
        field_loc = " -> ".join(str(loc) for loc in err.get("loc", []))
        errors.append(f"{field_loc}: {err.get('msg')}")
    res = JSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
        content=ErrorResponse(
            success=False,
            error=ErrorDetail(
                code="VALIDATION_ERROR",
                message="Request payload validation failed.",
                details=errors,
            ),
        ).model_dump(mode="json"),
    )
    return res


@app.exception_handler(StarletteHTTPException)
async def http_exception_handler(request: Request, exc: StarletteHTTPException):
    res = JSONResponse(
        status_code=exc.status_code,
        content=ErrorResponse(
            success=False,
            error=ErrorDetail(
                code=_HTTP_ERROR_CODES.get(exc.status_code, "HTTP_ERROR"),
                message=str(exc.detail),
                details=None,
            ),
        ).model_dump(mode="json"),
    )
    return res


@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.error(
        "request_id=%s unhandled error on %s %s", getattr(request.state, "request_id", "-"),
        request.method, request.url.path, exc_info=True,
    )
    res = JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content=ErrorResponse(
            success=False,
            error=ErrorDetail(
                code="INTERNAL_SERVER_ERROR",
                message="An unexpected server error occurred. Please contact administrator.",
                details=None,
            ),
        ).model_dump(mode="json"),
    )
    return res


# Root discovery endpoint
@app.get("/", tags=["Root"])
def root():
    payload = {
        "service": settings.PROJECT_NAME,
        "version": settings.VERSION,
        "health": "/api/v1/health",
    }
    if settings.docs_enabled:
        payload["docs"] = "/api/v1/docs"
    return payload


# Mount the versioned API router under /api
app.include_router(api_router, prefix="/api")
