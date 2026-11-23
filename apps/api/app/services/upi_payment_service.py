import json
import logging
import re
import uuid
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from typing import Any, Dict, Optional, Tuple, override
from urllib.parse import quote, urlencode

from fastapi import HTTPException, status
import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.exceptions import BadRequestError, ConflictError, NotFoundError, PermissionDeniedError
from app.models.invoice import Invoice
from app.models.payment import Payment
from app.models.property import Property
from app.models.receipt import Receipt
from app.models.resident import Resident

logger = logging.getLogger(__name__)

# Standard Android Package Identifiers for Direct Intent Routing
GPAY_PACKAGE_NAME = "com.google.android.apps.nbu.paisa.user"
PHONEPE_PACKAGE_NAME = "com.phonepe.app"
PAYTM_PACKAGE_NAME = "net.one97.paytm"
BHIM_PACKAGE_NAME = "in.org.npci.upiapp"


def parse_upi_client_metadata(gateway_signature: Optional[str]) -> Dict[str, Optional[str]]:
    """Safely extracts stored client-reported UPI telemetry without touching verified UTR."""
    if not gateway_signature:
        return {}
    raw = gateway_signature.strip()
    if raw.startswith("{"):
        try:
            decoded = json.loads(raw)
            if isinstance(decoded, dict):
                return {
                    "client_upi_txn_id": decoded.get("utxn"),
                    "app_package": decoded.get("app"),
                    "response_code": decoded.get("code"),
                    "client_status": decoded.get("st"),
                }
        except Exception:
            pass
    return {}


def compute_reconciliation_status(payment_status: str) -> str:
    st = (payment_status or "").upper()
    if st in ("PAID", "SUCCESS"):
        return "VERIFIED"
    if st in ("PENDING_VERIFICATION", "PENDING"):
        return "PENDING_RECONCILIATION"
    if st == "FAILED":
        return "FAILED"
    if st == "CANCELLED":
        return "CANCELLED"
    if st == "EXPIRED":
        return "EXPIRED"
    return st or "UNKNOWN"


def redact_vpa(vpa: Optional[str]) -> str:
    """Masks VPA local-part for safe diagnostic logging without exposing full UPI ID."""
    clean = (vpa or "").strip()
    if "@" not in clean:
        return "***"
    local, domain = clean.split("@", 1)
    if len(local) <= 3:
        return f"{local[:1]}***@{domain}"
    return f"{local[:2]}***{local[-2:]}@{domain}"


def sanitize_upi_note(text: str, max_len: int = 50) -> str:
    """Produces an NPCI-safe transaction note (strictly alphanumeric and spaces, <= 50 chars)."""
    cleaned = re.sub(r"[^A-Za-z0-9 ]", " ", (text or "").strip())
    cleaned = re.sub(r"\s+", " ", cleaned).strip()
    if not cleaned:
        return "Rent Payment"
    return cleaned[:max_len].strip()


def classify_upi_error_category(
    reported_status: str,
    response_code: Optional[str] = None,
    raw_response: Optional[str] = None,
) -> str:
    st = (reported_status or "UNKNOWN").strip().upper()
    code = (response_code or "").strip().upper()
    raw = (raw_response or "").lower()

    if st in ("PAID", "SUCCESS") and not raw and not code:
        return "PENDING_TRANSACTION"
    if st == "CANCELLED":
        return "USER_CANCELLED"
    if st == "NETWORK_ERROR" or "network" in raw:
        return "NETWORK_FAILURE"
    if "security reasons" in raw or "security policy" in raw or "risk" in raw or code in ("LAUNCH_ERROR", "SECURITY_DECLINED"):
        return "SECURITY_REJECTION"
    if code in ("Z9", "ZM", "ZA", "Z5", "U30", "U69", "XH", "XU", "B3", "LIMIT_EXCEEDED") or "limit" in raw:
        return "BANK_LIMIT_REJECTION"
    if st in ("FAILURE", "FAILED"):
        return "BANK_TRANSACTION_REJECTION"
    if st in ("SUCCESS", "SUBMITTED", "PENDING"):
        return "PENDING_TRANSACTION"
    return "UNKNOWN_ERROR"


