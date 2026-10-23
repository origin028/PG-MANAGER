import uuid
from typing import List, Optional
from pydantic import BaseModel, ConfigDict


class RoleBase(BaseModel):
    name: str
    display_name: str
    description: Optional[str] = None
    permissions: List[str] = []


class RoleCreate(RoleBase):
    pass


class RoleRead(RoleBase):
    id: uuid.UUID
    is_system_role: bool

    model_config = ConfigDict(from_attributes=True)
