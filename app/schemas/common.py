from datetime import datetime, timezone
from typing import Any, Generic, List, Optional, TypeVar
from pydantic import BaseModel, ConfigDict, Field

T = TypeVar("T")


class APIResponse(BaseModel, Generic[T]):
    success: bool = True
    message: str = "Operation successful"
    data: Optional[T] = None
    timestamp: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))

    model_config = ConfigDict(from_attributes=True)


class ErrorDetail(BaseModel):
    code: str
    message: str
    details: Optional[Any] = None


class ErrorResponse(BaseModel):
    success: bool = False
    error: ErrorDetail
    timestamp: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class PaginatedData(BaseModel, Generic[T]):
    items: List[T]
    total: int
    page: int
    page_size: int
    total_pages: int

    model_config = ConfigDict(from_attributes=True)
