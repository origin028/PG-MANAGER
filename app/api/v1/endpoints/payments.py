import uuid
from typing import List, Optional
from fastapi import APIRouter, Depends, Query, Request, status
from sqlalchemy.orm import Session

from app.api.deps import get_current_user, get_db
from app.models.user import User
from app.schemas.common import APIResponse
from app.schemas.payment import (
    PaymentCreate,
    PaymentDetail,
    PaymentRefundRequest,
)
from app.services.invoice_service import (
    get_payment_detail,
    list_payments,
    record_payment,
    refund_payment,
)

router = APIRouter()


@router.get("", response_model=APIResponse[List[PaymentDetail]], status_code=status.HTTP_200_OK)
def get_payments(
    property_id: Optional[uuid.UUID] = Query(None, description="Filter by property ID"),
    resident_id: Optional[uuid.UUID] = Query(None, description="Filter by resident ID"),
    invoice_id: Optional[uuid.UUID] = Query(None, description="Filter by invoice ID"),
    status_filter: Optional[str] = Query(None, alias="status", description="Filter by status (COMPLETED, REFUNDED, FAILED)"),
    payment_method: Optional[str] = Query(None, description="Filter by payment method (UPI, CASH, BANK_TRANSFER, CARD, OTHER)"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    List payments accessible to the authenticated user.
    - Super Admin: All company payments or filtered by property.
    - Property Manager / Staff: Only payments for assigned properties.
    - Resident: Only their own payments.
    """
    payments = list_payments(
        db=db,
        user=current_user,
        property_id=property_id,
        resident_id=resident_id,
        invoice_id=invoice_id,
        status_filter=status_filter,
        payment_method=payment_method,
    )
    return APIResponse(
        success=True,
        message=f"Retrieved {len(payments)} payments.",
        data=payments,
    )


@router.post("", response_model=APIResponse[PaymentDetail], status_code=status.HTTP_201_CREATED)
def record_new_payment(
    payload: PaymentCreate,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Record a rent or charge payment against an invoice.
    Uses exclusive row-locking on the invoice to guarantee exact balance tracking and prevent overpayments.
    Accessible to Super Admin, Property Managers, and Staff for their assigned properties.
    """
    ip_address = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")

    payment = record_payment(
        db=db,
        data=payload,
        user=current_user,
        ip_address=ip_address,
        user_agent=user_agent,
    )
    return APIResponse(
        success=True,
        message=f"Payment '{payment.payment_number}' of ₹{payment.amount} recorded successfully.",
        data=payment,
    )


@router.get("/me", response_model=APIResponse[List[PaymentDetail]], status_code=status.HTTP_200_OK)
def get_my_payments(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Retrieve all payment receipts belonging to the authenticated resident.
    Accessible to Resident Mobile app users.
    """
    payments = list_payments(
        db=db,
        user=current_user,
    )
    return APIResponse(
        success=True,
        message=f"Retrieved {len(payments)} resident payment records.",
        data=payments,
    )


@router.get("/{payment_id}", response_model=APIResponse[PaymentDetail], status_code=status.HTTP_200_OK)
def get_single_payment(
    payment_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Retrieve details of a single payment receipt.
    """
    payment = get_payment_detail(db=db, payment_id=payment_id, user=current_user)
    return APIResponse(
        success=True,
        message="Payment details retrieved successfully.",
        data=payment,
    )


@router.post("/{payment_id}/refund", response_model=APIResponse[PaymentDetail], status_code=status.HTTP_200_OK)
def refund_single_payment(
    payment_id: uuid.UUID,
    request: Request,
    payload: Optional[PaymentRefundRequest] = None,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Refund a completed payment and safely reinstate the outstanding balance on the invoice.
    Restricted to Super Admin and Property Managers for their assigned properties.
    """
    ip_address = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")
    reason = payload.reason if payload else None

    payment = refund_payment(
        db=db,
        payment_id=payment_id,
        user=current_user,
        reason=reason,
        ip_address=ip_address,
        user_agent=user_agent,
    )
    return APIResponse(
        success=True,
        message=f"Payment '{payment.payment_number}' refunded successfully.",
        data=payment,
    )
