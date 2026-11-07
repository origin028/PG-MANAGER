from typing import Any, Optional
from fastapi import HTTPException, status


class PGException(HTTPException):
    def __init__(
        self,
        status_code: int,
        message: str,
        code: str = "ERROR",
        details: Optional[Any] = None,
    ):
        super().__init__(status_code=status_code, detail=message)
        self.code = code
        self.message = message
        self.details = details


class AuthenticationError(PGException):
    def __init__(self, message: str = "Authentication failed", details: Optional[Any] = None):
        super().__init__(
            status_code=status.HTTP_401_UNAUTHORIZED,
            message=message,
            code="AUTHENTICATION_FAILED",
            details=details,
        )


class PermissionDeniedError(PGException):
    def __init__(self, message: str = "Permission denied", details: Optional[Any] = None):
        super().__init__(
            status_code=status.HTTP_403_FORBIDDEN,
            message=message,
            code="PERMISSION_DENIED",
            details=details,
        )


class NotFoundError(PGException):
    def __init__(self, message: str = "Resource not found", details: Optional[Any] = None):
        super().__init__(
            status_code=status.HTTP_404_NOT_FOUND,
            message=message,
            code="NOT_FOUND",
            details=details,
        )


class ConflictError(PGException):
    def __init__(self, message: str = "Resource conflict occurred", details: Optional[Any] = None):
        super().__init__(
            status_code=status.HTTP_409_CONFLICT,
            message=message,
            code="CONFLICT",
            details=details,
        )


class ValidationError(PGException):
    def __init__(self, message: str = "Validation failed", details: Optional[Any] = None):
        super().__init__(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            message=message,
            code="VALIDATION_ERROR",
            details=details,
        )
