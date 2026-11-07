import uuid
from calendar import monthrange
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
from typing import List, Optional
import sqlalchemy as sa
from sqlalchemy.orm import Session, joinedload

from app.core.exceptions import ConflictError, NotFoundError, PermissionDeniedError, ValidationError
from app.models.invoice import Invoice
from app.models.payment import Payment
from app.models.property import Property
from app.models.resident import Resident
from app.models.user import User, UserPropertyAccess
from app.schemas.invoice import (
    InvoiceCreate,
    InvoiceDetail,
    InvoiceSummary,
    InvoiceUpdate,
    PropertyFinancialSummary,
)
from app.schemas.payment import (
    PaymentCreate,
    PaymentDetail,
    PaymentRead,
)
from app.services.audit_service import record_audit_log


def _get_permitted_property_ids(
    db: Session, user: User, target_property_id: Optional[uuid.UUID] = None
) -> List[uuid.UUID]:
    """
    Returns list of property IDs the user is authorized to access for financial operations.
    """
    if user.role.name == "RESIDENT":
        raise PermissionDeniedError("Residents are not authorized for administrative financial operations.")

    if user.role.name == "SUPER_ADMIN":
        if target_property_id:
            prop = db.scalar(
                sa.select(Property).where(
                    Property.id == target_property_id,
                    Property.company_id == user.company_id,
                )
            )
            if not prop:
                raise NotFoundError(f"Property with ID '{target_property_id}' not found.")
            return [target_property_id]
        else:
            props = db.scalars(
                sa.select(Property.id).where(
                    Property.company_id == user.company_id,
                    Property.is_active == True,
                )
            ).all()
            return list(props)

    # For PROPERTY_MANAGER and STAFF
    assigned_query = sa.select(UserPropertyAccess.property_id).where(
        UserPropertyAccess.user_id == user.id
    )
    assigned_ids = list(db.scalars(assigned_query).all())

    if target_property_id:
        if target_property_id not in assigned_ids:
            raise PermissionDeniedError(
                f"You do not have access rights for property ID '{target_property_id}'."
            )
        return [target_property_id]

    return assigned_ids


def generate_invoice_number(property_code: str, billing_month: str) -> str:
    cleaned_month = billing_month.replace("-", "")
    suffix = uuid.uuid4().hex[:6].upper()
    return f"INV-{property_code}-{cleaned_month}-{suffix}"


def generate_payment_number(property_code: str) -> str:
    month_prefix = datetime.now(timezone.utc).strftime("%Y%m")
    suffix = uuid.uuid4().hex[:6].upper()
    return f"PAY-{property_code}-{month_prefix}-{suffix}"


def build_initial_rent_invoice(
    db: Session,
    resident: Resident,
    user: User,
    check_in_date: Optional[date] = None,
) -> Optional[Invoice]:
    """Creates (but does not commit) the first rent invoice for a new resident.

    The invoice is generated for the calendar month of check-in using the
    resident's agreed monthly rent. An invoice is only created when a positive
    rent is configured and no active RENT invoice exists for that month, which
    keeps check-in idempotent and avoids duplicate billing.
    """
    effective_date = check_in_date or resident.check_in_date or date.today()
    billing_month = effective_date.strftime("%Y-%m")

    monthly_rent = Decimal(str(resident.monthly_rent or 0))
    if monthly_rent <= Decimal("0.00"):
        return None

    existing = db.scalar(
        sa.select(Invoice).where(
            Invoice.resident_id == resident.id,
            Invoice.billing_month == billing_month,
            Invoice.invoice_type == "RENT",
            Invoice.status != "CANCELLED",
        )
    )
    if existing:
        return None

    prop = db.scalar(sa.select(Property).where(Property.id == resident.property_id))
    period_start = effective_date.replace(day=1)
    period_end = effective_date.replace(
        day=monthrange(effective_date.year, effective_date.month)[1]
    )
    due_date = min(effective_date + timedelta(days=7), period_end)

    invoice = Invoice(
        company_id=resident.company_id,
        property_id=resident.property_id,
        resident_id=resident.id,
        invoice_number=generate_invoice_number(
            prop.code if prop else "PG", billing_month
        ),
        billing_month=billing_month,
        billing_period_start=period_start,
        billing_period_end=period_end,
        issue_date=effective_date,
        due_date=due_date,
        invoice_type="RENT",
        rent_amount=monthly_rent,
        additional_charges=Decimal("0.00"),
        discount_amount=Decimal("0.00"),
        total_amount=monthly_rent,
        paid_amount=Decimal("0.00"),
        balance_amount=monthly_rent,
        status="ISSUED",
        notes="Initial rent invoice generated on check-in.",
    )
    db.add(invoice)
    return invoice


