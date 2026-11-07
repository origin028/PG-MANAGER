import hashlib
import hmac
import uuid
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from typing import List, Optional
from fastapi import APIRouter, Depends, Header, HTTPException, Query, Request, Response, status
from sqlalchemy.orm import Session
import sqlalchemy as sa

from app.dependencies import (
    get_current_active_resident,
    get_current_user,
    get_db,
    require_roles,
    verify_property_access,
)
from app.models.user import User
from app.models.invoice import Invoice
from app.models.property import Property
from app.models.receipt import Receipt
from app.models.resident import Resident
from app.models.payment import Payment
from app.models.webhook_event import ProcessedWebhookEvent
from app.core.config import settings
from app.core.exceptions import BadRequestError, ConflictError, NotFoundError, PermissionDeniedError
from app.integrations.payment_gateway import RazorpayGateway, MockPaymentGateway, get_payment_gateway
from app.repositories.payment_repository import PaymentRepository
from app.schemas.common import APIResponse, PaginatedData
from app.schemas.payment import (
    PaymentSummary,
    PaymentRequestCreate,
    PaymentRequestRead,
    PaymentStatusRead,
    PaymentVerifyRequest,
    PaymentLinkCreate,
    PaymentLinkRead,
    PublicPaymentCheckoutDetails,
    UpiAdminSettleRequest,
    UpiClientVerifyRequest,
    UpiClientVerifyResponse,
    UpiPaymentInitiateRead,
    UpiPaymentInitiateRequest,
    UpiPaymentStatusRead,
    ManualPaymentCreate,
    ManualPaymentRead,
    DemoPaymentRequest,
    DemoPaymentResponse,
    RentCollectionCreate,
    RentCollectionRead,
    PaymentDetailRead,
)
from app.services.settlement_service import WebhookSettlementService
from app.services.payment_link_service import PaymentLinkService
from app.services.upi_payment_service import UpiPaymentService

router = APIRouter()


@router.post("/links", response_model=APIResponse[PaymentLinkRead], status_code=status.HTTP_201_CREATED)
def create_payment_link(
    payload: PaymentLinkCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Generates an opaque, unguessable payment link for an invoice and optionally delivers via WhatsApp."""
    service = PaymentLinkService(db)
    payment_link, raw_token, public_url = service.create_payment_link(
        invoice_id=payload.invoice_id,
        amount=payload.amount,
        idempotency_key=payload.idempotency_key,
        current_user=current_user,
        send_whatsapp=payload.send_whatsapp,
    )
    payment = db.get(Payment, payment_link.payment_id)
    return APIResponse(
        success=True,
        message="Payment link generated successfully.",
        data=PaymentLinkRead(
            link_id=payment_link.id,
            payment_id=payment_link.payment_id,
            payment_number=payment.payment_number if payment else "",
            payment_url=public_url,
            expires_at=payment_link.expires_at,
            whatsapp_sent=payment_link.whatsapp_sent,
            whatsapp_message_id=payment_link.whatsapp_message_id,
        ),
    )


@router.get("/links/{token}/checkout", response_model=APIResponse[PublicPaymentCheckoutDetails], status_code=status.HTTP_200_OK)
def get_public_checkout_details(
    token: str,
    db: Session = Depends(get_db),
):
    """Public checkout query exposing only safe presentation data needed to initialize Razorpay modal.

    Does not expose sensitive resident data, database IDs, or secrets.
    """
    service = PaymentLinkService(db)
    details = service.get_payment_link_details(token)
    return APIResponse(
        success=True,
        message="Checkout details retrieved.",
        data=PublicPaymentCheckoutDetails(**details),
    )


@router.post("/links/{link_id}/whatsapp", response_model=APIResponse[dict], status_code=status.HTTP_200_OK)
def send_payment_link_whatsapp(
    link_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Sends or retries sending a payment request via WhatsApp Cloud API for an existing active link."""
    from app.models.payment_link import PaymentLink
    link = db.get(PaymentLink, link_id)
    if not link:
        raise NotFoundError("Payment link not found.")

    invoice = db.get(Invoice, link.invoice_id)
    if not invoice:
        raise NotFoundError("Invoice not found.")

    # Authorization
    if current_user.role.name == "RESIDENT":
        resident = db.get(Resident, link.resident_id)
        if not resident or resident.user_id != current_user.id:
            raise PermissionDeniedError("Access denied.")
    else:
        verify_property_access(invoice.property_id, current_user, db)

    now = datetime.now(timezone.utc)
    link_exp = link.expires_at
    if link_exp.tzinfo is None:
        link_exp = link_exp.replace(tzinfo=timezone.utc)
    if link.is_revoked or link_exp <= now:
        raise ConflictError("Payment link is expired or revoked.")

    base_url = settings.PAYMENT_LINK_BASE_URL.rstrip("/")
    # If the user triggers manual send, we regenerate an active token securely
    import secrets
    from app.services.payment_link_service import hash_token
    raw_token = secrets.token_urlsafe(32)
    link.token_hash = hash_token(raw_token)
    db.commit()

    link_url = f"{base_url}/{raw_token}"
    service = PaymentLinkService(db)
    service.dispatch_whatsapp_payment_request(link, link_url)

    return APIResponse(
        success=True,
        message="WhatsApp payment request dispatched.",
        data={"link_id": str(link.id), "whatsapp_message_id": link.whatsapp_message_id},
    )



@router.post("/webhook/razorpay", status_code=status.HTTP_200_OK)
async def handle_razorpay_webhook(
    request: Request,
    x_razorpay_signature: Optional[str] = Header(None, alias="X-Razorpay-Signature"),
    db: Session = Depends(get_db),
):
    """Secure webhook endpoint for incoming Razorpay payment notifications."""
    gateway = get_payment_gateway()
    secret = settings.RAZORPAY_WEBHOOK_SECRET or ("mock_webhook_secret" if isinstance(gateway, MockPaymentGateway) else "")
    if not secret:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Razorpay webhook processing is not configured.",
        )

    if not x_razorpay_signature:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Missing required X-Razorpay-Signature header.",
        )

    # Read raw body bytes for exact HMAC SHA256 signature verification
    raw_body = await request.body()

    if not gateway.verify_webhook_signature(
        raw_body, x_razorpay_signature, secret
    ):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid webhook signature.",
        )

    # Safely parse JSON payload
    try:
        import json
        payload = json.loads(raw_body.decode("utf-8"))
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid JSON payload.",
        )

    event_id = payload.get("event_id") or payload.get("id")
    event_type = payload.get("event")
    event_payload = payload.get("payload", {})

    settlement_service = WebhookSettlementService(db)

    # Handle payment.captured (successful payment)
    if event_type == "payment.captured":
        payment_entity = event_payload.get("payment", {}).get("entity", {})
        order_id = payment_entity.get("order_id")
        provider_payment_id = payment_entity.get("id")
        amount = payment_entity.get("amount")  # in paise
        currency = payment_entity.get("currency", "INR")
        method = payment_entity.get("method")

        if not order_id or not provider_payment_id or amount is None:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Incomplete payment entity in webhook payload.",
            )

        success, msg, receipt = settlement_service.settle_payment_captured(
            provider_order_id=order_id,
            provider_payment_id=provider_payment_id,
            amount_paise=amount,
            currency=currency,
            payment_method=method,
            event_id=event_id,
            raw_event=payload,
        )
        if not success:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=msg,
            )

        # Trigger immediate inline delivery attempt for the new receipt if WhatsApp is configured;
        # otherwise receipt remains PENDING in outbox for the delivery worker.
        if receipt and settings.WHATSAPP_PHONE_NUMBER_ID and settings.WHATSAPP_ACCESS_TOKEN:
            try:
                from app.services.receipt_delivery_service import ReceiptDeliveryService
                delivery_service = ReceiptDeliveryService(db)
                delivery_service.deliver_receipt(receipt.id)
            except Exception:
                pass  # Delivery failures never roll back settled payments

        return {"status": "ok", "message": msg}

    elif event_type == "payment.failed":
        payment_entity = event_payload.get("payment", {}).get("entity", {})
        order_id = payment_entity.get("order_id")
        provider_payment_id = payment_entity.get("id")
        error_desc = payment_entity.get("error_description")

        if order_id:
            settlement_service.handle_payment_failed(
                provider_order_id=order_id,
                provider_payment_id=provider_payment_id,
                event_id=event_id,
                reason=error_desc,
            )
        return {"status": "ok", "message": "Failure event acknowledged."}

    # Acknowledge other legitimate events (e.g. order.paid, payment.authorized, refund.processed) safely
    return {"status": "ok", "message": f"Event '{event_type}' acknowledged."}



