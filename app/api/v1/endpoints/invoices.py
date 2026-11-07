import uuid
from typing import List, Optional
from fastapi import APIRouter, Depends, Query, Request, status
from sqlalchemy.orm import Session

from app.api.deps import get_current_user, get_db
from app.models.user import User
from app.schemas.common import APIResponse
from app.schemas.invoice import (
    InvoiceCreate,
    InvoiceDetail,
    InvoiceSummary,
)
from app.services.invoice_service import (
    cancel_invoice,
    create_invoice,
    get_financial_summary,
    get_invoice_detail,
    issue_draft_invoice,
    list_invoices,
)

router = APIRouter()


@router.get("", response_model=APIResponse[List[InvoiceDetail]], status_code=status.HTTP_200_OK)
def get_invoices(
    property_id: Optional[uuid.UUID] = Query(None, description="Filter by property ID"),
    resident_id: Optional[uuid.UUID] = Query(None, description="Filter by resident ID"),
    billing_month: Optional[str] = Query(None, description="Filter by billing month (YYYY-MM)"),
    status_filter: Optional[str] = Query(None, alias="status", description="Filter by status (DRAFT, ISSUED, PARTIALLY_PAID, PAID, CANCELLED, OVERDUE)"),
    invoice_type: Optional[str] = Query(None, description="Filter by invoice type (RENT, SECURITY_DEPOSIT, MAINTENANCE, PENALTY)"),
    is_overdue: Optional[bool] = Query(None, description="Filter invoices that are overdue"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    List invoices accessible to the authenticated user.
    - Super Admin: All company invoices or filtered by property.
    - Property Manager / Staff: Only invoices for assigned properties.
    - Resident: Only their own invoices (excluding drafts).
    """
    invoices = list_invoices(
        db=db,
        user=current_user,
        property_id=property_id,
        resident_id=resident_id,
        billing_month=billing_month,
        status_filter=status_filter,
        invoice_type=invoice_type,
        is_overdue=is_overdue,
    )
    return APIResponse(
        success=True,
        message=f"Retrieved {len(invoices)} invoices.",
        data=invoices,
    )


@router.post("", response_model=APIResponse[InvoiceDetail], status_code=status.HTTP_201_CREATED)
def create_new_invoice(
    payload: InvoiceCreate,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Create a new invoice for a resident.
    Can be created as DRAFT or directly ISSUED.
    Restricted to Super Admin and Property Managers for their assigned properties.
    """
    ip_address = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")

    invoice = create_invoice(
        db=db,
        data=payload,
        user=current_user,
        ip_address=ip_address,
        user_agent=user_agent,
    )
    return APIResponse(
        success=True,
        message=f"Invoice '{invoice.invoice_number}' created successfully with status '{invoice.status}'.",
        data=invoice,
    )


@router.get("/summary", response_model=APIResponse[InvoiceSummary], status_code=status.HTTP_200_OK)
def get_invoices_summary(
    property_id: Optional[uuid.UUID] = Query(None, description="Optional property ID to scope summary"),
    billing_month: Optional[str] = Query(None, description="Optional billing month (YYYY-MM)"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Retrieve financial billing and collection summary without double-counting.
    Provides portfolio totals and per-property breakdowns.
    Restricted to Super Admin and Property Managers for their assigned properties.
    """
    summary = get_financial_summary(
        db=db,
        user=current_user,
        property_id=property_id,
        billing_month=billing_month,
    )
    return APIResponse(
        success=True,
        message="Financial summary computed successfully.",
        data=summary,
    )


@router.get("/me", response_model=APIResponse[List[InvoiceDetail]], status_code=status.HTTP_200_OK)
def get_my_invoices(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Retrieve all invoices belonging to the authenticated resident.
    Accessible to Resident Mobile app users.
    """
    invoices = list_invoices(
        db=db,
        user=current_user,
    )
    return APIResponse(
        success=True,
        message=f"Retrieved {len(invoices)} resident invoices.",
        data=invoices,
    )


@router.get("/{invoice_id}", response_model=APIResponse[InvoiceDetail], status_code=status.HTTP_200_OK)
def get_single_invoice(
    invoice_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Retrieve details of a single invoice including payment history.
    """
    invoice = get_invoice_detail(db=db, invoice_id=invoice_id, user=current_user)
    return APIResponse(
        success=True,
        message="Invoice details retrieved successfully.",
        data=invoice,
    )


@router.post("/{invoice_id}/issue", response_model=APIResponse[InvoiceDetail], status_code=status.HTTP_200_OK)
def issue_invoice(
    invoice_id: uuid.UUID,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Issue a draft invoice, making it payable and visible to the resident.
    Restricted to Super Admin and Property Managers.
    """
    ip_address = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")

    invoice = issue_draft_invoice(
        db=db,
        invoice_id=invoice_id,
        user=current_user,
        ip_address=ip_address,
        user_agent=user_agent,
    )
    return APIResponse(
        success=True,
        message=f"Invoice '{invoice.invoice_number}' issued successfully.",
        data=invoice,
    )


@router.post("/{invoice_id}/cancel", response_model=APIResponse[InvoiceDetail], status_code=status.HTTP_200_OK)
def cancel_single_invoice(
    invoice_id: uuid.UUID,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Cancel an uncollected invoice. Cannot cancel if payments were recorded.
    Restricted to Super Admin and Property Managers.
    """
    ip_address = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")

    invoice = cancel_invoice(
        db=db,
        invoice_id=invoice_id,
        user=current_user,
        ip_address=ip_address,
        user_agent=user_agent,
    )
    return APIResponse(
        success=True,
        message=f"Invoice '{invoice.invoice_number}' cancelled successfully.",
        data=invoice,
    )


from pydantic import BaseModel, Field, field_validator
from decimal import Decimal
from datetime import date


PAYMENT_METHOD_ALIASES = {
    "CASH": "CASH",
    "UPI": "UPI",
    "BANK TRANSFER": "BANK_TRANSFER",
    "BANK_TRANSFER": "BANK_TRANSFER",
    "BANKTRANSFER": "BANK_TRANSFER",
}


class RecordPaymentRequest(BaseModel):
    amount: Decimal = Field(..., gt=0, description="Payment amount, must be greater than zero")
    payment_method: str = Field(..., description="Cash, UPI, or Bank Transfer")
    date: date

    @field_validator("payment_method")
    @classmethod
    def _normalize_method(cls, value: str) -> str:
        key = " ".join(value.strip().upper().replace("_", " ").split())
        normalized = PAYMENT_METHOD_ALIASES.get(key)
        if not normalized:
            raise ValueError("payment_method must be one of: Cash, UPI, Bank Transfer")
        return normalized


@router.post("/{invoice_id}/record-payment", status_code=status.HTTP_200_OK)
def record_payment_on_invoice(
    invoice_id: uuid.UUID,
    payload: RecordPaymentRequest,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Records a payment against an invoice using the ledger rules of the payment service.

    A partial payment leaves the invoice PARTIALLY_PAID; only a payment that settles
    the full outstanding balance marks the invoice as PAID.
    """
    from app.schemas.payment import PaymentCreate
    from app.services.invoice_service import record_payment

    ip_address = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")

    payment_data = PaymentCreate(
        invoice_id=invoice_id,
        amount=payload.amount,
        payment_method=payload.payment_method,
        payment_date=payload.date,
    )
    payment = record_payment(
        db=db,
        data=payment_data,
        user=current_user,
        ip_address=ip_address,
        user_agent=user_agent,
    )
    return APIResponse(
        success=True,
        message=f"Payment '{payment.payment_number}' recorded successfully.",
        data=payment,
    )


class AdjustInvoiceRequest(BaseModel):
    new_amount: Decimal = Field(..., gt=0, description="New invoice total amount")
    reason: str = Field(..., min_length=3, max_length=255)


@router.put("/{invoice_id}/adjust", response_model=APIResponse[InvoiceDetail], status_code=status.HTTP_200_OK)
def adjust_existing_invoice(
    invoice_id: uuid.UUID,
    payload: AdjustInvoiceRequest,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Adjusts an invoice total, preserving the previous amount in the audit trail."""
    from app.services.invoice_service import adjust_invoice

    invoice = adjust_invoice(
        db=db,
        invoice_id=invoice_id,
        new_amount=payload.new_amount,
        reason=payload.reason,
        user=current_user,
        ip_address=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent"),
    )
    return APIResponse(success=True, message="Invoice adjusted successfully.", data=invoice)


@router.get("/{invoice_id}/receipt", status_code=status.HTTP_200_OK)
def get_invoice_receipt(
    invoice_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Returns a PDF receipt for an authorized invoice."""
    from fastapi.responses import Response
    from app.services.invoice_service import get_invoice_detail
    from app.services.pdf_service import build_receipt_pdf

    invoice = get_invoice_detail(db=db, invoice_id=invoice_id, user=current_user)
    content = build_receipt_pdf(invoice, payments=invoice.payments)
    filename = f"receipt-{invoice.invoice_number}.pdf"
    return Response(
        content=content,
        media_type="application/pdf",
        headers={
            "Content-Disposition": f'attachment; filename="{filename}"',
            "Content-Length": str(len(content)),
        },
    )