def _build_payment_read(p: Payment) -> PaymentRead:
    return PaymentRead(
        id=p.id,
        company_id=p.company_id,
        property_id=p.property_id,
        invoice_id=p.invoice_id,
        resident_id=p.resident_id,
        payment_number=p.payment_number,
        amount=p.amount,
        payment_method=p.payment_method,
        transaction_reference=p.transaction_reference,
        status=p.status,
        recorded_by_user_id=p.recorded_by_user_id,
        payment_date=p.payment_date,
        paid_at=p.paid_at,
        notes=p.notes,
        created_at=p.created_at,
        updated_at=p.updated_at,
    )


def _build_payment_detail(p: Payment) -> PaymentDetail:
    read_data = _build_payment_read(p)
    return PaymentDetail(
        **read_data.model_dump(),
        property_name=p.property.name if p.property else None,
        resident_name=p.resident.full_name if p.resident else None,
        invoice_number=p.invoice.invoice_number if p.invoice else None,
        recorded_by_name=p.recorded_by.full_name if p.recorded_by else None,
    )


def _build_invoice_detail(inv: Invoice) -> InvoiceDetail:
    payments_data = [_build_payment_read(p) for p in inv.payments] if inv.payments else []
    room_num = inv.resident.room.room_number if inv.resident and inv.resident.room else None
    bed_num = inv.resident.bed.bed_number if inv.resident and inv.resident.bed else None

    # Check overdue status on-the-fly for reporting
    effective_status = inv.status
    if effective_status in ["ISSUED", "PARTIALLY_PAID"] and inv.due_date < date.today():
        effective_status = "OVERDUE"

    return InvoiceDetail(
        id=inv.id,
        company_id=inv.company_id,
        property_id=inv.property_id,
        resident_id=inv.resident_id,
        invoice_number=inv.invoice_number,
        billing_month=inv.billing_month,
        billing_period_start=inv.billing_period_start,
        billing_period_end=inv.billing_period_end,
        issue_date=inv.issue_date,
        due_date=inv.due_date,
        invoice_type=inv.invoice_type,
        rent_amount=inv.rent_amount,
        additional_charges=inv.additional_charges,
        discount_amount=inv.discount_amount,
        total_amount=inv.total_amount,
        paid_amount=inv.paid_amount,
        balance_amount=inv.balance_amount,
        status=effective_status,
        notes=inv.notes,
        created_at=inv.created_at,
        updated_at=inv.updated_at,
        property_name=inv.property.name if inv.property else None,
        resident_name=inv.resident.full_name if inv.resident else None,
        room_number=room_num,
        bed_number=bed_num,
        payments=payments_data,
    )


