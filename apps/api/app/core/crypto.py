"""Symmetric encryption for sensitive files (KYC) stored at rest."""
from cryptography.fernet import Fernet, InvalidToken

from app.core.config import settings

_fernet = None


def _get() -> Fernet:
    global _fernet
    if _fernet is None:
        _fernet = Fernet(settings.ENCRYPTION_KEY.encode())
    return _fernet


def encrypt_bytes(data: bytes) -> bytes:
    return _get().encrypt(data)


def decrypt_bytes(token: bytes) -> bytes:
    try:
        return _get().decrypt(token)
    except InvalidToken as exc:
        raise ValueError("Stored document could not be decrypted (wrong key or corrupted file).") from exc
