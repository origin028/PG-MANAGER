import uuid
from typing import Optional
from sqlalchemy.orm import Session

from app.core.exceptions import NotFoundError
from app.models.invoice import Invoice


class InvoiceService:
    def __init__(self, db: Session):
        self.db = db

    def get_invoice(self, invoice_id: uuid.UUID) -> Optional[Invoice]:
        inv = self.db.get(Invoice, invoice_id)
        if not inv:
            raise NotFoundError(f"Invoice with ID '{invoice_id}' not found.")
        return inv