def create_invoice(
    db: Session,
    data: InvoiceCreate,
    user: User,
    ip_address: Optional[str] = None,
    user_agent: Optional[str] = None,
) -> InvoiceDetail:
    if user.role.name not in ["SUPER_ADMIN", "PROPERTY_MANAGER"]:
        raise PermissionDeniedError("Only Super Admins and Property Managers can create invoices.")

    _get_permitted_property_ids(db, user, data.property_id)

    # 1. Load resident and verify property affiliation
    resident = db.scalar(sa.select(Resident).where(Resident.id == data.resident_id))
    if not resident:
        raise NotFoundError(f"Resident with ID '{data.resident_id}' not found.")

    if resident.property_id != data.property_id:
        raise ConflictError(
            f"Property mismatch: Resident '{resident.full_name}' belongs to property "
            f"'{resident.property_id}', but invoice specifies property '{data.property_id}'."
        )

    # 2. Check duplicate invoice for the same resident, billing month, and type
    existing = db.scalar(
        sa.select(Invoice).where(
            Invoice.resident_id == data.resident_id,
            Invoice.billing_month == data.billing_month,
            Invoice.invoice_type == data.invoice_type.upper(),
            Invoice.status != "CANCELLED",
        )
    )
    if existing:
        raise ConflictError(
            f"An active invoice of type '{data.invoice_type.upper()}' already exists for "
            f"resident '{resident.full_name}' for billing month '{data.billing_month}'."
        )

    # 3. Exact decimal financial calculations
    rent_amt = Decimal(str(data.rent_amount))
    addon_amt = Decimal(str(data.additional_charges))
    disc_amt = Decimal(str(data.discount_amount))
    total_amt = rent_amt + addon_amt - disc_amt
    if total_amt < Decimal("0.00"):
        raise ValidationError("Total invoice amount cannot be negative.")

    prop = db.scalar(sa.select(Property).where(Property.id == data.property_id))
    inv_number = generate_invoice_number(prop.code if prop else "PG", data.billing_month)

    status_val = "DRAFT" if data.is_draft else "ISSUED"

    invoice = Invoice(
        company_id=user.company_id,
        property_id=data.property_id,
        resident_id=data.resident_id,
        invoice_number=inv_number,
        billing_month=data.billing_month,
        billing_period_start=data.billing_period_start,
        billing_period_end=data.billing_period_end,
        issue_date=data.issue_date,
        due_date=data.due_date,
        invoice_type=data.invoice_type.upper(),
        rent_amount=rent_amt,
        additional_charges=addon_amt,
        discount_amount=disc_amt,
        total_amount=total_amt,
        paid_amount=Decimal("0.00"),
        balance_amount=total_amt,
        status=status_val,
        notes=data.notes,
    )
    db.add(invoice)
    db.commit()
    db.refresh(invoice)

    record_audit_log(
        db=db,
        action="INVOICE_CREATED",
        resource_type="invoice",
        resource_id=str(invoice.id),
        user_id=user.id,
        user_email=user.email,
        user_role=user.role.name,
        company_id=invoice.company_id,
        property_id=invoice.property_id,
        details={
            "invoice_number": invoice.invoice_number,
            "resident_name": resident.full_name,
            "total_amount": str(invoice.total_amount),
            "status": invoice.status,
        },
        ip_address=ip_address,
        user_agent=user_agent,
    )

    return get_invoice_detail(db=db, invoice_id=invoice.id, user=user)


def list_invoices(
    db: Session,
    user: User,
    property_id: Optional[uuid.UUID] = None,
    resident_id: Optional[uuid.UUID] = None,
    billing_month: Optional[str] = None,
    status_filter: Optional[str] = None,
    invoice_type: Optional[str] = None,
    is_overdue: Optional[bool] = None,
) -> List[InvoiceDetail]:
    # Resident self-scoping
    if user.role.name == "RESIDENT":
        resident = db.scalar(
            sa.select(Resident).where(
                sa.or_(Resident.user_id == user.id, Resident.phone == user.phone)
            )
        )
        if not resident:
            return []
        stmt = (
            sa.select(Invoice)
            .options(
                joinedload(Invoice.property),
                joinedload(Invoice.resident).joinedload(Resident.room),
                joinedload(Invoice.resident).joinedload(Resident.bed),
                joinedload(Invoice.payments),
            )
            .where(Invoice.resident_id == resident.id, Invoice.status != "DRAFT")
        )
    else:
        permitted_ids = _get_permitted_property_ids(db, user, property_id)
        if not permitted_ids:
            return []
        stmt = (
            sa.select(Invoice)
            .options(
                joinedload(Invoice.property),
                joinedload(Invoice.resident).joinedload(Resident.room),
                joinedload(Invoice.resident).joinedload(Resident.bed),
                joinedload(Invoice.payments),
            )
            .where(Invoice.property_id.in_(permitted_ids))
        )
        if resident_id:
            stmt = stmt.where(Invoice.resident_id == resident_id)

    if billing_month:
        stmt = stmt.where(Invoice.billing_month == billing_month)
    if status_filter:
        if status_filter.upper() == "OVERDUE":
            stmt = stmt.where(
                Invoice.status.in_(["ISSUED", "PARTIALLY_PAID"]),
                Invoice.due_date < date.today(),
            )
        else:
            stmt = stmt.where(Invoice.status == status_filter.upper())
    if invoice_type:
        stmt = stmt.where(Invoice.invoice_type == invoice_type.upper())
    if is_overdue is True:
        stmt = stmt.where(
            Invoice.status.in_(["ISSUED", "PARTIALLY_PAID"]),
            Invoice.due_date < date.today(),
        )

    stmt = stmt.order_by(Invoice.issue_date.desc(), Invoice.created_at.desc())
    invoices = db.scalars(stmt).unique().all()
    return [_build_invoice_detail(inv) for inv in invoices]


