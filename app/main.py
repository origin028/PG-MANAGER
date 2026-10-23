from contextlib import asynccontextmanager
from fastapi import FastAPI, HTTPException, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.api.v1.router import api_router
from app.core.config import settings
from app.core.exceptions import PGException
from app.core.logging import logger, setup_logging
from app.db.base import Base
from app.db.session import engine
from app.schemas.common import ErrorDetail, ErrorResponse


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    setup_logging()
    logger.info(f"Starting {settings.PROJECT_NAME} v{settings.VERSION} [{settings.ENVIRONMENT}]")
    # For SQLite local dev: automatically create tables if needed
    if settings.DATABASE_URL.startswith("sqlite"):
        Base.metadata.create_all(bind=engine)
        logger.info("SQLite database tables verified/created.")
    yield
    # Shutdown
    logger.info("Shutting down application...")


app = FastAPI(
    title=settings.PROJECT_NAME,
    version=settings.VERSION,
    description="Production backend API for Origin PG Management System supporting Admin Web, Admin Android, and Resident Android clients.",
    openapi_url=f"{settings.API_V1_STR}/openapi.json",
    docs_url=f"{settings.API_V1_STR}/docs",
    redoc_url=f"{settings.API_V1_STR}/redoc",
    lifespan=lifespan,
)

# CORS Configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS if isinstance(settings.CORS_ORIGINS, list) else ["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# Exception Handlers
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
                message="Request validation failed.",
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
    logger.error(f"Unhandled exception on {request.method} {request.url.path}: {exc}", exc_info=True)
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content=ErrorResponse(
            success=False,
            error=ErrorDetail(
                code="INTERNAL_SERVER_ERROR",
                message="An unexpected server error occurred. Please try again later.",
                details=str(exc) if settings.DEBUG else None,
            ),
        ).model_dump(mode="json"),
    )


# Root health redirect/check
@app.get("/", tags=["Root"])
def root():
    return {
        "service": settings.PROJECT_NAME,
        "version": settings.VERSION,
        "docs": f"{settings.API_V1_STR}/docs",
        "health": f"{settings.API_V1_STR}/health",
    }


# Mount API V1 router
app.include_router(api_router, prefix=settings.API_V1_STR)
