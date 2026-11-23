import uuid
from typing import Optional
from sqlalchemy.orm import Session

from app.core.exceptions import ConflictError, NotFoundError
from app.models.bed import Bed


class BedAllocationService:
    def __init__(self, db: Session):
        self.db = db

    def allocate_bed(self, bed_id: uuid.UUID, resident_id: uuid.UUID) -> Bed:
        """
        Atomically allocates a bed to a resident.
        Prevents double-booking via transaction row locking.
        """
        bed = self.db.get(Bed, bed_id, with_for_update=True)
        if not bed:
            raise NotFoundError(f"Bed with ID '{bed_id}' not found.")

        if bed.status != "AVAILABLE":
            raise ConflictError(f"Bed '{bed.bed_number}' is not available (current status: {bed.status}).")

        bed.status = "OCCUPIED"
        self.db.commit()
        self.db.refresh(bed)
        return bed

    def release_bed(self, bed_id: uuid.UUID) -> Bed:
        """Releases an occupied bed back to AVAILABLE status upon checkout."""
        bed = self.db.get(Bed, bed_id, with_for_update=True)
        if not bed:
            raise NotFoundError(f"Bed with ID '{bed_id}' not found.")

        bed.status = "AVAILABLE"
        self.db.commit()
        self.db.refresh(bed)
        return bed