def get_invoice_detail(db: Session, invoice_id: uuid.UUID, user: User) -> InvoiceDetail:
    stmt = (
        sa.select(Invoice)
        .options(
            joinedload(Invoice.property),
            joinedload(Invoice.resident).joinedload(Resident.room),
            joinedload(Invoice.resident).joinedload(Resident.bed),
            joinedload(Invoice.payments),
        )
        .where(Invoice.id == invoice_id)
    )
    invoice = db.scalar(stmt)
    if not invoice:
        raise NotFoundError(f"Invoice with ID '{invoice_id}' not found.")

    if user.role.name == "RESIDENT":
        if (
            invoice.resident.user_id != user.id
            and invoice.resident.phone != user.phone
        ):
            raise PermissionDeniedError("Residents can only access their own invoices.")
        if invoice.status == "DRAFT":
            raise NotFoundError(f"Invoice with ID '{invoice_id}' not found.")
        return _build_invoice_detail(invoice)

    _get_permitted_property_ids(db, user, invoice.property_id)
    return _build_invoice_detail(invoice)


def issue_draft_invoice(
    db: Session,
    invoice_id: uuid.UUID,
    user: User,
    ip_address: Optional[str] = None,
    user_agent: Optional[str] = None,
) -> InvoiceDetail:
    if user.role.name not in ["SUPER_ADMIN", "PROPERTY_MANAGER"]:
        raise PermissionDeniedError("Only Super Admins and Property Managers can issue invoices.")

    invoice = db.scalar(
        sa.select(Invoice).where(Invoice.id == invoice_id).with_for_update()
    )
    if not invoice:
        raise NotFoundError(f"Invoice with ID '{invoice_id}' not found.")

    _get_permitted_property_ids(db, user, invoice.property_id)

    if invoice.status != "DRAFT":
        raise ConflictError(
            f"Cannot issue invoice in '{invoice.status}' status (must be DRAFT)."
        )

    invoice.status = "ISSUED"
    db.commit()
    db.refresh(invoice)

    record_audit_log(
        db=db,
        action="INVOICE_ISSUED",
        resource_type="invoice",
        resource_id=str(invoice.id),
        user_id=user.id,
        user_email=user.email,
        user_role=user.role.name,
        company_id=invoice.company_id,
        property_id=invoice.property_id,
        details={"invoice_number": invoice.invoice_number, "total_amount": str(invoice.total_amount)},
        ip_address=ip_address,
        user_agent=user_agent,
    )

    return get_invoice_detail(db=db, invoice_id=invoice.id, user=user)


def cancel_invoice(
    db: Session,
    invoice_id: uuid.UUID,
    user: User,
    ip_address: Optional[str] = None,
    user_agent: Optional[str] = None,
) -> InvoiceDetail:
    if user.role.name not in ["SUPER_ADMIN", "PROPERTY_MANAGER"]:
        raise PermissionDeniedError("Only Super Admins and Property Managers can cancel invoices.")

    invoice = db.scalar(
        sa.select(Invoice).where(Invoice.id == invoice_id).with_for_update()
    )
    if not invoice:
        raise NotFoundError(f"Invoice with ID '{invoice_id}' not found.")

    _get_permitted_property_ids(db, user, invoice.property_id)

    if invoice.status == "CANCELLED":
        raise ConflictError("Invoice is already cancelled.")

    if invoice.paid_amount > Decimal("0.00"):
        raise ConflictError(
            f"Cannot cancel invoice '{invoice.invoice_number}' with recorded payments (₹{invoice.paid_amount}). "
            f"Recorded payments must be refunded or settled first."
        )

    invoice.status = "CANCELLED"
    db.commit()
    db.refresh(invoice)

    record_audit_log(
        db=db,
        action="INVOICE_CANCELLED",
        resource_type="invoice",
        resource_id=str(invoice.id),
        user_id=user.id,
        user_email=user.email,
        user_role=user.role.name,
        company_id=invoice.company_id,
        property_id=invoice.property_id,
        details={"invoice_number": invoice.invoice_number},
        ip_address=ip_address,
        user_agent=user_agent,
    )

    return get_invoice_detail(db=db, invoice_id=invoice.id, user=user)