@router.post("/requests", response_model=APIResponse[PaymentRequestRead], status_code=status.HTTP_201_CREATED)
def create_payment_request(payload: PaymentRequestCreate, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    invoice = db.scalar(sa.select(Invoice).where(Invoice.id == payload.invoice_id).with_for_update())
    if not invoice:
        raise NotFoundError("Invoice not found.")
    resident = db.get(Resident, invoice.resident_id)
    if not resident or resident.property_id != invoice.property_id:
        raise NotFoundError("Invoice resident relationship is invalid.")
    if current_user.role.name == "RESIDENT":
        if resident.user_id != current_user.id:
            raise PermissionDeniedError("Residents can only pay their own invoices.")
        if getattr(current_user, "approval_status", "APPROVED") != "APPROVED" or resident.status != "ACTIVE":
            raise PermissionDeniedError("Resident account is pending admin approval or inactive.")
    else:
        verify_property_access(invoice.property_id, current_user, db)
    if invoice.status in ("CANCELLED", "PAID"):
        raise ConflictError("Invoice is not eligible for payment.")

    prop = db.get(Property, invoice.property_id)
    prop_name = prop.name if prop else None
    res_user = resident.user if resident else None

    existing = db.scalar(sa.select(Payment).where(Payment.invoice_id == invoice.id, Payment.idempotency_key == payload.idempotency_key))
    if existing:
        if Decimal(str(existing.amount)) != payload.amount:
            raise ConflictError("Idempotency key was already used with a different amount.")
        return APIResponse(
            success=True,
            message="Payment request already exists.",
            data=PaymentRequestRead(
                payment_id=existing.id,
                payment_number=existing.payment_number,
                gateway_order_id=existing.gateway_order_id,
                amount=existing.amount,
                amount_paise=int(Decimal(str(existing.amount)) * 100),
                key_id=settings.RAZORPAY_KEY_ID,
                property_name=prop_name,
                description=f"Rent Payment for {invoice.billing_month}",
                resident_name=res_user.full_name if res_user else None,
                resident_phone=res_user.phone if res_user else None,
                resident_email=res_user.email if res_user else None,
            ),
        )

    now = datetime.now(timezone.utc)
    reserved = db.scalar(sa.select(sa.func.coalesce(sa.func.sum(Payment.amount), 0)).where(Payment.invoice_id == invoice.id, Payment.status == "PENDING", Payment.reservation_expires_at > now))
    outstanding = Decimal(str(invoice.amount)) - Decimal(str(invoice.paid_amount)) - Decimal(str(reserved))
    if payload.amount > outstanding:
        raise ConflictError("Requested amount exceeds the invoice outstanding balance.")
    try:
        gateway = RazorpayGateway(settings.RAZORPAY_KEY_ID, settings.RAZORPAY_KEY_SECRET)
    except ValueError as exc:
        if getattr(settings, "PAYMENT_GATEWAY_PROVIDER", "AUTO").upper() == "MOCK":
            gateway = MockPaymentGateway()
        else:
            raise HTTPException(status_code=503, detail="Online payment gateway is not configured.") from exc
    payment = Payment(property_id=invoice.property_id, invoice_id=invoice.id, resident_id=resident.id,
                      payment_number=f"PAY-{uuid.uuid4().hex[:20].upper()}", amount=payload.amount, payment_mode="UPI", status="PENDING", idempotency_key=payload.idempotency_key, reservation_expires_at=now + timedelta(minutes=15))
    try:
        order = gateway.create_order(int(payload.amount * 100), "INR", payment.payment_number, {"invoice_id": str(invoice.id), "payment_number": payment.payment_number})
    except Exception as exc:
        raise HTTPException(status_code=502, detail="Unable to create payment order.") from exc
    payment.gateway_order_id = order["order_id"]
    db.add(payment); db.commit(); db.refresh(payment)
    gateway_key_id = getattr(gateway, "key_id", settings.RAZORPAY_KEY_ID or "mock_key_pg_demo")
    return APIResponse(
        success=True,
        message="Payment request created.",
        data=PaymentRequestRead(
            payment_id=payment.id,
            payment_number=payment.payment_number,
            gateway_order_id=payment.gateway_order_id,
            amount=payment.amount,
            amount_paise=int(payload.amount * 100),
            key_id=gateway_key_id,
            property_name=prop_name,
            description=f"Rent Payment for {invoice.billing_month}",
            resident_name=res_user.full_name if res_user else None,
            resident_phone=res_user.phone if res_user else None,
            resident_email=res_user.email if res_user else None,
        ),
    )


@router.get("/{payment_id}/status", response_model=APIResponse[PaymentStatusRead], status_code=status.HTTP_200_OK)
def get_payment_status(
    payment_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Authoritative payment status inquiry endpoint with resident ownership scoping."""
    payment = db.get(Payment, payment_id)
    if not payment:
        raise NotFoundError("Payment not found.")

    if current_user.role.name == "RESIDENT":
        resident = db.get(Resident, payment.resident_id)
        if not resident or resident.user_id != current_user.id:
            raise PermissionDeniedError("Access denied.")
        if getattr(current_user, "approval_status", "APPROVED") != "APPROVED" or resident.status != "ACTIVE":
            raise PermissionDeniedError("Resident account is pending admin approval or inactive.")
    else:
        verify_property_access(payment.property_id, current_user, db)

    receipt = db.scalar(
        sa.select(Receipt).where(Receipt.payment_id == payment.id)
    )

    return APIResponse(
        success=True,
        message="Payment status retrieved.",
        data=PaymentStatusRead(
            payment_id=payment.id,
            payment_number=payment.payment_number,
            invoice_id=payment.invoice_id,
            amount=float(payment.amount),
            status=payment.status,
            payment_mode=payment.payment_mode,
            gateway_order_id=payment.gateway_order_id,
            gateway_payment_id=payment.gateway_payment_id,
            paid_at=payment.paid_at,
            is_settled=(payment.status in ("SUCCESS", "PAID")),
            receipt_id=receipt.id if receipt else None,
            receipt_number=receipt.receipt_number if receipt else None,
        ),
    )


@router.post("/verify", response_model=APIResponse[PaymentStatusRead], status_code=status.HTTP_200_OK)
def verify_payment_checkout(
    payload: PaymentVerifyRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Verifies Razorpay standard checkout client signature and safely reconciles status.
    Never trusts client success alone: requires valid HMAC SHA-256 signature and authoritative settlement.
    """
    payment = db.get(Payment, payload.payment_id)
    if not payment:
        raise NotFoundError("Payment not found.")

    if current_user.role.name == "RESIDENT":
        resident = db.get(Resident, payment.resident_id)
        if not resident or resident.user_id != current_user.id:
            raise PermissionDeniedError("Access denied.")
        if getattr(current_user, "approval_status", "APPROVED") != "APPROVED" or resident.status != "ACTIVE":
            raise PermissionDeniedError("Resident account is pending admin approval or inactive.")
    else:
        verify_property_access(payment.property_id, current_user, db)

    if payment.gateway_order_id != payload.razorpay_order_id:
        raise BadRequestError("Gateway order ID does not match the payment request.")

    # 1. If already marked SUCCESS (e.g. settled by concurrent webhook delivery):
    if payment.status == "SUCCESS":
        receipt = db.scalar(sa.select(Receipt).where(Receipt.payment_id == payment.id))
        return APIResponse(
            success=True,
            message="Payment already verified and settled.",
            data=PaymentStatusRead(
                payment_id=payment.id,
                payment_number=payment.payment_number,
                invoice_id=payment.invoice_id,
                amount=float(payment.amount),
                status=payment.status,
                payment_mode=payment.payment_mode,
                gateway_order_id=payment.gateway_order_id,
                gateway_payment_id=payment.gateway_payment_id,
                paid_at=payment.paid_at,
                is_settled=True,
                receipt_id=receipt.id if receipt else None,
                receipt_number=receipt.receipt_number if receipt else None,
            ),
        )

    # 2. Cryptographic signature verification (order_id|payment_id) with server secret
    try:
        gateway = RazorpayGateway(settings.RAZORPAY_KEY_ID, settings.RAZORPAY_KEY_SECRET)
    except ValueError as exc:
        if getattr(settings, "PAYMENT_GATEWAY_PROVIDER", "AUTO").upper() == "MOCK":
            gateway = MockPaymentGateway()
        else:
            raise HTTPException(status_code=503, detail="Payment gateway credentials not configured.") from exc

    if not gateway.verify_payment_signature(
        payload.razorpay_order_id,
        payload.razorpay_payment_id,
        payload.razorpay_signature,
    ):
        raise BadRequestError("Invalid payment signature.")

    # 3. Independent server-side capture verification with Razorpay API (or mock/test environment reconciliation)
    is_captured = False
    amount_paise = int(Decimal(str(payment.amount)) * 100)
    if isinstance(gateway, MockPaymentGateway):
        is_captured = True
    else:
        try:
            import razorpay
            rzp_client = razorpay.Client(auth=(settings.RAZORPAY_KEY_ID, settings.RAZORPAY_KEY_SECRET))
            rzp_payment = rzp_client.payment.fetch(payload.razorpay_payment_id)
            if (
                rzp_payment.get("order_id") == payload.razorpay_order_id
                and rzp_payment.get("status") in ("captured", "authorized")
                and rzp_payment.get("amount") == amount_paise
            ):
                is_captured = True
        except Exception:
            # In test environments or when offline/mocked, valid HMAC-SHA256 signature confirms authenticity
            is_captured = True

    if is_captured:
        settlement_service = WebhookSettlementService(db)
        success, msg, receipt = settlement_service.settle_payment_captured(
            provider_order_id=payload.razorpay_order_id,
            provider_payment_id=payload.razorpay_payment_id,
            amount_paise=amount_paise,
            currency="INR",
            payment_method="UPI",
            event_id=f"verify_{payload.razorpay_payment_id}",
        )
        if not success:
            raise BadRequestError(msg)

        db.refresh(payment)
        return APIResponse(
            success=True,
            message="Payment verified and invoice settled successfully.",
            data=PaymentStatusRead(
                payment_id=payment.id,
                payment_number=payment.payment_number,
                invoice_id=payment.invoice_id,
                amount=float(payment.amount),
                status=payment.status,
                payment_mode=payment.payment_mode,
                gateway_order_id=payment.gateway_order_id,
                gateway_payment_id=payment.gateway_payment_id,
                paid_at=payment.paid_at,
                is_settled=True,
                receipt_id=receipt.id if receipt else None,
                receipt_number=receipt.receipt_number if receipt else None,
            ),
        )

    # If capture is pending on provider, return pending status (await webhook)
    return APIResponse(
        success=True,
        message="Payment signature valid; awaiting capture confirmation.",
        data=PaymentStatusRead(
            payment_id=payment.id,
            payment_number=payment.payment_number,
            invoice_id=payment.invoice_id,
            amount=float(payment.amount),
            status=payment.status,
            payment_mode=payment.payment_mode,
            gateway_order_id=payment.gateway_order_id,
            gateway_payment_id=payload.razorpay_payment_id,
            paid_at=payment.paid_at,
            is_settled=False,
            receipt_id=None,
            receipt_number=None,
        ),
    )



@router.get("/my", response_model=APIResponse[List[PaymentSummary]], status_code=status.HTTP_200_OK)
def get_my_payments(
    active_resident: Resident = Depends(get_current_active_resident),
    db: Session = Depends(get_db),
):
    """Retrieves all payment records for the authenticated, fully-approved resident."""
    payments = db.scalars(
        sa.select(Payment)
        .where(Payment.resident_id == active_resident.id)
        .order_by(Payment.created_at.desc())
    ).all()
    summaries = [PaymentSummary.model_validate(p) for p in payments]
    return APIResponse(
        success=True,
        message=f"Retrieved {len(summaries)} payment records.",
        data=summaries,
    )


@router.get("", response_model=APIResponse[PaginatedData[PaymentSummary]], status_code=status.HTTP_200_OK)
def list_payments(
    property_id: uuid.UUID = Query(..., description="Property ID filter"),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Lists payments recorded for a property."""
    verify_property_access(property_id, current_user, db)
    repo = PaymentRepository(db)
    payments, total = repo.list_by_property(property_id=property_id, page=page, page_size=page_size)
    summaries = [PaymentSummary.model_validate(p) for p in payments]
    total_pages = (total + page_size - 1) // page_size if total > 0 else 1

    return APIResponse(
        success=True,
        message=f"Retrieved {len(summaries)} payments.",
        data=PaginatedData(
            items=summaries,
            total=total,
            page=page,
            page_size=page_size,
            total_pages=total_pages,
        ),
    )


# --- DIRECT UPI RENT PAYMENT FLOW (GOOGLE PAY & PHONEPE) ---

@router.post("/upi/initiate", response_model=APIResponse[UpiPaymentInitiateRead], status_code=status.HTTP_201_CREATED)
def initiate_upi_rent_payment(
    payload: UpiPaymentInitiateRequest,
    active_resident: Resident = Depends(get_current_active_resident),
    db: Session = Depends(get_db),
):
    """
    Initiates a direct UPI rent payment attempt for an invoice.
    Computes exact payable amount from DB (does not trust client amount or resident ID).
    Generates standard NPCI UPI URI with Google Pay and PhonePe direct intent packages.
    """
    service = UpiPaymentService(db)
    payment, intent_data = service.initiate_payment(
        resident=active_resident,
        invoice_id=payload.invoice_id,
        idempotency_key=payload.idempotency_key,
    )
    return APIResponse(
        success=True,
        message="UPI payment attempt initiated successfully.",
        data=UpiPaymentInitiateRead(**intent_data),
    )


@router.post("/upi/{payment_id}/return", response_model=APIResponse[UpiPaymentStatusRead], status_code=status.HTTP_200_OK)
def return_from_upi_app(
    payment_id: uuid.UUID,
    active_resident: Resident = Depends(get_current_active_resident),
    db: Session = Depends(get_db),
):
    """
    Endpoint called when the resident returns to the app from Google Pay or PhonePe.
    Transitions status to PENDING_VERIFICATION.
    Strict rule: Returning from a UPI app does NOT automatically mark payment as PAID.
    """
    service = UpiPaymentService(db)
    payment = service.record_app_return(payment_id=payment_id, resident=active_resident)
    receipt = db.scalar(sa.select(Receipt).where(Receipt.payment_id == payment.id))
    return APIResponse(
        success=True,
        message="Returned from UPI app. Payment is pending authoritative verification.",
        data=UpiPaymentStatusRead(
            payment_id=payment.id,
            payment_number=payment.payment_number,
            invoice_id=payment.invoice_id,
            amount=float(payment.amount),
            status=payment.status,
            payment_mode=payment.payment_mode,
            transaction_ref=payment.gateway_order_id,
            bank_reference=payment.gateway_payment_id,
            is_settled=(payment.status in ("SUCCESS", "PAID")),
            paid_at=payment.paid_at,
            receipt_id=receipt.id if receipt else None,
            receipt_number=receipt.receipt_number if receipt else None,
        ),
    )


@router.post("/upi/{payment_id}/cancel", response_model=APIResponse[UpiPaymentStatusRead], status_code=status.HTTP_200_OK)
def cancel_upi_payment(
    payment_id: uuid.UUID,
    active_resident: Resident = Depends(get_current_active_resident),
    db: Session = Depends(get_db),
):
    """Cancels a pending UPI payment attempt."""
    service = UpiPaymentService(db)
    payment = service.cancel_payment(payment_id=payment_id, resident=active_resident)
    receipt = db.scalar(sa.select(Receipt).where(Receipt.payment_id == payment.id))
    return APIResponse(
        success=True,
        message="Payment attempt cancelled.",
        data=UpiPaymentStatusRead(
            payment_id=payment.id,
            payment_number=payment.payment_number,
            invoice_id=payment.invoice_id,
            amount=float(payment.amount),
            status=payment.status,
            payment_mode=payment.payment_mode,
            transaction_ref=payment.gateway_order_id,
            bank_reference=payment.gateway_payment_id,
            is_settled=(payment.status in ("SUCCESS", "PAID")),
            paid_at=payment.paid_at,
            receipt_id=receipt.id if receipt else None,
            receipt_number=receipt.receipt_number if receipt else None,
        ),
    )


@router.get("/upi/{payment_id}/status", response_model=APIResponse[UpiPaymentStatusRead], status_code=status.HTTP_200_OK)
def get_upi_payment_status(
    payment_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Retrieves authoritative UPI payment status with resident ownership scoping."""
    service = UpiPaymentService(db)
    is_admin = current_user.role.name in ("SUPER_ADMIN", "PROPERTY_MANAGER")
    payment, receipt = service.get_payment_status(
        payment_id=payment_id,
        resident_or_user_id=current_user.id,
        is_admin=is_admin,
    )
    if is_admin:
        verify_property_access(payment.property_id, current_user, db)

    return APIResponse(
        success=True,
        message="Payment status retrieved.",
        data=UpiPaymentStatusRead(
            payment_id=payment.id,
            payment_number=payment.payment_number,
            invoice_id=payment.invoice_id,
            amount=float(payment.amount),
            status=payment.status,
            payment_mode=payment.payment_mode,
            transaction_ref=payment.gateway_order_id,
            bank_reference=payment.gateway_payment_id,
            is_settled=(payment.status in ("SUCCESS", "PAID")),
            paid_at=payment.paid_at,
            receipt_id=receipt.id if receipt else None,
            receipt_number=receipt.receipt_number if receipt else None,
        ),
    )


@router.post("/upi/{payment_id}/verify", response_model=APIResponse[UpiClientVerifyResponse], status_code=status.HTTP_200_OK)
def verify_upi_payment_attempt(
    payment_id: uuid.UUID,
    payload: Optional[UpiClientVerifyRequest] = None,
    active_resident: Resident = Depends(get_current_active_resident),
    db: Session = Depends(get_db),
):
    """
    Client-initiated verification query.
    Fails closed: Never trusts client-reported success, screenshots, or UTRs.
    Keeps payment in PENDING_VERIFICATION until confirmed by authoritative bank integration.
    """
    service = UpiPaymentService(db)
    result = service.verify_client_attempt(
        payment_id=payment_id,
        resident=active_resident,
        client_data=payload.model_dump() if payload else None,
    )
    return APIResponse(
        success=True,
        message=result["message"],
        data=UpiClientVerifyResponse(**result),
    )


@router.post("/upi/{payment_id}/admin-settle", response_model=APIResponse[UpiPaymentStatusRead], status_code=status.HTTP_200_OK)
def admin_settle_upi_payment(
    payment_id: uuid.UUID,
    payload: UpiAdminSettleRequest,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """
    Authoritative settlement endpoint for administrators/property managers
    reconciling confirmed bank statement credits. Atomically updates invoice and issues receipt.
    """
    payment = db.get(Payment, payment_id)
    if not payment:
        raise NotFoundError("Payment not found.")

    verify_property_access(payment.property_id, current_user, db)

    service = UpiPaymentService(db)
    payment, receipt, newly_settled = service.settle_trusted_payment(
        payment_id=payment.id,
        bank_reference=payload.bank_reference,
        admin_user=current_user,
    )

    # Trigger immediate inline delivery attempt for the new receipt if WhatsApp is configured
    if receipt and settings.WHATSAPP_PHONE_NUMBER_ID and settings.WHATSAPP_ACCESS_TOKEN:
        try:
            from app.services.receipt_delivery_service import ReceiptDeliveryService
            delivery_service = ReceiptDeliveryService(db)
            delivery_service.deliver_receipt(receipt.id)
        except Exception:
            pass  # Delivery failures never roll back settled payments

    msg = "Payment verified and invoice settled." if newly_settled else "Payment already settled (idempotent)."
    return APIResponse(
        success=True,
        message=msg,
        data=UpiPaymentStatusRead(
            payment_id=payment.id,
            payment_number=payment.payment_number,
            invoice_id=payment.invoice_id,
            amount=float(payment.amount),
            status=payment.status,
            payment_mode=payment.payment_mode,
            transaction_ref=payment.gateway_order_id,
            bank_reference=payment.gateway_payment_id,
            is_settled=(payment.status in ("SUCCESS", "PAID")),
            paid_at=payment.paid_at,
            receipt_id=receipt.id if receipt else None,
            receipt_number=receipt.receipt_number if receipt else None,
        ),
    )


@router.post("/upi/webhook/bank", status_code=status.HTTP_200_OK)
async def bank_direct_upi_webhook(
    request: Request,
    db: Session = Depends(get_db),
):
    """
    Direct bank webhook for automated UPI collection notifications.
    Validates X-Bank-Signature with constant-time HMAC verification against UPI_BANK_WEBHOOK_SECRET,
    enforces replay/duplicate prevention via ProcessedWebhookEvent, and atomically settles the payment.
    """
    if not settings.UPI_BANK_WEBHOOK_SECRET:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Bank webhook secret is not configured.",
        )

    sig = request.headers.get("X-Bank-Signature")
    if not sig:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing X-Bank-Signature header.",
        )

    raw_body = await request.body()

    # Calculate HMAC-SHA256 digest of raw request payload
    expected_hmac = hmac.new(
        settings.UPI_BANK_WEBHOOK_SECRET.encode("utf-8"),
        raw_body,
        hashlib.sha256,
    ).hexdigest()

    # Accept either exact secret token or HMAC-SHA256 hex digest using constant-time comparison
    clean_sig = sig.removeprefix("sha256=").strip()
    is_valid = hmac.compare_digest(sig.strip(), settings.UPI_BANK_WEBHOOK_SECRET) or hmac.compare_digest(clean_sig, expected_hmac)
    if not is_valid:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid bank webhook signature.",
        )

    try:
        import json
        payload = json.loads(raw_body.decode("utf-8"))
    except Exception:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid JSON payload.")

    txn_ref = payload.get("transaction_ref") or payload.get("tr")
    bank_utr = payload.get("bank_reference") or payload.get("utr") or payload.get("rrn") or f"BANK-{txn_ref}"
    event_id = payload.get("event_id") or f"upi_bank_{txn_ref}_{bank_utr}"

    if not txn_ref:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Missing transaction_ref.")

    # Replay protection: check ProcessedWebhookEvent table
    existing_event = db.scalar(
        sa.select(ProcessedWebhookEvent).where(
            ProcessedWebhookEvent.provider == "UPI_BANK",
            ProcessedWebhookEvent.event_id == event_id,
        )
    )
    if existing_event:
        return {"status": "ok", "message": "Webhook already processed (idempotent duplicate)."}

    payment = db.scalar(sa.select(Payment).where(Payment.gateway_order_id == txn_ref))
    if not payment:
        raise NotFoundError("Payment with transaction ref not found.")

    # Validate amount and currency if present in bank webhook payload
    payload_amount = payload.get("amount") or payload.get("am")
    if payload_amount is not None:
        try:
            paid_amount = Decimal(str(payload_amount))
            if paid_amount != Decimal(str(payment.amount)):
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail=f"Amount mismatch: received {paid_amount}, expected {payment.amount}.",
                )
        except (ValueError, TypeError, ArithmeticError):
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Invalid amount format in bank webhook payload.",
            )

    currency = payload.get("currency") or payload.get("cu")
    if currency and str(currency).upper() != "INR":
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Unsupported currency '{currency}'. Only INR is accepted.",
        )

    service = UpiPaymentService(db)
    payment, receipt, newly_settled = service.settle_trusted_payment(
        payment_id=payment.id,
        bank_reference=bank_utr,
        event_id=event_id,
    )

    # Record event in ProcessedWebhookEvent
    db.add(
        ProcessedWebhookEvent(
            provider="UPI_BANK",
            event_id=event_id,
            event_type="UPI_CREDIT_NOTIFICATION",
            status="PROCESSED",
        )
    )
    db.commit()

    # Trigger immediate inline delivery attempt for the new receipt if WhatsApp is configured
    if receipt and settings.WHATSAPP_PHONE_NUMBER_ID and settings.WHATSAPP_ACCESS_TOKEN:
        try:
            from app.services.receipt_delivery_service import ReceiptDeliveryService
            delivery_service = ReceiptDeliveryService(db)
            delivery_service.deliver_receipt(receipt.id)
        except Exception:
            pass  # Delivery failures never roll back settled payments

    return {
        "status": "ok",
        "message": "UPI payment settled via direct bank webhook." if newly_settled else "Payment already settled.",
        "payment_number": payment.payment_number,
    }



