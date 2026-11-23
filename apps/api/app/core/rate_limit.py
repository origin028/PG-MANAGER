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