def adjust_invoice(
    db: Session,
    invoice_id: uuid.UUID,
    new_amount: Decimal,
    reason: str,
    user: User,
    ip_address: Optional[str] = None,
    user_agent: Optional[str] = None,
) -> InvoiceDetail:
    """Adjusts the total amount of an invoice while preserving financial history.

    Rules:
    - Only Super Admins and Property Managers may adjust invoices.
    - The invoice row is locked to avoid concurrent balance corruption.
    - Cancelled invoices cannot be adjusted.
    - The new total must be positive and cannot be lower than amounts already paid.
    - The previous amount and the reason are persisted in the audit trail.
    """
    if user.role.name not in ["SUPER_ADMIN", "PROPERTY_MANAGER"]:
        raise PermissionDeniedError("Only Super Admins and Property Managers can adjust invoices.")

    cleaned_reason = (reason or "").strip()
    if len(cleaned_reason) < 3:
        raise ValidationError("An adjustment reason of at least 3 characters is required.")

    if new_amount is None:
        raise ValidationError("A new invoice amount is required.")

    adjusted_amount = Decimal(str(new_amount))
    if adjusted_amount <= Decimal("0.00"):
        raise ValidationError("Adjusted invoice amount must be strictly greater than zero.")

    invoice = db.scalar(
        sa.select(Invoice).where(Invoice.id == invoice_id).with_for_update()
    )
    if not invoice:
        raise NotFoundError(f"Invoice with ID '{invoice_id}' not found.")

    _get_permitted_property_ids(db, user, invoice.property_id)

    if invoice.status == "CANCELLED":
        raise ConflictError("Cannot adjust a cancelled invoice.")

    paid_amount = invoice.paid_amount or Decimal("0.00")
    if adjusted_amount < paid_amount:
        raise ConflictError(
            f"Adjusted amount ₹{adjusted_amount:.2f} is lower than already collected "
            f"payments ₹{paid_amount:.2f}; refund the difference first."
        )

    previous_amount = invoice.total_amount
    invoice.total_amount = adjusted_amount
    invoice.balance_amount = adjusted_amount - paid_amount

    if invoice.balance_amount == Decimal("0.00"):
        invoice.status = "PAID"
    elif paid_amount > Decimal("0.00"):
        invoice.status = "PARTIALLY_PAID"
    elif invoice.due_date < date.today():
        invoice.status = "OVERDUE"
    else:
        invoice.status = "ISSUED"

    db.add(invoice)
    db.commit()
    db.refresh(invoice)

    record_audit_log(
        db=db,
        action="INVOICE_ADJUSTED",
        resource_type="invoice",
        resource_id=str(invoice.id),
        user_id=user.id,
        user_email=user.email,
        user_role=user.role.name,
        company_id=invoice.company_id,
        property_id=invoice.property_id,
        details={
            "invoice_number": invoice.invoice_number,
            "previous_amount": str(previous_amount),
            "new_amount": str(adjusted_amount),
            "paid_amount": str(paid_amount),
            "balance_amount": str(invoice.balance_amount),
            "reason": cleaned_reason,
        },
        ip_address=ip_address,
        user_agent=user_agent,
    )

    return get_invoice_detail(db=db, invoice_id=invoice.id, user=user)


