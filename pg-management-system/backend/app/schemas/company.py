from typing import Optional
from pydantic import BaseModel


class CompanyBedCapacity(BaseModel):
    total_capacity: int = 240
    used_beds: int = 0
    remaining_beds: int = 240
    usage_percentage: float = 0.0
    is_warning_threshold: bool = False
    is_capacity_reached: bool = False
    company_id: Optional[str] = None
    company_name: Optional[str] = None
