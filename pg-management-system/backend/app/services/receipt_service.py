import uuid
from typing import Dict, Any


class ReceiptService:
    def generate_receipt_data(self, payment_id: uuid.UUID) -> Dict[str, Any]:
        """Prepares receipt metadata for PDF generation or client rendering."""
        return {
            "receipt_id": str(uuid.uuid4()),
            "payment_id": str(payment_id),
            "status": "ISSUED",
        }