def record_payment(
    db: Session,
    data: PaymentCreate,
    user: User,
    ip_address: Optional[str] = None,
    user_agent: Optional[str] = None,
) -> PaymentDetail:
    """
    Concurrency-safe payment recording with row-level locking on the parent Invoice.
    Enforces exact balance updates, overpayment prevention, and idempotent reference protection.
    """
    if user.role.name not in ["SUPER_ADMIN", "PROPERTY_MANAGER", "STAFF"]:
        raise PermissionDeniedError("You are not authorized to record payments.")

    try:
        # 1. Acquire exclusive row lock on Invoice
        invoice = db.scalar(
            sa.select(Invoice)
            .where(Invoice.id == data.invoice_id)
            .with_for_update()
        )
        if not invoice:
            raise NotFoundError(f"Invoice with ID '{data.invoice_id}' not found.")

        _get_permitted_property_ids(db, user, invoice.property_id)

        # 2. State & Balance validations
        if invoice.status == "CANCELLED":
            raise ConflictError("Cannot record payment against a cancelled invoice.")

        if invoice.status == "DRAFT":
            raise ConflictError("Cannot record payment against an unissued draft invoice.")

        if invoice.status == "PAID" or invoice.balance_amount <= Decimal("0.00"):
            raise ConflictError("Invoice is already fully settled and paid.")

        payment_amt = Decimal(str(data.amount))
        if payment_amt <= Decimal("0.00"):
            raise ValidationError("Payment amount must be strictly greater than zero.")

        if payment_amt > invoice.balance_amount:
            raise ConflictError(
                f"Payment amount ₹{payment_amt:.2f} exceeds outstanding invoice balance of ₹{invoice.balance_amount:.2f}."
            )

        # 3. Duplicate transaction reference check
        if data.transaction_reference and data.transaction_reference.strip():
            existing_ref = db.scalar(
                sa.select(Payment).where(
                    Payment.transaction_reference == data.transaction_reference.strip()
                )
            )
            if existing_ref:
                raise ConflictError(
                    f"A payment with transaction reference '{data.transaction_reference.strip()}' has already been recorded."
                )

        # 4. Generate payment number
        prop_code = invoice.property.code if invoice.property else "PG"
        pay_number = generate_payment_number(prop_code)

        # 5. Create Payment record
        payment = Payment(
            company_id=invoice.company_id,
            property_id=invoice.property_id,
            invoice_id=invoice.id,
            resident_id=invoice.resident_id,
            payment_number=pay_number,
            amount=payment_amt,
            payment_method=data.payment_method.upper(),
            transaction_reference=data.transaction_reference.strip() if data.transaction_reference else None,
            status="COMPLETED",
            recorded_by_user_id=user.id,
            payment_date=data.payment_date or date.today(),
            notes=data.notes,
        )
        db.add(payment)

        # 6. Atomically update invoice balance
        invoice.paid_amount = invoice.paid_amount + payment_amt
        invoice.balance_amount = invoice.total_amount - invoice.paid_amount
        if invoice.balance_amount == Decimal("0.00"):
            invoice.status = "PAID"
        else:
            invoice.status = "PARTIALLY_PAID"

        db.commit()
        db.refresh(payment)
        db.refresh(invoice)

        record_audit_log(
            db=db,
            action="PAYMENT_RECORDED",
            resource_type="payment",
            resource_id=str(payment.id),
            user_id=user.id,
            user_email=user.email,
            user_role=user.role.name,
            company_id=payment.company_id,
            property_id=payment.property_id,
            details={
                "payment_number": payment.payment_number,
                "invoice_number": invoice.invoice_number,
                "amount": str(payment.amount),
                "remaining_balance": str(invoice.balance_amount),
            },
            ip_address=ip_address,
            user_agent=user_agent,
        )

        return get_payment_detail(db=db, payment_id=payment.id, user=user)
    except (ConflictError, NotFoundError, PermissionDeniedError, ValidationError):
        raise
    except Exception:
        db.rollback()
        raise


