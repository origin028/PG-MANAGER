import logging
import uuid
from datetime import datetime, timezone
from decimal import Decimal
from typing import Any, Dict, Optional, Tuple

import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.models.invoice import Invoice
from app.models.payment import Payment
from app.models.receipt import Receipt
from app.models.webhook_event import ProcessedWebhookEvent

logger = logging.getLogger(__name__)


class WebhookSettlementService:
    """Service responsible for atomic payment and invoice settlement triggered by webhooks."""

    def __init__(self, db: Session):
        self.db = db

    def is_event_processed(self, event_id: str) -> bool:
        """Checks if a provider webhook event ID has already been recorded."""
        if not event_id:
            return False
        return (
            self.db.scalar(
                sa.select(
                    sa.select(ProcessedWebhookEvent)
                    .where(ProcessedWebhookEvent.event_id == event_id)
                    .exists()
                )
            )
            is True
        )

    def record_processed_event(
        self, provider: str, event_id: str, event_type: str, status: str = "PROCESSED"
    ) -> ProcessedWebhookEvent:
        """Records a successfully processed or recognized provider event."""
        event_record = ProcessedWebhookEvent(
            provider=provider,
            event_id=event_id,
            event_type=event_type,
            status=status,
        )
        self.db.add(event_record)
        return event_record

    def settle_payment_captured(
        self,
        provider_order_id: str,
        provider_payment_id: str,
        amount_paise: int,
        currency: str,
        payment_method: Optional[str] = None,
        event_id: Optional[str] = None,
        raw_event: Optional[Dict[str, Any]] = None,
    ) -> Tuple[bool, str, Optional[Receipt]]:
        """Atomically settles a captured payment, updates invoice state, and creates a receipt.

        Returns (success: bool, message: str, receipt: Optional[Receipt]).
        """
        if currency.upper() != "INR":
            return False, f"Unsupported currency '{currency}'. Only INR is accepted.", None

        # 1. Deduplicate by provider event ID if provided
        if event_id and self.is_event_processed(event_id):
            # Already processed event - lookup existing receipt if available
            existing_payment = self.db.scalar(
                sa.select(Payment).where(Payment.gateway_payment_id == provider_payment_id)
            )
            existing_receipt = (
                self.db.scalar(
                    sa.select(Receipt).where(Receipt.payment_id == existing_payment.id)
                )
                if existing_payment
                else None
            )
            return True, "Webhook event already processed.", existing_receipt

        # 2. Lock the target payment row using PostgreSQL row lock
        payment = self.db.scalar(
            sa.select(Payment)
            .where(Payment.gateway_order_id == provider_order_id)
            .with_for_update()
        )
        if not payment:
            # Payment record not found for provider order ID
            return False, f"No payment request found for gateway order {provider_order_id}.", None

        # If payment is already marked SUCCESS:
        if payment.status == "SUCCESS":
            existing_receipt = self.db.scalar(
                sa.select(Receipt).where(Receipt.payment_id == payment.id)
            )
            if event_id and not self.is_event_processed(event_id):
                self.record_processed_event("RAZORPAY", event_id, "payment.captured")
                self.db.commit()
            return True, "Payment already settled successfully.", existing_receipt

        # 3. Amount verification
        paid_amount_decimal = Decimal(amount_paise) / Decimal("100")
        expected_amount = Decimal(str(payment.amount))
        if paid_amount_decimal != expected_amount:
            return (
                False,
                f"Amount mismatch: received {paid_amount_decimal}, expected {expected_amount}.",
                None,
            )

        # 4. Lock the invoice row atomically
        invoice = self.db.scalar(
            sa.select(Invoice).where(Invoice.id == payment.invoice_id).with_for_update()
        )
        if not invoice:
            return False, f"Invoice {payment.invoice_id} associated with payment not found.", None

        # Verify cross-property association integrity
        if invoice.property_id != payment.property_id:
            return False, "Property mismatch between invoice and payment request.", None

        if invoice.status == "CANCELLED":
            return False, "Cannot settle payment against a cancelled invoice.", None

        # Check existing payment balance
        invoice_total = Decimal(str(invoice.amount))
        current_paid = Decimal(str(invoice.paid_amount))
        if invoice.status == "PAID" or current_paid >= invoice_total:
            return False, "Invoice has already been fully settled.", None

        if current_paid + paid_amount_decimal > invoice_total:
            return False, f"Settlement amount {paid_amount_decimal} exceeds invoice outstanding balance {invoice_total - current_paid}.", None

        # Check for provider payment ID collision with a different payment record
        existing_provider_pay = self.db.scalar(
            sa.select(Payment).where(
                Payment.gateway_payment_id == provider_payment_id,
                Payment.id != payment.id,
            )
        )
        if existing_provider_pay:
            return False, f"Provider payment ID '{provider_payment_id}' has already been credited to payment {existing_provider_pay.payment_number}.", None

        # 5. Handle settlement updates within transaction
        now = datetime.now(timezone.utc)
        payment.status = "SUCCESS"
        payment.gateway_payment_id = provider_payment_id
        payment.paid_at = now
        if payment_method:
            payment.payment_mode = payment_method.upper()

        # Recalculate invoice amounts & status
        invoice_total = Decimal(str(invoice.amount))
        current_paid = Decimal(str(invoice.paid_amount))
        new_paid = current_paid + paid_amount_decimal
        invoice.paid_amount = new_paid

        if new_paid >= invoice_total:
            invoice.status = "PAID"
        elif new_paid > Decimal("0.00"):
            invoice.status = "PARTIALLY_PAID"

        # 6. Issue exactly one Receipt
        receipt_number = f"RCT-{now.strftime('%Y%m%d')}-{uuid.uuid4().hex[:8].upper()}"
        receipt = Receipt(
            payment_id=payment.id,
            invoice_id=invoice.id,
            receipt_number=receipt_number,
            amount=paid_amount_decimal,
            issued_at=now,
            whatsapp_status="PENDING",
            whatsapp_attempts=0,
        )
        self.db.add(receipt)

        # 7. Record the event ID to guarantee idempotency across duplicate webhooks
        if event_id:
            self.record_processed_event("RAZORPAY", event_id, "payment.captured")

        self.db.commit()
        self.db.refresh(receipt)
        self.db.refresh(payment)
        self.db.refresh(invoice)

        return True, "Payment and invoice settled successfully.", receipt

    def handle_payment_failed(
        self,
        provider_order_id: str,
        provider_payment_id: Optional[str] = None,
        event_id: Optional[str] = None,
        reason: Optional[str] = None,
    ) -> Tuple[bool, str]:
        """Handles payment.failed event from provider without overwriting prior success."""
        if event_id and self.is_event_processed(event_id):
            return True, "Webhook event already processed."

        payment = self.db.scalar(
            sa.select(Payment)
            .where(Payment.gateway_order_id == provider_order_id)
            .with_for_update()
        )
        if not payment:
            return False, f"No payment request found for gateway order {provider_order_id}."

        # Never downgrade a previously successful payment to FAILED!
        if payment.status == "SUCCESS":
            if event_id:
                self.record_processed_event("RAZORPAY", event_id, "payment.failed")
                self.db.commit()
            return True, "Ignored failure event for already succeeded payment."

        # Mark payment as FAILED
        payment.status = "FAILED"
        if provider_payment_id:
            payment.gateway_payment_id = provider_payment_id

        if event_id:
            self.record_processed_event("RAZORPAY", event_id, "payment.failed")

        self.db.commit()
        return True, "Payment marked as failed."
