import uuid
from typing import List
from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.orm import Session

import uuid
from typing import List, Optional
from fastapi import APIRouter, Depends, Query, status
import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.core.exceptions import BadRequestError, ConflictError, NotFoundError, PermissionDeniedError
from app.dependencies import (
    get_current_active_resident,
    get_current_user,
    get_db,
    require_roles,
    verify_property_access,
)
from app.models.invoice import Invoice
from app.models.payment import Payment
from app.models.property import Property
from app.models.receipt import Receipt
from app.models.resident import Resident
from app.models.user import User
from app.schemas.common import APIResponse
from app.schemas.invoice import (
    InvoiceCreate,
    InvoiceRead,
    InvoiceSummary,
    InvoiceUpdate,
    ResidentInvoiceDetail,
    ResidentInvoiceItem,
)
from app.services.audit_service import record_audit_log
from app.services.notification_service import NotificationService

router = APIRouter()


@router.post("", response_model=APIResponse[InvoiceRead], status_code=status.HTTP_201_CREATED)
def create_invoice(
    payload: InvoiceCreate,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Generates a rent, charge, or test invoice for a resident and enqueues an in-app notification."""
    verify_property_access(payload.property_id, current_user, db)

    resident = db.get(Resident, payload.resident_id)
    if not resident or resident.property_id != payload.property_id:
        raise NotFoundError("Resident not found in the specified property.")

    if payload.amount <= 0:
        raise BadRequestError("Invoice amount must be greater than zero.")

    effective_invoice_type = payload.invoice_type.strip().upper() if payload.invoice_type else "RENT"

    # Prevent duplicate invoice cycle for same resident, billing month, and type
    existing = db.scalar(
        sa.select(Invoice).where(
            Invoice.resident_id == payload.resident_id,
            Invoice.billing_month == payload.billing_month,
            Invoice.invoice_type == effective_invoice_type,
        )
    )
    if existing:
        if effective_invoice_type.startswith("TEST"):
            idx = 2
            while True:
                candidate = f"TEST_{idx}"
                conflict = db.scalar(
                    sa.select(Invoice).where(
                        Invoice.resident_id == payload.resident_id,
                        Invoice.billing_month == payload.billing_month,
                        Invoice.invoice_type == candidate,
                    )
                )
                if not conflict:
                    effective_invoice_type = candidate
                    break
                idx += 1
        else:
            raise ConflictError(
                f"An invoice of type '{payload.invoice_type}' already exists for resident in cycle '{payload.billing_month}'."
            )

    invoice_number = f"INV-{payload.billing_month.replace('-', '')}-{uuid.uuid4().hex[:8].upper()}"
    invoice = Invoice(
        property_id=payload.property_id,
        resident_id=payload.resident_id,
        invoice_number=invoice_number,
        billing_month=payload.billing_month,
        invoice_type=effective_invoice_type,
        amount=payload.amount,
        paid_amount=0.00,
        due_date=payload.due_date,
        status="PENDING",
        notes=payload.notes,
    )
    db.add(invoice)
    db.commit()
    db.refresh(invoice)

    # Enqueue in-app push notification for the resident if resident has user_id
    if resident.user_id:
        type_prefix = effective_invoice_type.replace("_", " ").title()
        NotificationService(db).dispatch(
            user_id=resident.user_id,
            title=f"{type_prefix} Invoice: {payload.billing_month}",
            body=f"Your {effective_invoice_type.lower()} invoice of ₹{float(payload.amount):,.2f} for {payload.billing_month} is due on {payload.due_date}.",
            channel="PUSH",
        )

    record_audit_log(
        db=db,
        action="CREATE_INVOICE",
        resource_type="invoices",
        user_id=current_user.id,
        user_email=current_user.email,
        user_role=current_user.role.name if current_user.role else None,
        property_id=invoice.property_id,
        resource_id=str(invoice.id),
        details={"invoice_number": invoice.invoice_number, "amount": float(invoice.amount), "due_date": str(invoice.due_date), "invoice_type": invoice.invoice_type},
    )

    return APIResponse(
        success=True,
        message=f"Invoice '{invoice.invoice_number}' created successfully.",
        data=InvoiceRead.model_validate(invoice),
    )


@router.get("/my", response_model=APIResponse[List[ResidentInvoiceItem]], status_code=status.HTTP_200_OK)
def get_my_invoices(
    status_filter: Optional[str] = Query(None, alias="status", description="Filter by status (PENDING, PAID, etc.)"),
    active_resident: Resident = Depends(get_current_active_resident),
    db: Session = Depends(get_db),
):
    """Retrieves all invoices issued to the authenticated, fully-approved resident."""
    query = sa.select(Invoice).where(Invoice.resident_id == active_resident.id)
    if status_filter:
        query = query.where(Invoice.status == status_filter.upper())
    query = query.order_by(Invoice.due_date.desc())

    invoices = db.scalars(query).all()
    items = [
        ResidentInvoiceItem(
            id=inv.id,
            invoice_number=inv.invoice_number,
            billing_month=inv.billing_month,
            invoice_type=inv.invoice_type,
            amount=float(inv.amount),
            paid_amount=float(inv.paid_amount),
            remaining_amount=max(0.0, float(inv.amount) - float(inv.paid_amount)),
            due_date=inv.due_date,
            status=inv.status,
            notes=inv.notes,
            created_at=inv.created_at,
        )
        for inv in invoices
    ]

    return APIResponse(
        success=True,
        message=f"Retrieved {len(items)} resident invoices.",
        data=items,
    )


@router.get("/{invoice_id}", response_model=APIResponse[ResidentInvoiceDetail], status_code=status.HTTP_200_OK)
def get_invoice_detail(
    invoice_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Retrieves single invoice details with resident ownership authorization."""
    invoice = db.get(Invoice, invoice_id)
    if not invoice:
        raise NotFoundError("Invoice not found.")

    resident = db.get(Resident, invoice.resident_id)
    if not resident:
        raise NotFoundError("Resident associated with invoice not found.")

    if current_user.role.name == "RESIDENT":
        if resident.user_id != current_user.id:
            raise PermissionDeniedError("Access denied. Residents can only view their own invoices.")
        if getattr(current_user, "approval_status", "APPROVED") != "APPROVED" or resident.status != "ACTIVE":
            raise PermissionDeniedError("Resident account is pending admin approval or inactive.")
    else:
        verify_property_access(invoice.property_id, current_user, db)

    property_record = db.get(Property, invoice.property_id)

    # Check for settled receipt if paid
    receipt = db.scalar(
        sa.select(Receipt).where(Receipt.invoice_id == invoice.id).order_by(Receipt.issued_at.desc())
    )
    # Check for latest payment record
    latest_payment = db.scalar(
        sa.select(Payment).where(Payment.invoice_id == invoice.id).order_by(Payment.created_at.desc())
    )

    detail = ResidentInvoiceDetail(
        id=invoice.id,
        property_id=invoice.property_id,
        property_name=property_record.name if property_record else "Unknown Property",
        resident_id=invoice.resident_id,
        resident_name=resident.user.full_name if resident.user else "Resident",
        invoice_number=invoice.invoice_number,
        billing_month=invoice.billing_month,
        invoice_type=invoice.invoice_type,
        amount=float(invoice.amount),
        paid_amount=float(invoice.paid_amount),
        remaining_amount=max(0.0, float(invoice.amount) - float(invoice.paid_amount)),
        due_date=invoice.due_date,
        status=invoice.status,
        notes=invoice.notes,
        created_at=invoice.created_at,
        receipt_id=receipt.id if receipt else None,
        receipt_number=receipt.receipt_number if receipt else None,
        gateway_order_id=latest_payment.gateway_order_id if latest_payment else None,
        paid_at=latest_payment.paid_at if latest_payment else None,
    )

    return APIResponse(
        success=True,
        message="Invoice retrieved successfully.",
        data=detail,
    )


@router.get("", response_model=APIResponse[List[InvoiceSummary]], status_code=status.HTTP_200_OK)
def list_invoices(
    property_id: uuid.UUID = Query(..., description="Property ID filter"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Lists monthly invoices for a property with resident and room metadata."""
    verify_property_access(property_id, current_user, db)
    prop = db.get(Property, property_id)
    prop_name = prop.name if prop else None

    invoices = (
        db.query(Invoice)
        .filter(Invoice.property_id == property_id)
        .order_by(Invoice.due_date.desc(), Invoice.created_at.desc())
        .all()
    )

    summaries = []
    for inv in invoices:
        res = inv.resident
        res_user = res.user if res else None
        bed = res.bed if res else None
        room = bed.room if bed else None

        summaries.append(
            InvoiceSummary(
                id=inv.id,
                invoice_number=inv.invoice_number,
                billing_month=inv.billing_month,
                invoice_type=inv.invoice_type,
                amount=float(inv.amount),
                paid_amount=float(inv.paid_amount),
                due_date=inv.due_date,
                status=inv.status,
                property_id=inv.property_id,
                property_name=prop_name,
                resident_id=inv.resident_id,
                resident_name=res_user.full_name if res_user else ("Resident" if not res else f"Resident {res.id.hex[:6]}"),
                resident_phone=res_user.phone if res_user else None,
                room_number=room.room_number if room else None,
                notes=inv.notes,
            )
        )

    return APIResponse(
        success=True,
        message=f"Retrieved {len(summaries)} invoices.",
        data=summaries,
    )


@router.get("/{invoice_id}/pdf", status_code=status.HTTP_200_OK)
def download_invoice_pdf(
    invoice_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Generates and downloads a standards-compliant PDF invoice statement."""
    from fastapi import Response
    from app.services.pdf_service import build_text_pdf

    invoice = db.get(Invoice, invoice_id)
    if not invoice:
        raise NotFoundError("Invoice not found.")

    resident = db.get(Resident, invoice.resident_id)
    if not resident:
        raise NotFoundError("Resident associated with invoice not found.")

    if current_user.role.name == "RESIDENT":
        if resident.user_id != current_user.id:
            raise PermissionDeniedError("Access denied. Residents can only download their own invoices.")
        if getattr(current_user, "approval_status", "APPROVED") != "APPROVED" or resident.status != "ACTIVE":
            raise PermissionDeniedError("Resident account is pending admin approval or inactive.")
    else:
        verify_property_access(invoice.property_id, current_user, db)

    property_record = db.get(Property, invoice.property_id)
    resident_user = resident.user
    remaining = max(0.0, float(invoice.amount) - float(invoice.paid_amount))

    lines = [
        ("SMART GROUP PG'S — INVOICE STATEMENT", 16, True),
        ("--------------------------------------------------------------------------------", 10, False),
        ("", 8, False),
        (f"Invoice Number:       {invoice.invoice_number}", 12, True),
        (f"Billing Month:        {invoice.billing_month}", 11, False),
        (f"Invoice Type:         {invoice.invoice_type}", 11, False),
        (f"Due Date:             {invoice.due_date}", 11, False),
        (f"Property:             {property_record.name if property_record else 'PG Property'}", 11, False),
        (f"Resident Name:        {resident_user.full_name if resident_user else 'Resident'}", 11, False),
        ("", 8, False),
        ("FINANCIAL BREAKDOWN", 13, True),
        ("--------------------------------------------------------------------------------", 10, False),
        (f"Total Invoiced:       INR {float(invoice.amount):,.2f}", 12, False),
        (f"Amount Paid:          INR {float(invoice.paid_amount):,.2f}", 12, False),
        (f"Balance Due:          INR {remaining:,.2f}", 13, True),
        (f"Current Status:       {invoice.status}", 12, True),
        ("", 8, False),
        ("--------------------------------------------------------------------------------", 10, False),
        ("Please pay via the PG Resident App or contact your Property Manager.", 9, False),
    ]

    pdf_bytes = build_text_pdf(lines, title=f"Invoice {invoice.invoice_number}")

    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={
            "Content-Disposition": f'attachment; filename="invoice_{invoice.invoice_number}.pdf"'
        },
    )


@router.patch("/{invoice_id}", response_model=APIResponse[InvoiceRead], status_code=status.HTTP_200_OK)
def update_invoice(
    invoice_id: uuid.UUID,
    payload: InvoiceUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Updates an invoice's due date, notes, or status."""
    invoice = db.get(Invoice, invoice_id)
    if not invoice:
        raise NotFoundError("Invoice not found.")

    verify_property_access(invoice.property_id, current_user, db)

    update_data = payload.model_dump(exclude_unset=True)
    if not update_data:
        return APIResponse(
            success=True,
            message="No changes requested.",
            data=InvoiceRead.model_validate(invoice),
        )

    if "status" in update_data and update_data["status"]:
        new_status = update_data["status"].upper()
        if new_status == "CANCELLED" and float(invoice.paid_amount) > 0:
            raise ConflictError("Cannot cancel an invoice with recorded payments.")
        invoice.status = new_status

    if "due_date" in update_data and update_data["due_date"]:
        invoice.due_date = update_data["due_date"]

    if "notes" in update_data:
        invoice.notes = update_data["notes"]

    record_audit_log(
        db=db,
        action="UPDATE_INVOICE",
        resource_type="invoices",
        user_id=current_user.id,
        user_email=current_user.email,
        user_role=current_user.role.name if current_user.role else None,
        property_id=invoice.property_id,
        resource_id=str(invoice.id),
        details={"updated_fields": list(update_data.keys())},
    )

    db.commit()
    db.refresh(invoice)

    return APIResponse(
        success=True,
        message="Invoice updated successfully.",
        data=InvoiceRead.model_validate(invoice),
    )

