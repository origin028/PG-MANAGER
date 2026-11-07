import uuid
from typing import List
from fastapi import APIRouter, Depends, status
import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.core.exceptions import NotFoundError, PermissionDeniedError
from app.dependencies import (
    get_current_active_resident,
    get_current_user,
    get_db,
    verify_property_access,
)
from app.models.bed import Bed
from app.models.invoice import Invoice
from app.models.payment import Payment
from app.models.property import Property
from app.models.receipt import Receipt
from app.models.resident import Resident
from app.models.room import Room
from app.models.user import User
from app.schemas.common import APIResponse
from app.schemas.receipt import ReceiptDetailRead, ReceiptSummaryRead

router = APIRouter()


@router.get("/my", response_model=APIResponse[List[ReceiptSummaryRead]], status_code=status.HTTP_200_OK)
def get_my_receipts(
    active_resident: Resident = Depends(get_current_active_resident),
    db: Session = Depends(get_db),
):
    """Retrieves all payment receipts issued to the authenticated, fully-approved resident."""
    # Query receipts joined with invoice and payment
    receipts_query = (
        sa.select(Receipt, Invoice, Payment)
        .join(Invoice, Receipt.invoice_id == Invoice.id)
        .join(Payment, Receipt.payment_id == Payment.id)
        .where(Invoice.resident_id == active_resident.id)
        .order_by(Receipt.issued_at.desc())
    )
    rows = db.execute(receipts_query).all()

    items = [
        ReceiptSummaryRead(
            id=r.id,
            receipt_number=r.receipt_number,
            amount=float(r.amount),
            issued_at=r.issued_at,
            invoice_id=inv.id,
            invoice_number=inv.invoice_number,
            billing_month=inv.billing_month,
            payment_mode=pay.payment_mode,
        )
        for r, inv, pay in rows
    ]

    return APIResponse(
        success=True,
        message=f"Retrieved {len(items)} digital receipts.",
        data=items,
    )


@router.get("/{receipt_id}", response_model=APIResponse[ReceiptDetailRead], status_code=status.HTTP_200_OK)
def get_receipt_detail(
    receipt_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Retrieves authoritative receipt details with strict resident ownership verification."""
    receipt = db.get(Receipt, receipt_id)
    if not receipt:
        raise NotFoundError("Receipt not found.")

    invoice = db.get(Invoice, receipt.invoice_id)
    if not invoice:
        raise NotFoundError("Associated invoice not found.")

    resident = db.get(Resident, invoice.resident_id)
    if not resident:
        raise NotFoundError("Associated resident record not found.")

    # Enforce ownership: Residents can only access their own receipts
    if current_user.role.name == "RESIDENT":
        if resident.user_id != current_user.id:
            raise PermissionDeniedError("Access denied. Residents can only view their own receipts.")
        if getattr(current_user, "approval_status", "APPROVED") != "APPROVED" or resident.status != "ACTIVE":
            raise PermissionDeniedError("Resident account is pending admin approval or inactive.")
    else:
        verify_property_access(invoice.property_id, current_user, db)

    payment = db.get(Payment, receipt.payment_id)
    property_record = db.get(Property, invoice.property_id)
    room_record = db.get(Room, resident.room_id) if resident.room_id else None
    bed_record = db.get(Bed, resident.bed_id) if resident.bed_id else None
    resident_user = resident.user

    detail = ReceiptDetailRead(
        id=receipt.id,
        receipt_number=receipt.receipt_number,
        amount=float(receipt.amount),
        issued_at=receipt.issued_at,
        invoice_id=invoice.id,
        invoice_number=invoice.invoice_number,
        billing_month=invoice.billing_month,
        invoice_type=invoice.invoice_type,
        property_name=property_record.name if property_record else "Unknown Property",
        property_address=property_record.address_line1 if property_record else None,
        room_number=room_record.room_number if room_record else None,
        bed_number=bed_record.bed_number if bed_record else None,
        resident_id=resident.id,
        resident_name=resident_user.full_name if resident_user else "Resident",
        resident_phone=resident_user.phone if resident_user else "",
        resident_email=resident_user.email if resident_user else None,
        payment_id=payment.id if payment else receipt.payment_id,
        payment_number=payment.payment_number if payment else "",
        payment_mode=payment.payment_mode if payment else "UPI",
        gateway_payment_id=payment.gateway_payment_id if payment else None,
        paid_at=payment.paid_at if payment else None,
    )

    return APIResponse(
        success=True,
        message="Receipt retrieved successfully.",
        data=detail,
    )


@router.get("/{receipt_id}/pdf", status_code=status.HTTP_200_OK)
def download_receipt_pdf(
    receipt_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Generates and downloads a standards-compliant PDF payment receipt."""
    from fastapi import Response
    from app.services.pdf_service import build_receipt_pdf

    receipt = db.get(Receipt, receipt_id)
    if not receipt:
        raise NotFoundError("Receipt not found.")

    invoice = db.get(Invoice, receipt.invoice_id)
    if not invoice:
        raise NotFoundError("Associated invoice not found.")

    resident = db.get(Resident, invoice.resident_id)
    if not resident:
        raise NotFoundError("Associated resident record not found.")

    # Enforce ownership: Residents can only access their own receipts
    if current_user.role.name == "RESIDENT":
        if resident.user_id != current_user.id:
            raise PermissionDeniedError("Access denied. Residents can only download their own receipts.")
        if getattr(current_user, "approval_status", "APPROVED") != "APPROVED" or resident.status != "ACTIVE":
            raise PermissionDeniedError("Resident account is pending admin approval or inactive.")
    else:
        verify_property_access(invoice.property_id, current_user, db)

    payment = db.get(Payment, receipt.payment_id)
    property_record = db.get(Property, invoice.property_id)
    resident_user = resident.user

    pdf_bytes = build_receipt_pdf(
        receipt_number=receipt.receipt_number,
        amount=float(receipt.amount),
        payment_mode=payment.payment_mode if payment else "ONLINE",
        payment_number=payment.payment_number if payment else "N/A",
        invoice_number=invoice.invoice_number,
        resident_name=resident_user.full_name if resident_user else "Resident",
        property_name=property_record.name if property_record else "PG Property",
        issued_at=receipt.issued_at.strftime("%Y-%m-%d %H:%M:%S UTC") if receipt.issued_at else "N/A",
        transaction_ref=payment.gateway_payment_id if payment else None,
        billing_month=invoice.billing_month,
    )

    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={
            "Content-Disposition": f'attachment; filename="receipt_{receipt.receipt_number}.pdf"'
        },
    )
