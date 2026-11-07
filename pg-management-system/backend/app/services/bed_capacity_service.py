import uuid
from typing import Any, Dict
import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.core.exceptions import BedCapacityExceededError, NotFoundError
from app.models.bed import Bed
from app.models.property import Company, Property
from app.models.room import Room


class BedCapacityService:
    @staticmethod
    def get_company_bed_usage(company_id: uuid.UUID, db: Session) -> Dict[str, Any]:
        company = db.scalar(sa.select(Company).where(Company.id == company_id))
        if not company:
            raise NotFoundError("Company not found.")

        total_capacity = company.bed_limit or 240

        # Count all non-deleted beds across all properties belonging to this company
        stmt = (
            sa.select(sa.func.count(Bed.id))
            .join(Room, Bed.room_id == Room.id)
            .join(Property, Room.property_id == Property.id)
            .where(
                Property.company_id == company_id,
                Bed.is_deleted == False,
            )
        )
        used_beds = db.scalar(stmt) or 0
        remaining_beds = max(0, total_capacity - used_beds)
        usage_percentage = round((used_beds / total_capacity * 100), 1) if total_capacity > 0 else 0.0
        is_warning_threshold = used_beds >= int(0.9 * total_capacity)  # >= 216 beds for 240
        is_capacity_reached = used_beds >= total_capacity

        return {
            "company_id": str(company_id),
            "company_name": company.name,
            "total_capacity": total_capacity,
            "used_beds": used_beds,
            "remaining_beds": remaining_beds,
            "usage_percentage": usage_percentage,
            "is_warning_threshold": is_warning_threshold,
            "is_capacity_reached": is_capacity_reached,
        }

    @staticmethod
    def assert_can_add_beds(company_id: uuid.UUID, additional_beds: int, db: Session) -> None:
        if additional_beds <= 0:
            return

        # Lock company row with SELECT ... FOR UPDATE on postgresql to prevent concurrency race conditions
        query = sa.select(Company).where(Company.id == company_id)
        try:
            bind = db.get_bind() if hasattr(db, "get_bind") else db.bind
            if bind and bind.dialect.name == "postgresql":
                query = query.with_for_update()
        except Exception:
            if db.bind and getattr(db.bind.dialect, "name", "") == "postgresql":
                query = query.with_for_update()

        company = db.scalar(query)
        if not company:
            raise NotFoundError("Company not found.")

        total_capacity = company.bed_limit or 240

        stmt = (
            sa.select(sa.func.count(Bed.id))
            .join(Room, Bed.room_id == Room.id)
            .join(Property, Room.property_id == Property.id)
            .where(
                Property.company_id == company_id,
                Bed.is_deleted == False,
            )
        )
        used_beds = db.scalar(stmt) or 0

        if used_beds + additional_beds > total_capacity:
            raise BedCapacityExceededError(
                f"Your organization has reached its maximum bed capacity of {total_capacity}. Please contact Origin for assistance."
            )

    @staticmethod
    def assert_can_add_beds_for_property(property_id: uuid.UUID, additional_beds: int, db: Session) -> None:
        prop = db.scalar(sa.select(Property).where(Property.id == property_id))
        if not prop:
            raise NotFoundError("Property not found.")
        BedCapacityService.assert_can_add_beds(prop.company_id, additional_beds, db)

    @staticmethod
    def assert_can_add_beds_for_room(room_id: uuid.UUID, additional_beds: int, db: Session) -> None:
        room = db.scalar(sa.select(Room).where(Room.id == room_id))
        if not room:
            raise NotFoundError("Room not found.")
        BedCapacityService.assert_can_add_beds_for_property(room.property_id, additional_beds, db)
