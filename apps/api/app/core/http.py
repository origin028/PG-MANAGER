"""HTTP middleware: request IDs, security headers."""
import time
import uuid

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request

from app.core.config import settings
from app.core.logging import logger

_SECURITY_HEADERS = {
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "no-referrer",
    "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
    "Cross-Origin-Resource-Policy": "same-site",
}


class RequestContextMiddleware(BaseHTTPMiddleware):
    """Attaches a request id, logs one line per request, and sets security headers."""

    async def dispatch(self, request: Request, call_next):
        request_id = request.headers.get("X-Request-ID", "")[:64] or uuid.uuid4().hex
        request.state.request_id = request_id
        started = time.perf_counter()
        response = await call_next(request)
        elapsed_ms = int((time.perf_counter() - started) * 1000)
        response.headers["X-Request-ID"] = request_id
        for name, value in _SECURITY_HEADERS.items():
            response.headers.setdefault(name, value)
        if settings.is_production:
            response.headers.setdefault("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
        if request.url.path.startswith("/api"):
            response.headers.setdefault("Cache-Control", "no-store")
            logger.info(
                "request_id=%s %s %s -> %s %dms",
                request_id, request.method, request.url.path, response.status_code, elapsed_ms,
            )
        return response
