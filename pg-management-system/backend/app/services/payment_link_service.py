import hashlib
import logging
import secrets
import uuid
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from typing import Optional, Tuple

import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.exceptions import ConflictError, NotFoundError, PermissionDeniedError
from app.integrations.payment_gateway import RazorpayGateway
from app.integrations.whatsapp import WhatsAppCloudProvider
from app.models.invoice import Invoice
from app.models.payment import Payment
from app.models.payment_link import PaymentLink
from app.models.property import Property
from app.models.resident import Resident
from app.models.room import Room
from app.models.user import User

logger = logging.getLogger(__name__)


def hash_token(token: str) -> str:
    """Computes SHA-256 hex digest of the raw token."""
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


class PaymentLinkService:
    """Service for generating, querying, and distributing secure payment links."""

    def __init__(self, db: Session):
        self.db = db

    def create_payment_link(
        self,
        invoice_id: uuid.UUID,
        amount: Decimal,
        idempotency_key: str,
        current_user: User,
        send_whatsapp: bool = False,
    ) -> Tuple[PaymentLink, str, str]:
        """Creates or reuses a payment request, generates an unguessable payment link token,

        and optionally delivers the link via WhatsApp.
        Returns: (payment_link, raw_token, public_url).
        """
        # 1. Lock and validate invoice
        invoice = self.db.scalar(
            sa.select(Invoice).where(Invoice.id == invoice_id).with_for_update()
        )
        if not invoice:
            raise NotFoundError("Invoice not found.")

        resident = self.db.get(Resident, invoice.resident_id)
        if not resident or resident.property_id != invoice.property_id:
            raise NotFoundError("Invoice resident relationship is invalid.")

        # Property authorization: Super admins have company access, staff need assignment, residents own only
        if current_user.role.name == "RESIDENT":
            if resident.user_id != current_user.id:
                raise PermissionDeniedError("Residents can only generate payment links for their own invoices.")
        elif current_user.role.name != "SUPER_ADMIN":
            from app.dependencies import verify_property_access
            verify_property_access(invoice.property_id, current_user, self.db)

        if invoice.status in ("CANCELLED", "PAID"):
            raise ConflictError("Invoice is not eligible for payment.")

        # 2. Check for existing payment request with this idempotency key
        existing_payment = self.db.scalar(
            sa.select(Payment).where(
                Payment.invoice_id == invoice.id,
                Payment.idempotency_key == idempotency_key,
            )
        )
        now = datetime.now(timezone.utc)

        if existing_payment:
            if Decimal(str(existing_payment.amount)) != amount:
                raise ConflictError("Idempotency key was already used with a different amount.")
            payment = existing_payment

            # Check if an active unrevoked payment link already exists for this payment
            existing_link = self.db.scalar(
                sa.select(PaymentLink).where(
                    PaymentLink.payment_id == payment.id,
                    PaymentLink.is_revoked == False,
                    PaymentLink.expires_at > now,
                )
            )
            if existing_link:
                # Reuse existing link without re-sending duplicate charge or creating duplicate token
                # For security we issue a fresh access token for the user session if needed,
                # or maintain existing link. Generate fresh raw token and update token hash safely.
                raw_token = secrets.token_urlsafe(32)
                existing_link.token_hash = hash_token(raw_token)
                self.db.commit()
                self.db.refresh(existing_link)
                base_url = settings.PAYMENT_LINK_BASE_URL.rstrip("/")
                link_url = f"{base_url}/{raw_token}"
                return existing_link, raw_token, link_url
        else:
            # 3. Balance verification
            reserved = self.db.scalar(
                sa.select(sa.func.coalesce(sa.func.sum(Payment.amount), 0)).where(
                    Payment.invoice_id == invoice.id,
                    Payment.status == "PENDING",
                    Payment.reservation_expires_at > now,
                )
            )
            outstanding = (
                Decimal(str(invoice.amount))
                - Decimal(str(invoice.paid_amount))
                - Decimal(str(reserved))
            )
            if amount > outstanding:
                raise ConflictError("Requested amount exceeds the invoice outstanding balance.")

            # 4. Gateway order creation
            if not settings.RAZORPAY_KEY_ID or not settings.RAZORPAY_KEY_SECRET:
                from fastapi import HTTPException
                raise HTTPException(status_code=503, detail="Online payment gateway is not configured.")

            gateway = RazorpayGateway(settings.RAZORPAY_KEY_ID, settings.RAZORPAY_KEY_SECRET)
            payment = Payment(
                property_id=invoice.property_id,
                invoice_id=invoice.id,
                resident_id=resident.id,
                payment_number=f"PAY-{uuid.uuid4().hex[:20].upper()}",
                amount=amount,
                payment_mode="UPI",
                status="PENDING",
                idempotency_key=idempotency_key,
                reservation_expires_at=now + timedelta(minutes=15),
            )
            try:
                order = gateway.create_order(
                    int(amount * 100),
                    "INR",
                    payment.payment_number,
                    {"invoice_id": str(invoice.id), "payment_number": payment.payment_number},
                )
            except Exception as exc:
                from fastapi import HTTPException
                raise HTTPException(status_code=502, detail="Unable to create payment order.") from exc

            payment.gateway_order_id = order["order_id"]
            self.db.add(payment)
            self.db.flush()

        # 5. Generate secure payment link token
        raw_token = secrets.token_urlsafe(32)
        token_digest = hash_token(raw_token)
        expires_at = payment.reservation_expires_at or (now + timedelta(minutes=15))

        payment_link = PaymentLink(
            payment_id=payment.id,
            invoice_id=invoice.id,
            resident_id=resident.id,
            token_hash=token_digest,
            expires_at=expires_at,
            is_revoked=False,
            whatsapp_sent=False,
        )
        self.db.add(payment_link)
        self.db.commit()
        self.db.refresh(payment_link)

        base_url = settings.PAYMENT_LINK_BASE_URL.rstrip("/")
        link_url = f"{base_url}/{raw_token}"

        # 6. Deliver via WhatsApp if requested
        if send_whatsapp:
            try:
                self.dispatch_whatsapp_payment_request(payment_link, link_url)
            except Exception:
                self.db.delete(payment_link)
                self.db.commit()
                raise

        return payment_link, raw_token, link_url

    def get_payment_link_details(self, raw_token: str) -> dict:
        """Looks up the payment link by hashed token.

        Exposes only minimal, safe resident checkout data (no secrets, no database IDs).
        """
        token_digest = hash_token(raw_token)
        link = self.db.scalar(
            sa.select(PaymentLink).where(PaymentLink.token_hash == token_digest)
        )
        if not link:
            raise NotFoundError("Payment link not found or invalid.")

        now = datetime.now(timezone.utc)
        if link.is_revoked:
            raise ConflictError("Payment link has been revoked.")

        # Ensure tz-aware comparison
        link_expires_at = link.expires_at
        if link_expires_at.tzinfo is None:
            link_expires_at = link_expires_at.replace(tzinfo=timezone.utc)

        if link_expires_at <= now:
            raise ConflictError("Payment link has expired.")

        payment = self.db.get(Payment, link.payment_id)
        if not payment or payment.status != "PENDING":
            if payment and payment.status in ("SUCCESS", "PAID"):
                raise ConflictError("Invoice payment has already been completed.")
            raise ConflictError("Payment is no longer pending.")

        invoice = self.db.get(Invoice, link.invoice_id)
        if not invoice or invoice.status in ("PAID", "CANCELLED"):
            raise ConflictError("Invoice is no longer pending payment.")

        resident = self.db.get(Resident, link.resident_id)
        prop = self.db.get(Property, invoice.property_id) if invoice else None
        room = self.db.get(Room, resident.room_id) if resident and resident.room_id else None

        return {
            "property_name": prop.name if prop else "",
            "room_number": room.room_number if room else "N/A",
            "invoice_number": invoice.invoice_number,
            "billing_month": invoice.billing_month,
            "amount": Decimal(str(payment.amount)),
            "amount_paise": int(Decimal(str(payment.amount)) * 100),
            "currency": "INR",
            "gateway_order_id": payment.gateway_order_id,
            "key_id": settings.RAZORPAY_KEY_ID,  # Public client key for Razorpay checkout modal
            "expires_at": link.expires_at,
        }

    def dispatch_whatsapp_payment_request(self, payment_link: PaymentLink, link_url: str) -> bool:
        """Sends property name, room number, due amount, and payment link via WhatsApp Cloud API."""
        invoice = self.db.get(Invoice, payment_link.invoice_id)
        resident = self.db.get(Resident, payment_link.resident_id)
        if not resident or not invoice:
            raise NotFoundError("Resident or invoice associated with payment link was not found.")

        user = self.db.get(User, resident.user_id)
        if not user or not user.phone:
            raise ConflictError("Resident user phone number is missing.")

        prop = self.db.get(Property, invoice.property_id)
        room = self.db.get(Room, resident.room_id) if resident.room_id else None
        payment = self.db.get(Payment, payment_link.payment_id)

        property_name = prop.name if prop else "PG"
        room_number = room.room_number if room else "N/A"
        amount_str = f"Rs. {payment.amount:.2f}"

        # Initialize WhatsApp Provider
        try:
            provider = WhatsAppCloudProvider(
                phone_number_id=settings.WHATSAPP_PHONE_NUMBER_ID,
                access_token=settings.WHATSAPP_ACCESS_TOKEN,
            )
        except ValueError as exc:
            from fastapi import HTTPException, status
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="WhatsApp service is not configured.",
            ) from exc

        template = settings.WHATSAPP_PAYMENT_TEMPLATE
        parameters = [property_name, room_number, amount_str, link_url]

        try:
            msg_id = provider.send_template(user.phone, template, parameters)
            payment_link.whatsapp_sent = True
            payment_link.whatsapp_message_id = msg_id
            payment_link.whatsapp_last_error = None
            self.db.commit()
            return True
        except Exception as exc:
            logger.error(f"WhatsApp delivery failed for link {payment_link.id}: {exc}")
            payment_link.whatsapp_last_error = str(exc)
            self.db.commit()
            raise