def refund_payment(
    db: Session,
    payment_id: uuid.UUID,
    user: User,
    reason: Optional[str] = None,
    ip_address: Optional[str] = None,
    user_agent: Optional[str] = None,
) -> PaymentDetail:
    """
    Refunds a completed payment and safely reinstates the invoice balance.
    """
    if user.role.name not in ["SUPER_ADMIN", "PROPERTY_MANAGER"]:
        raise PermissionDeniedError("Only Super Admins and Property Managers can process refunds.")

    try:
        # Row lock payment and invoice
        payment = db.scalar(
            sa.select(Payment).where(Payment.id == payment_id).with_for_update()
        )
        if not payment:
            raise NotFoundError(f"Payment with ID '{payment_id}' not found.")

        _get_permitted_property_ids(db, user, payment.property_id)

        if payment.status != "COMPLETED":
            raise ConflictError(
                f"Cannot refund payment in '{payment.status}' status (must be COMPLETED)."
            )

        invoice = db.scalar(
            sa.select(Invoice).where(Invoice.id == payment.invoice_id).with_for_update()
        )
        if not invoice:
            raise NotFoundError(f"Parent invoice for payment '{payment_id}' not found.")

        # Reopen invoice balance
        invoice.paid_amount = max(Decimal("0.00"), invoice.paid_amount - payment.amount)
        invoice.balance_amount = invoice.total_amount - invoice.paid_amount
        if invoice.paid_amount == Decimal("0.00"):
            invoice.status = "ISSUED"
        else:
            invoice.status = "PARTIALLY_PAID"

        payment.status = "REFUNDED"
        if reason:
            payment.notes = f"{payment.notes or ''} [Refund reason: {reason}]".strip()

        db.commit()
        db.refresh(payment)
        db.refresh(invoice)

        record_audit_log(
            db=db,
            action="PAYMENT_REFUNDED",
            resource_type="payment",
            resource_id=str(payment.id),
            user_id=user.id,
            user_email=user.email,
            user_role=user.role.name,
            company_id=payment.company_id,
            property_id=payment.property_id,
            details={
                "payment_number": payment.payment_number,
                "amount": str(payment.amount),
                "reopened_balance": str(invoice.balance_amount),
            },
            ip_address=ip_address,
            user_agent=user_agent,
        )

        return get_payment_detail(db=db, payment_id=payment.id, user=user)
    except (ConflictError, NotFoundError, PermissionDeniedError, ValidationError):
        raise
    except Exception:
        db.rollback()
        raise


def list_payments(
    db: Session,
    user: User,
    property_id: Optional[uuid.UUID] = None,
    resident_id: Optional[uuid.UUID] = None,
    invoice_id: Optional[uuid.UUID] = None,
    status_filter: Optional[str] = None,
    payment_method: Optional[str] = None,
) -> List[PaymentDetail]:
    if user.role.name == "RESIDENT":
        resident = db.scalar(
            sa.select(Resident).where(
                sa.or_(Resident.user_id == user.id, Resident.phone == user.phone)
            )
        )
        if not resident:
            return []
        stmt = (
            sa.select(Payment)
            .options(
                joinedload(Payment.property),
                joinedload(Payment.resident),
                joinedload(Payment.invoice),
                joinedload(Payment.recorded_by),
            )
            .where(Payment.resident_id == resident.id)
        )
    else:
        permitted_ids = _get_permitted_property_ids(db, user, property_id)
        if not permitted_ids:
            return []
        stmt = (
            sa.select(Payment)
            .options(
                joinedload(Payment.property),
                joinedload(Payment.resident),
                joinedload(Payment.invoice),
                joinedload(Payment.recorded_by),
            )
            .where(Payment.property_id.in_(permitted_ids))
        )
        if resident_id:
            stmt = stmt.where(Payment.resident_id == resident_id)
        if invoice_id:
            stmt = stmt.where(Payment.invoice_id == invoice_id)

    if status_filter:
        stmt = stmt.where(Payment.status == status_filter.upper())
    if payment_method:
        stmt = stmt.where(Payment.payment_method == payment_method.upper())

    stmt = stmt.order_by(Payment.payment_date.desc(), Payment.created_at.desc())
    payments = db.scalars(stmt).unique().all()
    return [_build_payment_detail(p) for p in payments]


