from contextlib import asynccontextmanager
from pathlib import Path
from fastapi import FastAPI, HTTPException, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles

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

    # Non-destructive database connectivity ping (schema migrations are exclusively managed via preDeployCommand)
    try:
        from app.db.session import engine
        import sqlalchemy as sa
        with engine.connect() as conn:
            conn.execute(sa.text("SELECT 1"))
        logger.info("Database connection verified successfully.")
    except Exception as exc:
        logger.error(f"Database connectivity verification check failed: {type(exc).__name__}")

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


@app.get("/docs", include_in_schema=False)
def redirect_to_swagger():
    """Convenience redirect to Swagger documentation."""
    return RedirectResponse(url="/api/v1/docs")

# Configure Cross-Origin Resource Sharing (CORS)
base_origins = [
    "https://pg-admin-web-nu.vercel.app",
    "http://localhost:8080",
    "http://localhost:8000",
    "http://localhost:5173",
    "http://localhost:5174",
    "http://127.0.0.1:8080",
    "http://127.0.0.1:8000",
    "http://127.0.0.1:5173",
    "http://127.0.0.1:5174",
]
configured_origins = (
    settings.CORS_ORIGINS
    if isinstance(settings.CORS_ORIGINS, list)
    else [str(settings.CORS_ORIGINS)]
)
# Do not use unrestricted "*" when credentials are enabled. Expand to valid origin list.
cors_origins = [o for o in configured_origins if o != "*"]
for o in base_origins:
    if o not in cors_origins:
        cors_origins.append(o)

app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_origin_regex=r"^https?://(localhost|127\.0\.0\.1|.*\.vercel\.app)(:[0-9]+)?$",
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS", "PATCH"],
    allow_headers=["*"],
    expose_headers=["*"],
)


def _attach_cors_headers(request: Request, response: JSONResponse) -> JSONResponse:
    """Explicitly attaches CORS headers to error responses to ensure client receives meaningful errors."""
    origin = request.headers.get("origin")
    if origin:
        response.headers["Access-Control-Allow-Origin"] = origin
        response.headers["Access-Control-Allow-Credentials"] = "true"
        response.headers["Access-Control-Expose-Headers"] = "*"
        response.headers["Vary"] = "Origin"
    return response


@app.middleware("http")
async def add_pna_and_cors_headers(request: Request, call_next):
    if request.method == "OPTIONS":
        origin = request.headers.get("origin", "*")
        response = JSONResponse(content="OK", status_code=200)
        response.headers["Access-Control-Allow-Origin"] = origin
        response.headers["Access-Control-Allow-Credentials"] = "true"
        response.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS, PATCH"
        response.headers["Access-Control-Allow-Headers"] = "*"
        if request.headers.get("access-control-request-private-network"):
            response.headers["Access-Control-Allow-Private-Network"] = "true"
        return response

    response = await call_next(request)
    origin = request.headers.get("origin")
    if origin:
        response.headers["Access-Control-Allow-Origin"] = origin
        response.headers["Access-Control-Allow-Credentials"] = "true"
    if request.headers.get("access-control-request-private-network"):
        response.headers["Access-Control-Allow-Private-Network"] = "true"
    return response


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
    return _attach_cors_headers(request, res)


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
    return _attach_cors_headers(request, res)


@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    res = JSONResponse(
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
    return _attach_cors_headers(request, res)


@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.error(f"Unhandled error processing {request.method} {request.url.path}: {exc}", exc_info=True)
    res = JSONResponse(
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
    return _attach_cors_headers(request, res)


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

# Ensure uploads directory exists on disk for secure storage (not mounted publicly)
uploads_dir = Path(__file__).resolve().parent.parent / "uploads"
uploads_dir.mkdir(parents=True, exist_ok=True)
