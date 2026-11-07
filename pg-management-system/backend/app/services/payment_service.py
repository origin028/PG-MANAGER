import uuid
from typing import Optional
from sqlalchemy.orm import Session

from app.core.exceptions import NotFoundError
from app.models.payment import Payment
from app.repositories.payment_repository import PaymentRepository


class PaymentService:
    def __init__(self, db: Session):
        self.db = db
        self.repo = PaymentRepository(db)

    def get_payment(self, payment_id: uuid.UUID) -> Optional[Payment]:
        p = self.repo.get_payment_by_id(payment_id)
        if not p:
            raise NotFoundError(f"Payment with ID '{payment_id}' not found.")
        return p
