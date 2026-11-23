import uuid
from typing import List, Optional, Tuple
import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.models.payment import Payment
from app.models.invoice import Invoice


class PaymentRepository:
    def __init__(self, db: Session):
        self.db = db

    def get_payment_by_id(self, payment_id: uuid.UUID) -> Optional[Payment]:
        return self.db.get(Payment, payment_id)

    def get_by_gateway_payment_id(self, gateway_payment_id: str) -> Optional[Payment]:
        return self.db.scalar(
            sa.select(Payment).where(Payment.gateway_payment_id == gateway_payment_id)
        )

    def list_by_property(
        self,
        property_id: uuid.UUID,
        page: int = 1,
        page_size: int = 20,
    ) -> Tuple[List[Payment], int]:
        query = sa.select(Payment).where(Payment.property_id == property_id)
        total = self.db.scalar(sa.select(sa.func.count()).select_from(query.subquery())) or 0
        offset = (page - 1) * page_size
        payments = list(
            self.db.scalars(
                query.order_by(Payment.created_at.desc()).offset(offset).limit(page_size)
            ).all()
        )
        return payments, total

    def get_invoice_by_id(self, invoice_id: uuid.UUID) -> Optional[Invoice]:
        return self.db.get(Invoice, invoice_id)
