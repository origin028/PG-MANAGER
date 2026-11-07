import logging
import math
from datetime import datetime, timedelta, timezone
from typing import Optional, Tuple

import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.core.config import settings
from app.integrations.whatsapp import WhatsAppCloudProvider
from app.models.invoice import Invoice
from app.models.payment import Payment
from app.models.property import Property
from app.models.receipt import Receipt
from app.models.resident import Resident
from app.models.room import Room
from app.models.user import User

logger = logging.getLogger(__name__)

# Bounded exponential backoff in seconds for transient retryable delivery errors:
# Attempt 1: ~10s, Attempt 2: ~30s, Attempt 3: ~90s, Attempt 4: ~270s (max 5 attempts)
MAX_DELIVERY_ATTEMPTS = 5
BASE_RETRY_DELAY_SECONDS = 10


def calculate_backoff_seconds(attempt: int) -> int:
    """Calculates bounded exponential backoff delay in seconds."""
    # 10 * 3^(attempt - 1) up to a max cap of 3600 seconds (1 hour)
    delay = BASE_RETRY_DELAY_SECONDS * int(math.pow(3, max(0, attempt - 1)))
    return min(delay, 3600)


def is_permanent_whatsapp_error(error_message: str) -> bool:
    """Classifies WhatsApp provider error messages as permanent vs retryable."""
    err_lower = error_message.lower()
    # Configuration errors, invalid recipient phone numbers, or unapproved template errors are permanent
    permanent_signals = [
        "not configured",
        "invalid parameter",
        "recipient phone number not in allowed list",
        "template does not exist",
        "user is not a valid whatsapp user",
        "unsupported phone number",
        "invalid phone number",
        "template name",
    ]
    return any(sig in err_lower for sig in permanent_signals)