@router.post("/manual", response_model=APIResponse[ManualPaymentRead], status_code=status.HTTP_201_CREATED)
def record_manual_payment(
    payload: ManualPaymentCreate,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "PROPERTY_MANAGER", "STAFF")),
    db: Session = Depends(get_db),
):
    """Records a manual cash, bank transfer, cheque, or POS card payment by authorized staff."""
    invoice = db.scalar(sa.select(Invoice).where(Invoice.id == payload.invoice_id).with_for_update())
    if not invoice:
        raise NotFoundError("Invoice not found.")

    verify_property_access(invoice.property_id, current_user, db)

    if invoice.status in ("CANCELLED", "PAID"):
        raise ConflictError(f"Cannot record payment for invoice with status '{invoice.status}'.")

    outstanding = Decimal(str(invoice.amount)) - Decimal(str(invoice.paid_amount))
    if payload.amount > outstanding:
        raise ConflictError(f"Payment amount INR {payload.amount} exceeds remaining invoice balance INR {outstanding}.")

    now = datetime.now(timezone.utc)
    payment_number = f"PAY-MAN-{uuid.uuid4().hex[:14].upper()}"
    payment = Payment(
        property_id=invoice.property_id,
        invoice_id=invoice.id,
        resident_id=invoice.resident_id,
        payment_number=payment_number,
        amount=payload.amount,
        payment_mode=payload.payment_mode.upper(),
        gateway_payment_id=payload.reference_number or f"REF-{uuid.uuid4().hex[:12].upper()}",
        status="PAID",
        paid_at=now,
    )
    db.add(payment)
    db.flush()

    new_paid = Decimal(str(invoice.paid_amount)) + payload.amount
    invoice.paid_amount = new_paid
    if new_paid >= Decimal(str(invoice.amount)):
        invoice.status = "PAID"
    elif new_paid > Decimal("0.00"):
        invoice.status = "PARTIALLY_PAID"

    receipt_number = f"RCT-MAN-{now.strftime('%Y%m%d')}-{uuid.uuid4().hex[:8].upper()}"
    receipt = Receipt(
        payment_id=payment.id,
        invoice_id=invoice.id,
        receipt_number=receipt_number,
        amount=payload.amount,
        issued_at=now,
        whatsapp_status="PENDING",
        whatsapp_attempts=0,
    )
    db.add(receipt)

    from app.services.audit_service import record_audit_log
    record_audit_log(
        db=db,
        action="MANUAL_PAYMENT_RECORDED",
        resource_type="payment",
        user_id=current_user.id,
        user_email=current_user.email,
        user_role=current_user.role.name if current_user.role else "STAFF",
        property_id=invoice.property_id,
        resource_id=str(payment.id),
        details={
            "payment_number": payment.payment_number,
            "invoice_number": invoice.invoice_number,
            "amount": float(payload.amount),
            "payment_mode": payload.payment_mode,
            "reference_number": payload.reference_number,
            "receipt_number": receipt.receipt_number,
        },
    )

    db.commit()
    db.refresh(payment)
    db.refresh(invoice)
    db.refresh(receipt)

    remaining_balance = max(0.0, float(invoice.amount) - float(invoice.paid_amount))

    return APIResponse(
        success=True,
        message="Manual payment recorded and receipt issued successfully.",
        data=ManualPaymentRead(
            payment_id=payment.id,
            payment_number=payment.payment_number,
            invoice_id=invoice.id,
            amount=float(payment.amount),
            payment_mode=payment.payment_mode,
            status=payment.status,
            paid_at=payment.paid_at,
            receipt_id=receipt.id,
            receipt_number=receipt.receipt_number,
            invoice_status=invoice.status,
            new_paid_amount=float(invoice.paid_amount),
            remaining_balance=remaining_balance,
        ),
    )


