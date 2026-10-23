from contextlib import asynccontextmanager
from fastapi import FastAPI, HTTPException, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.api.router import api_router
from app.core.config import settings
from app.core.exceptions import PGException
from app.core.logging import logger, setup_logging
from app.schemas.common import ErrorDetail, ErrorResponse


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup lifecycle
    setup_logging()
    logger.info(f"Starting {settings.PROJECT_NAME} v{settings.VERSION} [{settings.ENVIRONMENT}]")
    yield
    # Shutdown lifecycle
    logger.info("Application shutdown completed.")


app = FastAPI(
    title=settings.PROJECT_NAME,
    version=settings.VERSION,
    description="Unified Backend API for Origin PG Management System supporting Admin Web, Admin Android, and Resident Android clients.",
    openapi_url="/api/v1/openapi.json",
    docs_url="/api/v1/docs",
    redoc_url="/api/v1/redoc",
    lifespan=lifespan,
)

# Configure Cross-Origin Resource Sharing (CORS)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS if isinstance(settings.CORS_ORIGINS, list) else ["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# Global Exception Handlers
@app.exception_handler(PGException)
async def pg_exception_handler(request: Request, exc: PGException):
    return JSONResponse(
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


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    errors = []
    for err in exc.errors():
        field_loc = " -> ".join(str(loc) for loc in err.get("loc", []))
        errors.append(f"{field_loc}: {err.get('msg')}")
    return JSONResponse(
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


@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    return JSONResponse(
        status_code=exc.status_code,
        content=ErrorResponse(
            success=False,
            error=ErrorDetail(
                code="HTTP_ERROR",
                message=str(exc.detail),
                details=None,
            ),
        ).model_dump(mode="json"),
    )


@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.error(f"Unhandled error processing {request.method} {request.url.path}: {exc}", exc_info=True)
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content=ErrorResponse(
            success=False,
            error=ErrorDetail(
                code="INTERNAL_SERVER_ERROR",
                message="An unexpected server error occurred. Please contact administrator.",
                details=str(exc) if settings.DEBUG else None,
            ),
        ).model_dump(mode="json"),
    )


# Root discovery endpoint
@app.get("/", tags=["Root"])
def root():
    return {
        "service": settings.PROJECT_NAME,
        "version": settings.VERSION,
        "docs": "/api/v1/docs",
        "health": "/api/v1/health",
    }


# Mount the versioned API router under /api
app.include_router(api_router, prefix="/api")
