import uuid
from typing import List, Optional
import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.models.room import Room
from app.models.bed import Bed


class RoomRepository:
    def __init__(self, db: Session):
        self.db = db

    def get_by_id(self, room_id: uuid.UUID) -> Optional[Room]:
        return self.db.get(Room, room_id)

    def list_by_property(self, property_id: uuid.UUID, floor_number: Optional[int] = None) -> List[Room]:
        query = sa.select(Room).where(Room.property_id == property_id, Room.is_active == True)
        if floor_number is not None:
            query = query.where(Room.floor_number == floor_number)
        return list(self.db.scalars(query.order_by(Room.room_number.asc())).all())

    def get_bed_by_id(self, bed_id: uuid.UUID) -> Optional[Bed]:
        return self.db.get(Bed, bed_id)

    def list_beds_by_room(self, room_id: uuid.UUID) -> List[Bed]:
        query = sa.select(Bed).where(Bed.room_id == room_id).order_by(Bed.bed_number.asc())
        return list(self.db.scalars(query).all())