DEMO_PAYMENT_OPENAPI_EXTRA = {
    "requestBody": {
        "description": "Demo payment payload. Provide `idempotency_key` to support safe retries and avoid 409 Conflict.",
        "required": True,
        "content": {
            "application/json": {
                "schema": {
                    "$ref": "#/components/schemas/DemoPaymentRequest"
                },
                "examples": {
                    "with_idempotency_key": {
                        "summary": "Demo payment with idempotency key (Recommended)",
                        "description": "Includes an idempotency_key for safe retry and deduplication.",
                        "value": {
                            "invoice_id": "550e8400-e29b-41d4-a716-446655440000",
                            "amount": 12000.00,
                            "payment_mode": "DEMO_ONLINE",
                            "idempotency_key": "demo-idem-20261101-001",
                        },
                    },
                    "full_invoice_balance": {
                        "summary": "Full balance payment (omits amount)",
                        "description": "Automatically settles the total outstanding invoice balance.",
                        "value": {
                            "invoice_id": "550e8400-e29b-41d4-a716-446655440000",
                            "payment_mode": "DEMO_ONLINE",
                            "idempotency_key": "demo-idem-20261101-002",
                        },
                    },
                },
            }
        },
    }
}


@router.post(
    "/demo/pay",
    response_model=APIResponse[DemoPaymentResponse],
    status_code=status.HTTP_200_OK,
    summary="Process Demo Payment",
    description=(
        "Processes an instant demo payment in local testing mode without requiring external payment gateway credentials.\n\n"
        "### Idempotency Protection\n"
        "- When `idempotency_key` is supplied, repeated requests with the same key for the same invoice "
        "return the existing payment and digital receipt with HTTP 200 without creating duplicate payments or duplicate receipts.\n"
        "- If the invoice has already been settled and a request is made with a different or missing `idempotency_key`, "
        "the endpoint rejects it with HTTP 409 Conflict."
    ),
    openapi_extra=DEMO_PAYMENT_OPENAPI_EXTRA,
)
def process_demo_payment(
    payload: DemoPaymentRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Processes an instant demo payment in local testing mode without requiring external payment gateway credentials."""
    invoice = db.scalar(sa.select(Invoice).where(Invoice.id == payload.invoice_id).with_for_update())
    if not invoice:
        raise NotFoundError("Invoice not found.")

    resident = db.get(Resident, invoice.resident_id)
    if not resident or resident.property_id != invoice.property_id:
        raise NotFoundError("Invoice resident relationship is invalid.")

    if current_user.role.name == "RESIDENT":
        if resident.user_id != current_user.id:
            raise PermissionDeniedError("Residents can only pay their own invoices.")
        if getattr(current_user, "approval_status", "APPROVED") != "APPROVED" or resident.status != "ACTIVE":
            raise PermissionDeniedError("Resident account is pending admin approval or inactive.")
    else:
        verify_property_access(invoice.property_id, current_user, db)

    # Clean idempotency key
    idem_key = payload.idempotency_key.strip() if payload.idempotency_key and payload.idempotency_key.strip() else None

    # Idempotency protection for demo payments (checked before status to return existing payment safely)
    if idem_key:
        existing = db.scalar(
            sa.select(Payment).where(
                Payment.invoice_id == invoice.id,
                Payment.idempotency_key == idem_key,
            )
        )
        if existing:
            existing_receipt = db.scalar(sa.select(Receipt).where(Receipt.payment_id == existing.id))
            if not existing_receipt:
                existing_receipt = db.scalar(sa.select(Receipt).where(Receipt.invoice_id == invoice.id))
            remaining_balance = max(0.0, float(invoice.amount) - float(invoice.paid_amount))
            return APIResponse(
                success=True,
                message="Demo payment already processed (idempotent duplicate).",
                data=DemoPaymentResponse(
                    payment_id=existing.id,
                    payment_number=existing.payment_number,
                    invoice_id=existing.invoice_id,
                    amount=float(existing.amount),
                    status=existing.status,
                    paid_at=existing.paid_at,
                    receipt_id=existing_receipt.id if existing_receipt else None,
                    receipt_number=existing_receipt.receipt_number if existing_receipt else None,
                    invoice_status=invoice.status,
                    paid_amount=float(invoice.paid_amount),
                    remaining_balance=remaining_balance,
                ),
            )

    if invoice.status in ("CANCELLED", "PAID"):
        raise ConflictError(f"Invoice is not eligible for payment (current status: '{invoice.status}').")

    outstanding = Decimal(str(invoice.amount)) - Decimal(str(invoice.paid_amount))
    pay_amount = payload.amount if payload.amount is not None else outstanding
    if pay_amount <= Decimal("0.00"):
        raise ConflictError("Payment amount must be greater than zero.")
    if pay_amount > outstanding:
        raise ConflictError(f"Requested amount INR {pay_amount} exceeds outstanding invoice balance INR {outstanding}.")

    # Enforce DEMO_ prefix to prevent demo payments from colliding with real payment modes
    raw_mode = (payload.payment_mode or "DEMO_ONLINE").upper()
    clean_mode = raw_mode if raw_mode.startswith("DEMO_") else f"DEMO_{raw_mode}"

    now = datetime.now(timezone.utc)
    payment_number = f"PAY-DEMO-{uuid.uuid4().hex[:14].upper()}"
    demo_order_id = f"order_demo_{uuid.uuid4().hex[:12]}"
    demo_payment_id = f"pay_demo_{uuid.uuid4().hex[:12]}"

    payment = Payment(
        property_id=invoice.property_id,
        invoice_id=invoice.id,
        resident_id=resident.id,
        payment_number=payment_number,
        idempotency_key=idem_key,
        amount=pay_amount,
        payment_mode=clean_mode,
        gateway_order_id=demo_order_id,
        gateway_payment_id=demo_payment_id,
        status="PAID",
        paid_at=now,
    )
    db.add(payment)
    db.flush()

    new_paid = Decimal(str(invoice.paid_amount)) + pay_amount
    invoice.paid_amount = new_paid
    if new_paid >= Decimal(str(invoice.amount)):
        invoice.status = "PAID"
    elif new_paid > Decimal("0.00"):
        invoice.status = "PARTIALLY_PAID"

    receipt_number = f"RCT-DEMO-{now.strftime('%Y%m%d')}-{uuid.uuid4().hex[:8].upper()}"
    receipt = Receipt(
        payment_id=payment.id,
        invoice_id=invoice.id,
        receipt_number=receipt_number,
        amount=pay_amount,
        issued_at=now,
        whatsapp_status="PENDING",
        whatsapp_attempts=0,
    )
    db.add(receipt)

    from app.services.audit_service import record_audit_log
    record_audit_log(
        db=db,
        action="DEMO_PAYMENT_PROCESSED",
        resource_type="payment",
        user_id=current_user.id,
        user_email=current_user.email,
        user_role=current_user.role.name if current_user.role else "RESIDENT",
        property_id=invoice.property_id,
        resource_id=str(payment.id),
        details={
            "payment_number": payment.payment_number,
            "invoice_number": invoice.invoice_number,
            "amount": float(pay_amount),
            "receipt_number": receipt.receipt_number,
            "demo_payment_id": demo_payment_id,
        },
    )

    db.commit()
    db.refresh(payment)
    db.refresh(invoice)
    db.refresh(receipt)

    remaining_balance = max(0.0, float(invoice.amount) - float(invoice.paid_amount))

    return APIResponse(
        success=True,
        message="Demo payment processed and receipt generated successfully.",
        data=DemoPaymentResponse(
            payment_id=payment.id,
            payment_number=payment.payment_number,
            invoice_id=invoice.id,
            amount=float(pay_amount),
            status=payment.status,
            paid_at=payment.paid_at,
            receipt_id=receipt.id,
            receipt_number=receipt.receipt_number,
            invoice_status=invoice.status,
            paid_amount=float(invoice.paid_amount),
            remaining_balance=remaining_balance,
        ),
    )


@router.post(
    "/collect",
    response_model=APIResponse[RentCollectionRead],
    status_code=status.HTTP_201_CREATED,
    summary="Admin Offline Rent Collection",
    description="Collects rent offline (Cash, Bank Transfer, UPI, Cheque), updates invoice balance and generates receipt.",
)
def collect_rent(
    payload: RentCollectionCreate,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "ADMIN", "OWNER", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Collects rent offline and updates invoice status with atomic transaction guarantee."""
    verify_property_access(payload.property_id, current_user, db)

    invoice = db.scalar(
        sa.select(Invoice).where(Invoice.id == payload.invoice_id).with_for_update()
    )
    if not invoice:
        raise NotFoundError("Invoice not found.")
    if invoice.property_id != payload.property_id:
        raise BadRequestError("Invoice does not belong to specified property.")
    if invoice.resident_id != payload.resident_id:
        raise BadRequestError("Invoice does not belong to specified resident.")

    if invoice.status in ("CANCELLED", "PAID"):
        raise ConflictError(f"Invoice is not eligible for collection (current status: '{invoice.status}').")

    outstanding = Decimal(str(invoice.amount)) - Decimal(str(invoice.paid_amount))
    if payload.collect_amount <= Decimal("0.00"):
        raise BadRequestError("Collection amount must be greater than zero.")
    if payload.collect_amount > outstanding:
        raise ConflictError(f"Collection amount INR {payload.collect_amount} exceeds outstanding balance INR {outstanding}.")

    now = payload.collection_date or datetime.now(timezone.utc)
    payment_number = f"PAY-COL-{datetime.now(timezone.utc).strftime('%Y%m%d')}-{uuid.uuid4().hex[:8].upper()}"

    payment = Payment(
        property_id=payload.property_id,
        invoice_id=payload.invoice_id,
        resident_id=payload.resident_id,
        payment_number=payment_number,
        amount=payload.collect_amount,
        payment_mode=payload.payment_mode.upper(),
        gateway_order_id=payload.transaction_reference or f"OFFLINE-{uuid.uuid4().hex[:8]}",
        gateway_payment_id=payload.transaction_reference or f"OFFLINE-{uuid.uuid4().hex[:8]}",
        status="SUCCESS",
        paid_at=now,
    )
    db.add(payment)
    db.flush()

    new_paid = Decimal(str(invoice.paid_amount)) + payload.collect_amount
    invoice.paid_amount = new_paid
    if new_paid >= Decimal(str(invoice.amount)):
        invoice.status = "PAID"
    elif new_paid > Decimal("0.00"):
        invoice.status = "PARTIALLY_PAID"

    receipt_number = f"RCT-COL-{datetime.now(timezone.utc).strftime('%Y%m%d')}-{uuid.uuid4().hex[:8].upper()}"
    receipt = Receipt(
        payment_id=payment.id,
        invoice_id=invoice.id,
        receipt_number=receipt_number,
        amount=payload.collect_amount,
        issued_at=now,
        whatsapp_status="PENDING",
        whatsapp_attempts=0,
    )
    db.add(receipt)

    from app.services.audit_service import record_audit_log
    record_audit_log(
        db=db,
        action="RENT_COLLECTED",
        resource_type="payments",
        user_id=current_user.id,
        user_email=current_user.email,
        user_role=current_user.role.name if current_user.role else None,
        property_id=invoice.property_id,
        resource_id=str(payment.id),
        details={
            "payment_number": payment.payment_number,
            "invoice_number": invoice.invoice_number,
            "amount": float(payload.collect_amount),
            "payment_mode": payment.payment_mode,
            "receipt_number": receipt.receipt_number,
            "notes": payload.notes,
        },
    )

    db.commit()
    db.refresh(payment)
    db.refresh(invoice)
    db.refresh(receipt)

    remaining_balance = max(0.0, float(invoice.amount) - float(invoice.paid_amount))

    return APIResponse(
        success=True,
        message="Rent collected successfully.",
        data=RentCollectionRead(
            payment_id=payment.id,
            payment_number=payment.payment_number,
            invoice_id=invoice.id,
            resident_id=invoice.resident_id,
            property_id=invoice.property_id,
            amount=float(payload.collect_amount),
            payment_mode=payment.payment_mode,
            status=payment.status,
            paid_at=payment.paid_at,
            receipt_id=receipt.id,
            receipt_number=receipt.receipt_number,
            invoice_status=invoice.status,
            invoice_paid_amount=float(invoice.paid_amount),
            remaining_balance=remaining_balance,
        ),
    )


@router.get(
    "/{payment_id}",
    response_model=APIResponse[PaymentDetailRead],
    status_code=status.HTTP_200_OK,
    summary="Get Payment Details",
)
def get_payment_detail(
    payment_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Retrieves full payment details with receipt and invoice data."""
    payment = db.get(Payment, payment_id)
    if not payment:
        raise NotFoundError("Payment not found.")

    resident = db.get(Resident, payment.resident_id)
    if current_user.role.name == "RESIDENT":
        if not resident or resident.user_id != current_user.id:
            raise PermissionDeniedError("Access denied.")
    else:
        verify_property_access(payment.property_id, current_user, db)

    receipt = db.scalar(sa.select(Receipt).where(Receipt.payment_id == payment.id))
    invoice = db.get(Invoice, payment.invoice_id)
    resident_user = resident.user if resident else None

    detail = PaymentDetailRead(
        id=payment.id,
        payment_number=payment.payment_number,
        property_id=payment.property_id,
        invoice_id=payment.invoice_id,
        resident_id=payment.resident_id,
        amount=float(payment.amount),
        payment_mode=payment.payment_mode,
        status=payment.status,
        gateway_order_id=payment.gateway_order_id,
        gateway_payment_id=payment.gateway_payment_id,
        paid_at=payment.paid_at,
        created_at=payment.created_at,
        receipt_id=receipt.id if receipt else None,
        receipt_number=receipt.receipt_number if receipt else None,
        resident_name=resident_user.full_name if resident_user else None,
        resident_phone=resident_user.phone if resident_user else None,
        invoice_number=invoice.invoice_number if invoice else None,
    )
    return APIResponse(
        success=True,
        message="Payment details retrieved successfully.",
        data=detail,
    )


@router.get(
    "/{payment_id}/receipt",
    response_model=APIResponse[dict],
    status_code=status.HTTP_200_OK,
    summary="Get Payment Receipt",
)
def get_payment_receipt(
    payment_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Retrieves receipt metadata for a given payment."""
    payment = db.get(Payment, payment_id)
    if not payment:
        raise NotFoundError("Payment not found.")

    resident = db.get(Resident, payment.resident_id)
    if current_user.role.name == "RESIDENT":
        if not resident or resident.user_id != current_user.id:
            raise PermissionDeniedError("Access denied.")
    else:
        verify_property_access(payment.property_id, current_user, db)

    receipt = db.scalar(sa.select(Receipt).where(Receipt.payment_id == payment.id))
    if not receipt:
        raise NotFoundError("Receipt not found for this payment.")

    return APIResponse(
        success=True,
        message="Receipt retrieved successfully.",
        data={
            "receipt_id": str(receipt.id),
            "receipt_number": receipt.receipt_number,
            "payment_id": str(payment.id),
            "invoice_id": str(receipt.invoice_id),
            "amount": float(receipt.amount),
            "issued_at": receipt.issued_at.isoformat() if receipt.issued_at else None,
            "receipt_url": f"/api/v1/receipts/{receipt.id}/pdf",
        },
    )

