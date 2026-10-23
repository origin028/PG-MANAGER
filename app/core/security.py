from datetime import datetime, timedelta, timezone
from typing import Any, Dict, Optional
import bcrypt
import jwt

from app.core.config import settings


def get_password_hash(password: str) -> str:
    """Hashes a password using bcrypt."""
    # Bcrypt has a 72-byte limit; encode to bytes and truncate if needed
    pwd_bytes = password.encode("utf-8")[:72]
    salt = bcrypt.gensalt(rounds=12)
    return bcrypt.hashpw(pwd_bytes, salt).decode("utf-8")


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verifies a plain password against a bcrypt hash."""
    try:
        plain_bytes = plain_password.encode("utf-8")[:72]
        hash_bytes = hashed_password.encode("utf-8")
        return bcrypt.checkpw(plain_bytes, hash_bytes)
    except Exception:
        return False


def create_access_token(
    subject: str,
    claims: Optional[Dict[str, Any]] = None,
    expires_delta: Optional[timedelta] = None,
) -> str:
    """Creates a signed JWT access token."""
    now = datetime.now(timezone.utc)
    if expires_delta:
        expire = now + expires_delta
    else:
        expire = now + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)

    to_encode: Dict[str, Any] = {
        "sub": str(subject),
        "iat": now,
        "exp": expire,
        "type": "access",
    }
    if claims:
        to_encode.update(claims)

    encoded_jwt = jwt.encode(
        to_encode,
        settings.SECRET_KEY,
        algorithm=settings.JWT_ALGORITHM,
    )
    return encoded_jwt


def create_refresh_token(
    subject: str,
    claims: Optional[Dict[str, Any]] = None,
    expires_delta: Optional[timedelta] = None,
) -> str:
    """Creates a signed JWT refresh token."""
    now = datetime.now(timezone.utc)
    if expires_delta:
        expire = now + expires_delta
    else:
        expire = now + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)

    to_encode: Dict[str, Any] = {
        "sub": str(subject),
        "iat": now,
        "exp": expire,
        "type": "refresh",
    }
    if claims:
        to_encode.update(claims)

    encoded_jwt = jwt.encode(
        to_encode,
        settings.SECRET_KEY,
        algorithm=settings.JWT_ALGORITHM,
    )
    return encoded_jwt


def decode_token(token: str) -> Dict[str, Any]:
    """Decodes and validates a JWT token."""
    return jwt.decode(
        token,
        settings.SECRET_KEY,
        algorithms=[settings.JWT_ALGORITHM],
    )
