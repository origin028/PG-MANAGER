"""Small in-process sliding-window rate limiter.

Single-instance by design (this deployment runs one API process; 800 residents).
If the API is ever scaled to several instances, swap ``_hits`` for Redis behind the
same ``rate_limit`` dependency without touching any endpoint.
"""
import threading
import time
from collections import defaultdict, deque
from typing import Deque, Dict

from fastapi import Request

from app.core.config import settings
from app.core.exceptions import PGException

_lock = threading.Lock()
_hits: Dict[str, Deque[float]] = defaultdict(deque)


def reset_rate_limits() -> None:
    with _lock:
        _hits.clear()
        _failures.clear()


def client_ip(request: Request) -> str:
    return request.client.host if request.client else "unknown"


def hit(key: str, limit: int, window_seconds: int) -> int:
    """Records a hit; returns 0 if allowed, otherwise seconds until retry."""
    now = time.monotonic()
    with _lock:
        q = _hits[key]
        while q and now - q[0] > window_seconds:
            q.popleft()
        if len(q) >= limit:
            return max(1, int(window_seconds - (now - q[0])))
        q.append(now)
        return 0


def rate_limit(bucket: str, limit: int, window_seconds: int):
    """FastAPI dependency limiting ``limit`` requests per ``window_seconds`` per client IP."""

    def dependency(request: Request) -> None:
        if not settings.RATE_LIMIT_ENABLED:
            return
        retry_after = hit(f"{bucket}:{client_ip(request)}", limit, window_seconds)
        if retry_after:
            raise PGException(
                status_code=429,
                message=f"Too many requests. Try again in {retry_after} seconds.",
                code="RATE_LIMITED",
                details={"retry_after_seconds": retry_after},
            )

    return dependency


# ---- Account lockout (failed credential attempts) ---------------------------
_failures: Dict[str, Deque[float]] = defaultdict(deque)


def lockout_seconds_remaining(key: str) -> int:
    """Seconds until the account may retry, or 0 when not locked."""
    window = settings.LOGIN_LOCKOUT_MINUTES * 60
    now = time.monotonic()
    with _lock:
        q = _failures[key]
        while q and now - q[0] > window:
            q.popleft()
        if len(q) >= settings.LOGIN_MAX_ATTEMPTS:
            return max(1, int(window - (now - q[0])))
    return 0


def record_failure(key: str) -> None:
    with _lock:
        _failures[key].append(time.monotonic())


def clear_failures(key: str) -> None:
    with _lock:
        _failures.pop(key, None)


# ---- Per-route limits for the auth router -----------------------------------
# (path suffix, limit, window seconds). OTP routes send email, so they are the tightest.
AUTH_LIMITS = [
    ("/otp/request", 5, 300),
    ("/otp/verify", 10, 300),
    ("/resend-otp", 5, 300),
    ("/login/verify", 10, 300),
    ("/register/verify", 10, 300),
    ("/change-password/request-otp", 5, 300),
    ("/change-password/verify-otp", 10, 300),
    ("/change-password/reset-with-otp", 10, 300),
    ("/admin/register", 5, 3600),
    ("/resident/register", 10, 3600),
    ("/admin/login", 10, 60),
    ("/login", 10, 60),
    ("/refresh", 30, 60),
]


def auth_throttle(request: Request) -> None:
    """Router-level dependency applying the strictest matching limit for the auth path."""
    if not settings.RATE_LIMIT_ENABLED:
        return
    path = request.url.path.rstrip("/")
    for suffix, limit, window in AUTH_LIMITS:
        if path.endswith(suffix):
            retry_after = hit(f"auth{suffix}:{client_ip(request)}", limit, window)
            if retry_after:
                raise PGException(
                    status_code=429,
                    message=f"Too many requests. Try again in {retry_after} seconds.",
                    code="RATE_LIMITED",
                    details={"retry_after_seconds": retry_after},
                )
            return