def build_upi_uri(
    payee_vpa: str,
    payee_name: str,
    amount: Decimal,
    transaction_ref: str,
    description: str,
    merchant_code: Optional[str] = None,
) -> str:
    """
    Builds a standard, RFC-3986 URL-encoded (%20, never '+') NPCI UPI Deep Link URI.
    Format: upi://pay?pa=...&pn=...&am=...&cu=INR&tr=...&tn=...
    Enforces strict NPCI alphanumeric mandate for transaction_ref (no hyphens/symbols).
    """
    safe_note = sanitize_upi_note(description)
    clean_tr = re.sub(r"[^A-Za-z0-9]", "", transaction_ref.strip())[:35]
    if not clean_tr:
        clean_tr = f"TXN{uuid.uuid4().hex[:12].upper()}"
    clean_pn = re.sub(r"[']", "", payee_name.strip())
    params = [
        ("pa", payee_vpa.strip()),
        ("pn", clean_pn),
        ("am", f"{amount:.2f}"),
        ("cu", "INR"),
        ("tr", clean_tr),
        ("tn", safe_note),
    ]
    if merchant_code and re.fullmatch(r"\d{4}", merchant_code.strip()):
        params.append(("mc", merchant_code.strip()))
    params.append(("mode", "04"))

    query_str = urlencode(params, quote_via=quote)
    return f"upi://pay?{query_str}"


class UpiVerificationResult:
    """Standard result object returned by UPI verification providers."""

    def __init__(
        self,
        is_settled: bool,
        status: str,
        message: str,
        bank_reference: Optional[str] = None,
        required_integration: Optional[str] = None,
        raw_response: Optional[Dict[str, Any]] = None,
    ):
        self.is_settled = is_settled
        self.status = status
        self.message = message
        self.bank_reference = bank_reference
        self.required_integration = required_integration
        self.raw_response = raw_response or {}


class BaseUpiVerificationProvider:
    """
    Abstract verification provider interface for future authoritative direct bank/UPI merchant integrations.
    Allows plugging in direct bank APIs (e.g., ICICI Eazypay, HDFC SmartHub, NPCI)
    without altering the UPI Intent generation or payment endpoints.
    """

    def verify_payment(
        self, payment: Payment, client_data: Optional[Dict[str, Any]] = None
    ) -> UpiVerificationResult:
        raise NotImplementedError


class DefaultPendingVerificationProvider(BaseUpiVerificationProvider):
    """
    Default verification provider when no direct bank merchant status API is configured.
    Strict security rule: Fails closed. Never marks transactions PAID based on untrusted
    client claims, user screenshots, or client-supplied references.
    """

    @override
    def verify_payment(
        self, payment: Payment, client_data: Optional[Dict[str, Any]] = None
    ) -> UpiVerificationResult:
        return UpiVerificationResult(
            is_settled=False,
            status="PENDING_VERIFICATION",
            message=(
                "Payment remains in PENDING_VERIFICATION. Automatic confirmation requires an "
                "authorized Bank/UPI provider transaction-status integration."
            ),
            required_integration=(
                "Bank Direct UPI Merchant API / Webhook (e.g. ICICI UPI Eazypay, HDFC SmartHub, "
                "or NPCI Merchant Callback)"
            ),
        )


