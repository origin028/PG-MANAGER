from typing import Any, Optional
from fastapi import HTTPException, status


class PGException(HTTPException):
    """Base application exception for PG Management System."""
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
    def __init__(self, message: str = "Authentication failed.", details: Optional[Any] = None):
        super().__init__(
            status_code=status.HTTP_401_UNAUTHORIZED,
            message=message,
            code="AUTHENTICATION_FAILED",
            details=details,
        )


class PermissionDeniedError(PGException):
    def __init__(self, message: str = "Access denied. Insufficient permissions.", details: Optional[Any] = None):
        super().__init__(
            status_code=status.HTTP_403_FORBIDDEN,
            message=message,
            code="PERMISSION_DENIED",
            details=details,
        )


class NotFoundError(PGException):
    def __init__(self, message: str = "Resource not found.", details: Optional[Any] = None):
        super().__init__(
            status_code=status.HTTP_404_NOT_FOUND,
            message=message,
            code="NOT_FOUND",
            details=details,
        )


class ConflictError(PGException):
    def __init__(self, message: str = "Resource conflict occurred.", details: Optional[Any] = None):
        super().__init__(
            status_code=status.HTTP_409_CONFLICT,
            message=message,
            code="CONFLICT",
            details=details,
        )


class BadRequestError(PGException):
    def __init__(self, message: str = "Bad request.", details: Optional[Any] = None):
        super().__init__(
            status_code=status.HTTP_400_BAD_REQUEST,
            message=message,
            code="BAD_REQUEST",
            details=details,
        )


class ValidationError(PGException):
    def __init__(self, message: str = "Request validation failed.", details: Optional[Any] = None):
        super().__init__(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            message=message,
            code="VALIDATION_ERROR",
            details=details,
        )


class TooManyRequestsError(PGException):
    def __init__(self, message: str = "Rate limit exceeded. Please try again later.", details: Optional[Any] = None):
        super().__init__(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            message=message,
            code="TOO_MANY_REQUESTS",
            details=details,
        )


class InternalServerError(PGException):
    def __init__(self, message: str = "Internal server error.", details: Optional[Any] = None):
        super().__init__(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            message=message,
            code="INTERNAL_SERVER_ERROR",
            details=details,
        )


class AccountPendingApprovalError(PGException):
    def __init__(
        self,
        message: str = "Your registration is awaiting admin approval. Please wait for approval before logging in.",
        details: Optional[Any] = None,
    ):
        super().__init__(
            status_code=status.HTTP_403_FORBIDDEN,
            message=message,
            code="PENDING_APPROVAL",
            details=details,
        )


class AccountRejectedError(PGException):
    def __init__(
        self,
        message: str = "Your resident registration has been rejected. Please contact PG administrator.",
        details: Optional[Any] = None,
    ):
        super().__init__(
            status_code=status.HTTP_403_FORBIDDEN,
            message=message,
            code="ACCOUNT_REJECTED",
            details=details,
        )


class BedCapacityExceededError(PGException):
    def __init__(
        self,
        message: str = "Your organization has reached its maximum bed capacity of 240. Please contact Origin for assistance.",
        details: Optional[Any] = None,
    ):
        super().__init__(
            status_code=status.HTTP_400_BAD_REQUEST,
            message=message,
            code="BED_CAPACITY_EXCEEDED",
            details=details,
        )