def get_payment_detail(db: Session, payment_id: uuid.UUID, user: User) -> PaymentDetail:
    stmt = (
        sa.select(Payment)
        .options(
            joinedload(Payment.property),
            joinedload(Payment.resident),
            joinedload(Payment.invoice),
            joinedload(Payment.recorded_by),
        )
        .where(Payment.id == payment_id)
    )
    payment = db.scalar(stmt)
    if not payment:
        raise NotFoundError(f"Payment with ID '{payment_id}' not found.")

    if user.role.name == "RESIDENT":
        if (
            payment.resident.user_id != user.id
            and payment.resident.phone != user.phone
        ):
            raise PermissionDeniedError("Residents can only access their own payment records.")
        return _build_payment_detail(payment)

    _get_permitted_property_ids(db, user, payment.property_id)
    return _build_payment_detail(payment)


def get_financial_summary(
    db: Session,
    user: User,
    property_id: Optional[uuid.UUID] = None,
    billing_month: Optional[str] = None,
) -> InvoiceSummary:
    """
    Computes property-wise and aggregate financial totals without double counting.
    Only includes properties authorized for the requesting user.
    """
    permitted_ids = _get_permitted_property_ids(db, user, property_id)
    if not permitted_ids:
        return InvoiceSummary(
            total_invoiced=Decimal("0.00"),
            total_collected=Decimal("0.00"),
            total_outstanding=Decimal("0.00"),
            total_overdue=Decimal("0.00"),
            invoices_count=0,
            paid_invoices_count=0,
            partially_paid_invoices_count=0,
            overdue_invoices_count=0,
            property_summaries=[],
        )

    # Base query for active/issued/paid invoices (excluding DRAFT and CANCELLED)
    stmt = sa.select(Invoice).where(
        Invoice.property_id.in_(permitted_ids),
        Invoice.status.in_(["ISSUED", "PARTIALLY_PAID", "PAID"]),
    )
    if billing_month:
        stmt = stmt.where(Invoice.billing_month == billing_month)

    invoices = db.scalars(stmt).all()

    total_invoiced = sum((inv.total_amount for inv in invoices), Decimal("0.00"))
    total_collected = sum((inv.paid_amount for inv in invoices), Decimal("0.00"))
    total_outstanding = sum((inv.balance_amount for inv in invoices), Decimal("0.00"))

    today_date = date.today()
    total_overdue = sum(
        (inv.balance_amount for inv in invoices if inv.due_date < today_date and inv.balance_amount > 0),
        Decimal("0.00"),
    )

    invoices_count = len(invoices)
    paid_count = sum(1 for inv in invoices if inv.status == "PAID" or inv.balance_amount == 0)
    partial_count = sum(1 for inv in invoices if inv.status == "PARTIALLY_PAID" or (inv.paid_amount > 0 and inv.balance_amount > 0))
    overdue_count = sum(1 for inv in invoices if inv.due_date < today_date and inv.balance_amount > 0)

    # Property-level breakdown
    props = db.scalars(sa.select(Property).where(Property.id.in_(permitted_ids))).all()
    prop_map = {p.id: p for p in props}

    prop_summaries = []
    for pid in permitted_ids:
        p = prop_map.get(pid)
        if not p:
            continue
        p_invoices = [inv for inv in invoices if inv.property_id == pid]
        p_invoiced = sum((inv.total_amount for inv in p_invoices), Decimal("0.00"))
        p_collected = sum((inv.paid_amount for inv in p_invoices), Decimal("0.00"))
        p_outstanding = sum((inv.balance_amount for inv in p_invoices), Decimal("0.00"))
        p_overdue = sum((inv.balance_amount for inv in p_invoices if inv.due_date < today_date and inv.balance_amount > 0), Decimal("0.00"))
        prop_summaries.append(
            PropertyFinancialSummary(
                property_id=p.id,
                property_name=p.name,
                property_code=p.code,
                total_invoiced=p_invoiced,
                total_collected=p_collected,
                total_outstanding=p_outstanding,
                total_overdue=p_overdue,
                invoices_count=len(p_invoices),
            )
        )

    return InvoiceSummary(
        total_invoiced=total_invoiced,
        total_collected=total_collected,
        total_outstanding=total_outstanding,
        total_overdue=total_overdue,
        invoices_count=invoices_count,
        paid_invoices_count=paid_count,
        partially_paid_invoices_count=partial_count,
        overdue_invoices_count=overdue_count,
        property_summaries=prop_summaries,
    )