class ReceiptDeliveryService:
    """Delivers WhatsApp payment receipts for settled payments with bounded retry.

    DELIVERY GUARANTEES & DISTRIBUTED SEMANTICS:
      - Internal Financial Settlement: STRICTLY EXACTLY-ONCE. Payment settlement,
        invoice paid-amount recalculation, and receipt record creation occur within
        a single atomic PostgreSQL transaction protected by pessimistic row locks.
      - External WhatsApp Delivery: AT-LEAST-ONCE. WhatsApp Cloud API is an external
        HTTP service that does not participate in PostgreSQL 2-phase commit (2PC).
        Receipt rows are locked via `with_for_update()` to prevent concurrent worker
        races. However, if the worker process crashes or loses database connectivity
        immediately after Meta accepts the message (HTTP 200) but before `db.commit()`
        records `whatsapp_status = "SENT"`, the subsequent worker pass will retry delivery,
        potentially resulting in a duplicate WhatsApp message.
    """

    def __init__(self, db: Session):
        self.db = db

    def deliver_receipt(self, receipt_id: str | Receipt) -> Tuple[bool, str]:
        """Attempts delivery for a single receipt using row-level locking."""
        if isinstance(receipt_id, Receipt):
            receipt_uuid = receipt_id.id
        else:
            receipt_uuid = receipt_id

        # Lock receipt row to prevent concurrent worker duplication
        receipt = self.db.scalar(
            sa.select(Receipt).where(Receipt.id == receipt_uuid).with_for_update()
        )
        if not receipt:
            return False, f"Receipt {receipt_uuid} not found."

        # Terminal states: already SENT or permanently FAILED
        if receipt.whatsapp_status in ("SENT", "FAILED"):
            return True, f"Receipt already in terminal status '{receipt.whatsapp_status}'."

        now = datetime.now(timezone.utc)
        # Verify next_retry_at constraint if previously retried
        if receipt.next_retry_at:
            retry_at = receipt.next_retry_at
            if retry_at.tzinfo is None:
                retry_at = retry_at.replace(tzinfo=timezone.utc)
            if retry_at > now:
                return False, f"Receipt not due for retry yet. Scheduled at {retry_at}."

        # Fetch relationships securely
        payment = self.db.get(Payment, receipt.payment_id)
        invoice = self.db.get(Invoice, receipt.invoice_id)
        if not payment or not invoice:
            receipt.whatsapp_status = "FAILED"
            receipt.last_delivery_error = "Associated payment or invoice record missing."
            self.db.commit()
            return False, "Associated payment or invoice record missing."

        # Double-check payment validity: NEVER send receipt for unconfirmed/pending payments
        if payment.status not in ("SUCCESS", "PAID"):
            return False, f"Payment is not settled (status: {payment.status}). Receipt delivery aborted."

        resident = self.db.get(Resident, invoice.resident_id)
        if not resident:
            receipt.whatsapp_status = "FAILED"
            receipt.last_delivery_error = "Resident record missing."
            self.db.commit()
            return False, "Resident record missing."

        user = self.db.get(User, resident.user_id)
        if not user or not user.phone:
            receipt.whatsapp_status = "FAILED"
            receipt.last_delivery_error = "Resident phone number missing."
            self.db.commit()
            return False, "Resident phone number missing."

        prop = self.db.get(Property, invoice.property_id)
        room = self.db.get(Room, resident.room_id) if resident.room_id else None

        # Build approved template parameters:
        # [property_name, room_number, resident_name, receipt_number, invoice_number, amount_str, payment_date, payment_mode]
        property_name = prop.name if prop else "PG"
        room_number = room.room_number if room else "N/A"
        resident_name = user.full_name or "Resident"
        receipt_number = receipt.receipt_number
        invoice_number = invoice.invoice_number
        amount_str = f"Rs. {receipt.amount:.2f}"
        paid_date_str = (payment.paid_at or receipt.issued_at).strftime("%d-%b-%Y %I:%M %p")
        payment_mode = payment.payment_mode or "UPI"

        template = settings.WHATSAPP_RECEIPT_TEMPLATE or "rent_receipt_v1"
        parameters = [
            property_name,
            room_number,
            resident_name,
            receipt_number,
            invoice_number,
            amount_str,
            paid_date_str,
            payment_mode,
        ]

        receipt.whatsapp_attempts += 1

        try:
            provider = WhatsAppCloudProvider(
                phone_number_id=settings.WHATSAPP_PHONE_NUMBER_ID,
                access_token=settings.WHATSAPP_ACCESS_TOKEN,
            )
            msg_id = provider.send_template(user.phone, template, parameters)

            receipt.whatsapp_status = "SENT"
            receipt.next_retry_at = None
            receipt.last_delivery_error = None
            self.db.commit()
            logger.info(f"Receipt {receipt.receipt_number} sent via WhatsApp (msg_id: {msg_id})")
            return True, f"Receipt sent successfully (msg_id: {msg_id})."
        except Exception as exc:
            err_msg = str(exc)
            logger.warning(f"Receipt delivery attempt {receipt.whatsapp_attempts} failed: {err_msg}")
            receipt.last_delivery_error = err_msg

            if is_permanent_whatsapp_error(err_msg) or receipt.whatsapp_attempts >= MAX_DELIVERY_ATTEMPTS:
                receipt.whatsapp_status = "FAILED"
                receipt.next_retry_at = None
            else:
                receipt.whatsapp_status = "PENDING"
                delay = calculate_backoff_seconds(receipt.whatsapp_attempts)
                receipt.next_retry_at = now + timedelta(seconds=delay)

            self.db.commit()
            return False, err_msg

    def process_due_receipts(self, limit: int = 50) -> int:
        """Processes pending receipts ready for initial delivery or scheduled retry."""
        now = datetime.now(timezone.utc)
        due_receipt_ids = list(
            self.db.scalars(
                sa.select(Receipt.id)
                .where(
                    Receipt.whatsapp_status == "PENDING",
                    sa.or_(
                        Receipt.next_retry_at.is_(None),
                        Receipt.next_retry_at <= now,
                    ),
                )
                .order_by(Receipt.created_at.asc())
                .limit(limit)
            ).all()
        )

        sent_count = 0
        for r_id in due_receipt_ids:
            success, _ = self.deliver_receipt(r_id)
            if success:
                sent_count += 1
        return sent_count