class UpiPaymentService:
    """Service handling direct UPI rent payment initiation, status, and authoritative settlement."""

    def __init__(self, db: Session):
        self.db = db

    def initiate_payment(
        self,
        resident: Resident,
        invoice_id: uuid.UUID,
        idempotency_key: Optional[str] = None,
        app_name: Optional[str] = None,
        package_name: Optional[str] = None,
    ) -> Tuple[Payment, Dict[str, Any]]:
        """
        Initiates a direct UPI rent payment attempt.
        Validates invoice ownership and eligibility, calculates exact payable balance from DB,
        and generates compliant UPI / Google Pay / PhonePe deep link intents.
        """
        # 1. Determine Payee: Bank Merchant VPA (if onboarded) vs Personal VPA
        merchant_code = settings.UPI_MERCHANT_CODE.strip() if getattr(settings, "UPI_MERCHANT_CODE", None) else None
        if getattr(settings, "UPI_MERCHANT_VPA", None) and settings.UPI_MERCHANT_VPA.strip():
            payee_vpa = settings.UPI_MERCHANT_VPA.strip()
            payee_name = (getattr(settings, "UPI_MERCHANT_NAME", None) or settings.UPI_PAYEE_NAME or "SMART GROUP PG'S").strip()
            is_merchant = True
        else:
            payee_vpa = settings.UPI_PAYEE_VPA.strip() if settings.UPI_PAYEE_VPA else ""
            if not payee_vpa:
                logger.error("[UpiPaymentService] UPI_PAYEE_VPA is not configured in settings.")
                raise HTTPException(
                    status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                    detail="PG business UPI ID (UPI_PAYEE_VPA) is not configured. Please contact the PG management.",
                )
            payee_name = settings.UPI_PAYEE_NAME.strip() if settings.UPI_PAYEE_NAME else "SMART GROUP PG'S"
            is_merchant = bool(merchant_code)

        # 2. Lock invoice row and validate ownership
        invoice = self.db.scalar(
            sa.select(Invoice).where(Invoice.id == invoice_id).with_for_update()
        )
        if not invoice:
            raise NotFoundError("Invoice not found.")

        if invoice.resident_id != resident.id:
            raise PermissionDeniedError("Residents can only pay their own invoices.")

        if invoice.property_id != resident.property_id:
            raise PermissionDeniedError("Invoice does not belong to resident's allocated property.")

        if invoice.status in ("PAID", "CANCELLED"):
            raise ConflictError(f"Invoice is not eligible for payment (current status: '{invoice.status}').")

        # 3. Calculate exact payable balance from DB (Never trust client-submitted amount)
        invoice_total = Decimal(str(invoice.amount))
        already_paid = Decimal(str(invoice.paid_amount))
        outstanding = invoice_total - already_paid

        if outstanding <= Decimal("0.00"):
            raise ConflictError("Invoice has no outstanding balance.")

        now = datetime.now(timezone.utc)

        # 4. Check idempotency: reuse existing payment if same idempotency key provided
        if idempotency_key:
            existing = self.db.scalar(
                sa.select(Payment).where(
                    Payment.invoice_id == invoice.id,
                    Payment.idempotency_key == idempotency_key,
                )
            )
            if existing:
                if existing.status not in ("FAILED", "CANCELLED"):
                    # Rebuild UPI URI details for existing active payment attempt
                    txn_ref = existing.gateway_order_id or f"TXN{existing.id.hex[:12].upper()}"
                    prop = self.db.get(Property, invoice.property_id)
                    prop_name = prop.name if prop else payee_name
                    desc = sanitize_upi_note(f"Rent payment {invoice.billing_month} - {prop_name}")
                    upi_uri = build_upi_uri(
                        payee_vpa=payee_vpa,
                        payee_name=payee_name,
                        amount=Decimal(str(existing.amount)),
                        transaction_ref=txn_ref,
                        description=desc,
                        merchant_code=merchant_code,
                    )
                    return existing, self._build_intent_payload(
                        payment=existing,
                        invoice=invoice,
                        transaction_ref=txn_ref,
                        payee_vpa=payee_vpa,
                        payee_name=payee_name,
                        description=desc,
                        upi_uri=upi_uri,
                        is_merchant_configured=is_merchant,
                        merchant_code=merchant_code,
                    )

        # 5. Generate unique transaction reference & payment number
        transaction_ref = f"TXN{uuid.uuid4().hex[:12].upper()}"
        payment_number = f"PAY-UPI-{uuid.uuid4().hex[:16].upper()}"

        initial_sig = None
        if package_name or app_name:
            sig_obj = {k: v for k, v in {"app": (package_name or app_name or "")[:80], "st": "INITIATED"}.items() if v}
            initial_sig = json.dumps(sig_obj)[:255]

        payment = Payment(
            property_id=invoice.property_id,
            invoice_id=invoice.id,
            resident_id=resident.id,
            payment_number=payment_number,
            amount=outstanding,
            payment_mode="UPI",
            gateway_order_id=transaction_ref,  # UPI transaction reference
            gateway_signature=initial_sig,
            status="PENDING",
            idempotency_key=idempotency_key or f"upi_{transaction_ref}",
            reservation_expires_at=now + timedelta(minutes=30),
        )
        self.db.add(payment)
        self.db.commit()
        self.db.refresh(payment)

        prop = self.db.get(Property, invoice.property_id)
        prop_name = prop.name if prop else payee_name
        description = sanitize_upi_note(f"Rent payment {invoice.billing_month} - {prop_name}")

        upi_uri = build_upi_uri(
            payee_vpa=payee_vpa,
            payee_name=payee_name,
            amount=outstanding,
            transaction_ref=transaction_ref,
            description=description,
            merchant_code=merchant_code,
        )

        logger.info(
            "[UpiPaymentService] Initiated UPI intent payment_ref=%s app=%s vpa=%s amount=%.2f merchant=%s",
            transaction_ref,
            package_name or app_name or "unspecified",
            redact_vpa(payee_vpa),
            float(outstanding),
            is_merchant,
        )

        return payment, self._build_intent_payload(
            payment=payment,
            invoice=invoice,
            transaction_ref=transaction_ref,
            payee_vpa=payee_vpa,
            payee_name=payee_name,
            description=description,
            upi_uri=upi_uri,
            is_merchant_configured=is_merchant,
            merchant_code=merchant_code,
        )

    def _build_intent_payload(
        self,
        payment: Payment,
        invoice: Invoice,
        transaction_ref: str,
        payee_vpa: str,
        payee_name: str,
        description: str,
        upi_uri: str,
        is_merchant_configured: bool = False,
        merchant_code: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Builds app-specific intent URLs and metadata while keeping base upi_uri clean."""
        gpay_uri = f"{upi_uri}&package={GPAY_PACKAGE_NAME}"
        phonepe_uri = f"{upi_uri}&package={PHONEPE_PACKAGE_NAME}"
        paytm_uri = f"{upi_uri}&package={PAYTM_PACKAGE_NAME}"
        bhim_uri = f"{upi_uri}&package={BHIM_PACKAGE_NAME}"

        return {
            "payment_id": payment.id,
            "payment_number": payment.payment_number,
            "transaction_ref": transaction_ref,
            "invoice_id": invoice.id,
            "amount": float(payment.amount),
            "currency": "INR",
            "payee_vpa": payee_vpa,
            "payee_name": payee_name,
            "description": description,
            "upi_uri": upi_uri,
            "google_pay_uri": gpay_uri,
            "phonepe_uri": phonepe_uri,
            "apps": {
                "google_pay": {
                    "name": "Google Pay",
                    "package_name": GPAY_PACKAGE_NAME,
                    "intent_uri": gpay_uri,
                },
                "phonepe": {
                    "name": "PhonePe",
                    "package_name": PHONEPE_PACKAGE_NAME,
                    "intent_uri": phonepe_uri,
                },
                "paytm": {
                    "name": "Paytm",
                    "package_name": PAYTM_PACKAGE_NAME,
                    "intent_uri": paytm_uri,
                },
                "bhim": {
                    "name": "BHIM",
                    "package_name": BHIM_PACKAGE_NAME,
                    "intent_uri": bhim_uri,
                },
            },
            "status": payment.status,
            "created_at": payment.created_at,
            "is_merchant_configured": is_merchant_configured,
            "merchant_code": merchant_code,
            "bank_name": getattr(settings, "UPI_BANK_NAME", "Bank of Baroda"),
        }

    def record_app_return(self, payment_id: uuid.UUID, resident: Resident) -> Payment:
        """
        Called when resident returns from Google Pay or PhonePe to the resident app.
        Transitions PENDING -> PENDING_VERIFICATION.
        Strict rule: Returning from a UPI app must NEVER automatically mark payment as PAID.
        """
        payment = self.db.get(Payment, payment_id)
        if not payment:
            raise NotFoundError("Payment not found.")

        if payment.resident_id != resident.id:
            raise PermissionDeniedError("Access denied.")

        # If currently PENDING, update to PENDING_VERIFICATION
        if payment.status == "PENDING":
            payment.status = "PENDING_VERIFICATION"
            self.db.commit()
            self.db.refresh(payment)

            try:
                from app.services.notification_service import NotificationService
                notif = NotificationService(self.db).dispatch(
                    user_id=resident.user_id,
                    title="Payment Pending Verification",
                    body=f"Your UPI payment attempt of INR {payment.amount:.2f} has been received and is awaiting bank verification.",
                    channel="PUSH",
                )
                if notif:
                    self.db.commit()
            except Exception as notif_err:
                logger.warning(f"[UpiPaymentService] Failed to queue return notification: {notif_err}")

        return payment

    def cancel_payment(self, payment_id: uuid.UUID, resident: Resident) -> Payment:
        """
        Cancels an unverified payment attempt.
        Idempotent: if already cancelled, returns cleanly.
        Defensively handles notification failure so cancellation is never reported as failed.
        """
        payment = self.db.get(Payment, payment_id)
        if not payment:
            raise NotFoundError("Payment not found.")

        if payment.resident_id != resident.id:
            raise PermissionDeniedError("Access denied.")

        if payment.status in ("PAID", "SUCCESS"):
            raise ConflictError("Cannot cancel an already settled payment.")

        if payment.status == "CANCELLED":
            return payment

        payment.status = "CANCELLED"
        self.db.commit()
        self.db.refresh(payment)

        try:
            from app.services.notification_service import NotificationService
            notif = NotificationService(self.db).dispatch(
                user_id=resident.user_id,
                title="Payment Attempt Cancelled",
                body=f"Payment attempt {payment.payment_number} for INR {payment.amount:.2f} was cancelled.",
                channel="PUSH",
            )
            if notif:
                self.db.commit()
        except Exception as notif_err:
            logger.warning(f"[UpiPaymentService] Failed to queue cancel notification: {notif_err}")

        return payment

    def record_upi_response(
        self,
        payment_id: uuid.UUID,
        resident: Resident,
        status_str: str,
        txn_ref: Optional[str] = None,
        upi_txn_id: Optional[str] = None,
        approval_ref_no: Optional[str] = None,
        response_code: Optional[str] = None,
        raw_response: Optional[str] = None,
        app_package: Optional[str] = None,
    ) -> Payment:
        """
        Records Direct UPI Intent callback response from the mobile app.
        Strict security rule: NEVER marks a payment PAID or settles an invoice from
        client callback parameters alone. Client-claimed SUCCESS/SUBMITTED/PENDING
        remains PENDING_VERIFICATION until authoritative bank/admin reconciliation.
        """
        from app.services.audit_service import record_audit_log

        payment = self.db.scalar(
            sa.select(Payment).where(Payment.id == payment_id).with_for_update()
        )
        if not payment:
            raise NotFoundError("Payment not found.")

        if payment.resident_id != resident.id:
            raise PermissionDeniedError("Access denied.")

        if txn_ref and payment.gateway_order_id and txn_ref.strip() != payment.gateway_order_id:
            raise BadRequestError("Transaction reference mismatch.")

        clean_upi_txn_id = upi_txn_id.strip() if upi_txn_id and upi_txn_id.strip() else None
        if clean_upi_txn_id:
            duplicate_settled = self.db.scalar(
                sa.select(Payment).where(
                    Payment.gateway_payment_id == clean_upi_txn_id,
                    Payment.id != payment.id,
                )
            )
            if duplicate_settled:
                raise ConflictError(
                    f"UPI transaction ID '{clean_upi_txn_id}' is already settled on another payment."
                )

        normalized = (status_str or "UNKNOWN").strip().upper()

        # Never downgrade an already settled payment
        if payment.status not in ("PAID", "SUCCESS"):
            if normalized in ("FAILURE", "FAILED", "NETWORK_ERROR"):
                payment.status = "FAILED"
            elif normalized in ("CANCELLED", "CANCELED", "USER_CANCELLED"):
                payment.status = "CANCELLED"
            else:
                # SUCCESS, SUBMITTED, PENDING, UNKNOWN -> fail closed in PENDING_VERIFICATION
                payment.status = "PENDING_VERIFICATION"

            existing_meta = parse_upi_client_metadata(payment.gateway_signature)
            meta_payload = {
                "st": normalized[:24],
                "app": (app_package or existing_meta.get("app_package") or "")[:64],
                "code": (response_code or existing_meta.get("response_code") or "")[:24],
                "utxn": (clean_upi_txn_id or approval_ref_no or existing_meta.get("client_upi_txn_id") or "")[:80],
            }
            compact = json.dumps({k: v for k, v in meta_payload.items() if v}, separators=(",", ":"))
            payment.gateway_signature = compact[:255]

        self.db.commit()
        self.db.refresh(payment)

        error_category = classify_upi_error_category(normalized, response_code, raw_response)
        logger.info(
            "[UpiPaymentService] UPI response recorded ref=%s app=%s status=%s code=%s category=%s resulting=%s has_utxn=%s",
            payment.gateway_order_id,
            app_package or "unknown",
            normalized,
            response_code or "-",
            error_category,
            payment.status,
            bool(clean_upi_txn_id),
        )

        try:
            record_audit_log(
                db=self.db,
                action="UPI_INTENT_RESPONSE",
                resource_type="payment",
                user_id=resident.user_id,
                user_role="RESIDENT",
                property_id=payment.property_id,
                resource_id=str(payment.id),
                details={
                    "payment_number": payment.payment_number,
                    "transaction_ref": payment.gateway_order_id,
                    "reported_status": normalized,
                    "error_category": error_category,
                    "resulting_status": payment.status,
                    "upi_txn_id": clean_upi_txn_id,
                    "approval_ref_no": approval_ref_no,
                    "response_code": response_code,
                    "app_package": app_package,
                    "raw_response": (raw_response or "")[:500] if raw_response else None,
                },
            )
        except Exception as audit_err:
            logger.warning(f"[UpiPaymentService] Failed to write UPI response audit log: {audit_err}")

        return payment

    def get_payment_status(
        self, payment_id: uuid.UUID, resident_or_user_id: uuid.UUID, is_admin: bool = False
    ) -> Tuple[Payment, Optional[Receipt]]:
        """Authoritatively queries payment state and associated receipt."""
        payment = self.db.get(Payment, payment_id)
        if not payment:
            raise NotFoundError("Payment not found.")

        if not is_admin:
            resident = self.db.get(Resident, payment.resident_id)
            if not resident or resident.user_id != resident_or_user_id:
                raise PermissionDeniedError("Access denied.")

        receipt = self.db.scalar(
            sa.select(Receipt).where(Receipt.payment_id == payment.id)
        )
        return payment, receipt

    def verify_client_attempt(
        self,
        payment_id: uuid.UUID,
        resident: Resident,
        client_data: Optional[Dict[str, Any]] = None,
        provider: Optional[BaseUpiVerificationProvider] = None,
    ) -> Dict[str, Any]:
        """
        Handles client verification inquiries.
        Strict rule: Never trust client callbacks, screenshots, or resident-entered transaction IDs.
        Uses BaseUpiVerificationProvider interface. If real bank/UPI status API is not configured,
        fails closed, keeps payment in PENDING_VERIFICATION, and reports the required bank integration.
        """
        payment = self.db.get(Payment, payment_id)
        if not payment:
            raise NotFoundError("Payment not found.")

        if payment.resident_id != resident.id:
            raise PermissionDeniedError("Access denied.")

        # If already settled by bank reconciliation or admin:
        if payment.status in ("PAID", "SUCCESS"):
            return {
                "payment_id": payment.id,
                "status": payment.status,
                "is_verified": True,
                "message": "Payment has been verified and settled.",
                "required_integration": None,
            }

        # Transition to PENDING_VERIFICATION if still PENDING
        if payment.status == "PENDING":
            payment.status = "PENDING_VERIFICATION"
            self.db.commit()
            self.db.refresh(payment)

        # Delegate verification to modular provider interface
        verification_provider = provider or DefaultPendingVerificationProvider()
        result = verification_provider.verify_payment(payment, client_data)

        logger.info(
            f"[UpiPaymentService] Verification inquiry for payment {payment.payment_number}. "
            f"Result status: {result.status}, is_settled: {result.is_settled}."
        )

        return {
            "payment_id": payment.id,
            "status": result.status,
            "is_verified": result.is_settled,
            "message": result.message,
            "required_integration": result.required_integration,
        }

    def settle_trusted_payment(
        self,
        payment_id: uuid.UUID,
        bank_reference: str,
        event_id: Optional[str] = None,
        admin_user: Optional[Any] = None,
        notes: Optional[str] = None,
    ) -> Tuple[Payment, Optional[Receipt], bool]:
        """
        Atomically settles a trusted/verified UPI payment, updates invoice balance and status,
        and issues an immutable digital receipt.
        Guarantees idempotency and prevents duplicate receipts.
        """
        from app.services.audit_service import record_audit_log

        # 1. Lock payment row
        payment = self.db.scalar(
            sa.select(Payment).where(Payment.id == payment_id).with_for_update()
        )
        if not payment:
            raise NotFoundError("Payment record not found.")

        # 2. Idempotency check: if already settled, return existing receipt without duplicate settlement
        if payment.status in ("PAID", "SUCCESS"):
            existing_receipt = self.db.scalar(
                sa.select(Receipt).where(Receipt.payment_id == payment.id)
            )
            return payment, existing_receipt, False

        # 3. Lock invoice row
        invoice = self.db.scalar(
            sa.select(Invoice).where(Invoice.id == payment.invoice_id).with_for_update()
        )
        if not invoice:
            raise NotFoundError(f"Invoice {payment.invoice_id} associated with payment not found.")

        # Property integrity check
        if invoice.property_id != payment.property_id:
            raise ConflictError("Property mismatch between invoice and payment request.")

        # Status integrity check
        if invoice.status == "CANCELLED":
            raise ConflictError("Cannot settle payment against a cancelled invoice.")

        # Overpayment and double-settlement protection
        current_paid = Decimal(str(invoice.paid_amount))
        invoice_total = Decimal(str(invoice.amount))
        if invoice.status == "PAID" or current_paid >= invoice_total:
            raise ConflictError("Invoice has already been fully settled.")

        paid_amount_decimal = Decimal(str(payment.amount))
        if current_paid + paid_amount_decimal > invoice_total:
            raise ConflictError(
                f"Settlement amount {paid_amount_decimal} exceeds invoice outstanding balance {invoice_total - current_paid}."
            )

        # Enforce uniqueness of bank reference / UTR across all payments
        clean_bank_ref = bank_reference.strip()
        existing_bank_ref = self.db.scalar(
            sa.select(Payment).where(
                Payment.gateway_payment_id == clean_bank_ref,
                Payment.id != payment.id,
            )
        )
        if existing_bank_ref:
            raise ConflictError(
                f"Bank reference '{clean_bank_ref}' has already been credited to payment {existing_bank_ref.payment_number}."
            )

        # 4. Settle payment
        now = datetime.now(timezone.utc)
        payment.status = "PAID"
        payment.gateway_payment_id = clean_bank_ref
        payment.paid_at = now

        # 5. Update invoice paid amount and status
        new_paid = current_paid + paid_amount_decimal
        invoice.paid_amount = float(new_paid)

        invoice_total = Decimal(str(invoice.amount))
        if new_paid >= invoice_total:
            invoice.status = "PAID"
        elif new_paid > Decimal("0.00"):
            invoice.status = "PARTIALLY_PAID"

        # 6. Issue exactly one Receipt (preventing duplicates)
        existing_receipt = self.db.scalar(
            sa.select(Receipt).where(Receipt.payment_id == payment.id)
        )
        if not existing_receipt:
            receipt_number = f"RCT-UPI-{now.strftime('%Y%m%d')}-{uuid.uuid4().hex[:8].upper()}"
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
        else:
            receipt = existing_receipt

        self.db.commit()
        self.db.refresh(payment)
        self.db.refresh(invoice)
        if receipt:
            self.db.refresh(receipt)

        # 7. Record authoritative audit log
        try:
            record_audit_log(
                db=self.db,
                action="UPI_PAYMENT_SETTLED",
                resource_type="payment",
                user_id=admin_user.id if admin_user else None,
                user_email=admin_user.email if admin_user else "bank_system@webhook",
                user_role=admin_user.role.name if admin_user else "SYSTEM",
                property_id=payment.property_id,
                resource_id=str(payment.id),
                details={
                    "bank_reference": bank_reference,
                    "amount": float(paid_amount_decimal),
                    "invoice_id": str(invoice.id),
                    "invoice_status": invoice.status,
                    "receipt_number": receipt.receipt_number if receipt else None,
                    **({"notes": notes} if notes else {}),
                },
            )
        except Exception as audit_err:
            logger.warning(f"[UpiPaymentService] Failed to write audit log for settlement: {audit_err}")

        # 8. Record in-app notification for resident
        try:
            resident = self.db.get(Resident, payment.resident_id)
            if resident:
                from app.services.notification_service import NotificationService
                receipt_str = f" Receipt: {receipt.receipt_number}." if receipt else ""
                notif = NotificationService(self.db).dispatch(
                    user_id=resident.user_id,
                    title="Rent Payment Confirmed",
                    body=f"Your payment of INR {paid_amount_decimal:.2f} for invoice {invoice.invoice_number} has been verified and settled.{receipt_str}",
                    channel="PUSH",
                )
                if notif:
                    self.db.commit()
        except Exception as notif_err:
            logger.warning(f"[UpiPaymentService] Failed to queue settlement notification: {notif_err}")

        return payment, receipt, True

    def reject_pending_payment(
        self,
        payment_id: uuid.UUID,
        admin_user: Any,
        notes: Optional[str] = None,
    ) -> Payment:
        """Marks an unverified/pending UPI payment as FAILED after admin statement review."""
        from app.services.audit_service import record_audit_log

        payment = self.db.scalar(
            sa.select(Payment).where(Payment.id == payment_id).with_for_update()
        )
        if not payment:
            raise NotFoundError("Payment record not found.")

        if payment.status in ("PAID", "SUCCESS"):
            raise ConflictError("Cannot reject an already settled payment.")

        payment.status = "FAILED"
        self.db.commit()
        self.db.refresh(payment)

        try:
            record_audit_log(
                db=self.db,
                action="UPI_PAYMENT_REJECTED",
                resource_type="payment",
                user_id=admin_user.id if admin_user else None,
                user_email=admin_user.email if admin_user else None,
                user_role=admin_user.role.name if admin_user and getattr(admin_user, "role", None) else None,
                property_id=payment.property_id,
                resource_id=str(payment.id),
                details={
                    "payment_number": payment.payment_number,
                    "transaction_ref": payment.gateway_order_id,
                    "amount": float(payment.amount),
                    "notes": notes or "Bank credit not found during reconciliation.",
                },
            )
        except Exception as audit_err:
            logger.warning(f"[UpiPaymentService] Failed to write rejection audit log: {audit_err}")

        return payment
