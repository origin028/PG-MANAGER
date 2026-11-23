import uuid
from datetime import datetime
from typing import List, Optional
from pydantic import BaseModel, ConfigDict, Field


class FoodMenuBase(BaseModel):
    day_of_week: str = Field(..., description="MONDAY, TUESDAY, WEDNESDAY, THURSDAY, FRIDAY, SATURDAY, SUNDAY")
    meal_type: str = Field(..., description="BREAKFAST, LUNCH, DINNER")
    start_time: Optional[str] = Field(None, max_length=10, description="e.g. 08:00 AM")
    end_time: Optional[str] = Field(None, max_length=10, description="e.g. 10:00 AM")
    dishes: List[str] = Field(default_factory=list, description="List of dishes/items served")
    is_active: bool = True


class FoodMenuCreate(FoodMenuBase):
    property_id: uuid.UUID


class FoodMenuUpdate(BaseModel):
    day_of_week: Optional[str] = None
    meal_type: Optional[str] = None
    start_time: Optional[str] = None
    end_time: Optional[str] = None
    dishes: Optional[List[str]] = None
    is_active: Optional[bool] = None


class FoodMenuRead(BaseModel):
    id: uuid.UUID
    property_id: uuid.UUID
    day_of_week: str
    meal_type: str
    start_time: Optional[str] = None
    end_time: Optional[str] = None
    dishes: List[str]
    is_active: bool
    created_at: datetime
    updated_at: datetime
    property_name: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)
