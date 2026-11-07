import csv
import io
import uuid
from datetime import date, datetime, timezone
from decimal import Decimal
from typing import Any, Dict, List, Optional
from fastapi import APIRouter, Depends, Query, Response, status
import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.core.exceptions import NotFoundError, PermissionDeniedError
from app.dependencies import get_db, require_roles, verify_property_access
from app.models.bed import Bed
from app.models.complaint import Complaint
from app.models.expense import Expense
from app.models.invoice import Invoice
from app.models.payment import Payment
from app.models.property import Property
from app.models.receipt import Receipt
from app.models.resident import Resident
from app.models.room import Room
from app.models.user import User
from app.schemas.common import APIResponse

router = APIRouter()


@router.get("/dashboard", response_model=APIResponse[Dict[str, Any]], status_code=status.HTTP_200_OK)
def get_dashboard_summary(
    property_id: Optional[uuid.UUID] = Query(None, description="Optional property filter"),
    current_user: User = Depends(require_roles("SUPER_ADMIN", "ADMIN", "OWNER", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """High-level executive dashboard summary with operational and financial metrics."""
    if property_id:
        verify_property_access(property_id, current_user, db)

    # Scoping filter
    prop_filter = []
    if property_id:
        prop_filter.append(Property.id == property_id)
    elif current_user.role.name not in ("SUPER_ADMIN", "OWNER"):
        allowed = getattr(current_user, "allowed_properties", []) or []
        allowed_uuids = [uuid.UUID(str(p)) for p in allowed if p]
        prop_filter.append(Property.id.in_(allowed_uuids))

    # Properties count
    props_query = sa.select(sa.func.count(Property.id))
    if prop_filter:
        props_query = props_query.where(*prop_filter)
    total_properties = db.scalar(props_query) or 0

    # Rooms & Beds
    bed_query = sa.select(sa.func.count(Bed.id)).select_from(Bed).join(Room, Bed.room_id == Room.id)
    if property_id:
        bed_query = bed_query.where(Room.property_id == property_id)
    elif prop_filter:
        bed_query = bed_query.where(Room.property_id.in_(sa.select(Property.id).where(*prop_filter)))
    total_beds = db.scalar(bed_query) or 0

    # Occupied beds (Active / Notice Period residents)
    occ_query = (
        sa.select(sa.func.count(sa.distinct(Bed.id)))
        .select_from(Bed)
        .join(Room, Bed.room_id == Room.id)
        .join(Resident, Resident.bed_id == Bed.id)
        .where(
            Resident.status.in_(("ACTIVE", "NOTICE_PERIOD")),
            Resident.property_id == Room.property_id,
        )
    )
    if property_id:
        occ_query = occ_query.where(Room.property_id == property_id)
    elif prop_filter:
        occ_query = occ_query.where(Room.property_id.in_(sa.select(Property.id).where(*prop_filter)))
    occupied_beds = db.scalar(occ_query) or 0
    vacant_beds = max(0, total_beds - occupied_beds)
    occupancy_rate = round((occupied_beds / total_beds) * 100, 2) if total_beds else 0.0

    # Residents
    res_query = sa.select(sa.func.count(Resident.id))
    if property_id:
        res_query = res_query.where(Resident.property_id == property_id)
    elif prop_filter:
        res_query = res_query.where(Resident.property_id.in_(sa.select(Property.id).where(*prop_filter)))
    total_residents = db.scalar(res_query) or 0

    active_res_query = res_query.where(Resident.status == "ACTIVE")
    active_residents = db.scalar(active_res_query) or 0

    # Financials
    # Gross collections
    pay_query = sa.select(sa.func.coalesce(sa.func.sum(Payment.amount), 0)).where(
        Payment.status.in_(("SUCCESS", "PAID"))
    )
    if property_id:
        pay_query = pay_query.where(Payment.property_id == property_id)
    elif prop_filter:
        pay_query = pay_query.where(Payment.property_id.in_(sa.select(Property.id).where(*prop_filter)))
    gross_collections = float(db.scalar(pay_query) or 0.0)

    # Total expenses
    exp_query = sa.select(sa.func.coalesce(sa.func.sum(Expense.amount), 0))
    if property_id:
        exp_query = exp_query.where(Expense.property_id == property_id)
    elif prop_filter:
        exp_query = exp_query.where(Expense.property_id.in_(sa.select(Property.id).where(*prop_filter)))
    total_expenses = float(db.scalar(exp_query) or 0.0)

    net_operating_profit = round(gross_collections - total_expenses, 2)

    # Pending rent
    inv_query = sa.select(
        sa.func.coalesce(sa.func.sum(Invoice.amount - Invoice.paid_amount), 0)
    ).where(Invoice.status.in_(("PENDING", "PARTIALLY_PAID")))
    if property_id:
        inv_query = inv_query.where(Invoice.property_id == property_id)
    elif prop_filter:
        inv_query = inv_query.where(Invoice.property_id.in_(sa.select(Property.id).where(*prop_filter)))
    pending_rent = float(db.scalar(inv_query) or 0.0)

    # Open complaints
    comp_query = sa.select(sa.func.count(Complaint.id)).where(Complaint.status.in_(("PENDING", "ASSIGNED", "IN_PROGRESS")))
    if property_id:
        comp_query = comp_query.where(Complaint.property_id == property_id)
    elif prop_filter:
        comp_query = comp_query.where(Complaint.property_id.in_(sa.select(Property.id).where(*prop_filter)))
    open_complaints = db.scalar(comp_query) or 0

    data = {
        "total_properties": total_properties,
        "total_residents": total_residents,
        "active_residents": active_residents,
        "total_beds": total_beds,
        "occupied_beds": occupied_beds,
        "vacant_beds": vacant_beds,
        "occupancy_rate_percent": occupancy_rate,
        "gross_collections": gross_collections,
        "total_expenses": total_expenses,
        "net_operating_profit": net_operating_profit,
        "pending_rent": pending_rent,
        "open_complaints": open_complaints,
    }
    return APIResponse(
        success=True,
        message="Dashboard summary retrieved successfully.",
        data=data,
    )


@router.get("/financial", response_model=APIResponse[Dict[str, Any]], status_code=status.HTTP_200_OK)
def get_financial_report(
    property_id: Optional[uuid.UUID] = Query(None, description="Optional property filter"),
    date_from: Optional[date] = Query(None, description="Start date filter"),
    date_to: Optional[date] = Query(None, description="End date filter"),
    current_user: User = Depends(require_roles("SUPER_ADMIN", "ADMIN", "OWNER", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Generates detailed financial report: Gross Collections, Expenses, Net Operating Profit."""
    if property_id:
        verify_property_access(property_id, current_user, db)

    # Payments (Collections)
    pay_query = sa.select(Payment).where(Payment.status.in_(("SUCCESS", "PAID")))
    if property_id:
        pay_query = pay_query.where(Payment.property_id == property_id)
    if date_from:
        pay_query = pay_query.where(sa.cast(Payment.paid_at, sa.Date) >= date_from)
    if date_to:
        pay_query = pay_query.where(sa.cast(Payment.paid_at, sa.Date) <= date_to)

    payments = db.scalars(pay_query).all()
    gross_collections = Decimal("0.00")
    by_payment_mode = {}
    for p in payments:
        amt = Decimal(str(p.amount))
        gross_collections += amt
        mode = p.payment_mode or "OTHER"
        by_payment_mode[mode] = by_payment_mode.get(mode, 0.0) + float(amt)

    # Expenses
    exp_query = sa.select(Expense)
    if property_id:
        exp_query = exp_query.where(Expense.property_id == property_id)
    if date_from:
        exp_query = exp_query.where(Expense.date >= date_from)
    if date_to:
        exp_query = exp_query.where(Expense.date <= date_to)

    expenses = db.scalars(exp_query).all()
    total_expenses = Decimal("0.00")
    by_category = {}
    for e in expenses:
        amt = Decimal(str(e.amount))
        total_expenses += amt
        cat = e.category or "OTHER"
        by_category[cat] = by_category.get(cat, 0.0) + float(amt)

    net_operating_profit = gross_collections - total_expenses

    # Invoices (Pending Rent)
    inv_query = sa.select(Invoice).where(Invoice.status.in_(("PENDING", "PARTIALLY_PAID")))
    if property_id:
        inv_query = inv_query.where(Invoice.property_id == property_id)
    if date_from:
        inv_query = inv_query.where(Invoice.due_date >= date_from)
    if date_to:
        inv_query = inv_query.where(Invoice.due_date <= date_to)

    invoices = db.scalars(inv_query).all()
    pending_rent = sum((Decimal(str(inv.amount)) - Decimal(str(inv.paid_amount))) for inv in invoices)

    data = {
        "period": {
            "date_from": str(date_from) if date_from else None,
            "date_to": str(date_to) if date_to else None,
        },
        "gross_collections": float(gross_collections),
        "total_expenses": float(total_expenses),
        "net_operating_profit": float(net_operating_profit),
        "pending_rent": float(pending_rent),
        "collections_by_mode": by_payment_mode,
        "expenses_by_category": by_category,
        "payment_count": len(payments),
        "expense_count": len(expenses),
    }
    return APIResponse(
        success=True,
        message="Financial report generated successfully.",
        data=data,
    )


@router.get("/payments", response_model=APIResponse[Dict[str, Any]], status_code=status.HTTP_200_OK)
def get_payments_report(
    property_id: Optional[uuid.UUID] = Query(None, description="Optional property filter"),
    payment_mode: Optional[str] = Query(None, description="Filter by payment mode"),
    date_from: Optional[date] = Query(None, description="Start date filter"),
    date_to: Optional[date] = Query(None, description="End date filter"),
    current_user: User = Depends(require_roles("SUPER_ADMIN", "ADMIN", "OWNER", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Payment statement report with breakdown and itemized history."""
    if property_id:
        verify_property_access(property_id, current_user, db)

    query = sa.select(Payment).where(Payment.status.in_(("SUCCESS", "PAID"))).order_by(Payment.paid_at.desc())
    if property_id:
        query = query.where(Payment.property_id == property_id)
    if payment_mode:
        query = query.where(Payment.payment_mode == payment_mode.upper())
    if date_from:
        query = query.where(sa.cast(Payment.paid_at, sa.Date) >= date_from)
    if date_to:
        query = query.where(sa.cast(Payment.paid_at, sa.Date) <= date_to)

    payments = db.scalars(query).all()
    items = []
    total_amount = Decimal("0.00")
    for p in payments:
        total_amount += Decimal(str(p.amount))
        receipt = db.scalar(sa.select(Receipt).where(Receipt.payment_id == p.id))
        resident = db.get(Resident, p.resident_id)
        resident_user = resident.user if resident else None
        prop = db.get(Property, p.property_id)

        items.append({
            "payment_id": str(p.id),
            "payment_number": p.payment_number,
            "property_name": prop.name if prop else "Unknown",
            "resident_name": resident_user.full_name if resident_user else "Resident",
            "amount": float(p.amount),
            "payment_mode": p.payment_mode,
            "status": p.status,
            "paid_at": p.paid_at.isoformat() if p.paid_at else None,
            "receipt_number": receipt.receipt_number if receipt else None,
        })

    data = {
        "total_amount": float(total_amount),
        "count": len(items),
        "payments": items,
    }
    return APIResponse(
        success=True,
        message=f"Retrieved {len(items)} payment records.",
        data=data,
    )


@router.get("/payments/export", status_code=status.HTTP_200_OK)
def export_payments_csv(
    property_id: Optional[uuid.UUID] = Query(None, description="Optional property filter"),
    payment_mode: Optional[str] = Query(None, description="Filter by payment mode"),
    date_from: Optional[date] = Query(None, description="Start date filter"),
    date_to: Optional[date] = Query(None, description="End date filter"),
    current_user: User = Depends(require_roles("SUPER_ADMIN", "ADMIN", "OWNER", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Exports payment statement to CSV format."""
    if property_id:
        verify_property_access(property_id, current_user, db)

    query = sa.select(Payment).where(Payment.status.in_(("SUCCESS", "PAID"))).order_by(Payment.paid_at.desc())
    if property_id:
        query = query.where(Payment.property_id == property_id)
    if payment_mode:
        query = query.where(Payment.payment_mode == payment_mode.upper())
    if date_from:
        query = query.where(sa.cast(Payment.paid_at, sa.Date) >= date_from)
    if date_to:
        query = query.where(sa.cast(Payment.paid_at, sa.Date) <= date_to)

    payments = db.scalars(query).all()

    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow([
        "Payment Number",
        "Property",
        "Resident Name",
        "Amount (INR)",
        "Payment Mode",
        "Status",
        "Paid Date",
        "Receipt Number",
    ])

    for p in payments:
        receipt = db.scalar(sa.select(Receipt).where(Receipt.payment_id == p.id))
        resident = db.get(Resident, p.resident_id)
        resident_user = resident.user if resident else None
        prop = db.get(Property, p.property_id)
        writer.writerow([
            p.payment_number,
            prop.name if prop else "",
            resident_user.full_name if resident_user else "",
            f"{float(p.amount):.2f}",
            p.payment_mode,
            p.status,
            p.paid_at.strftime("%Y-%m-%d %H:%M:%S") if p.paid_at else "",
            receipt.receipt_number if receipt else "",
        ])

    csv_data = output.getvalue()
    return Response(
        content=csv_data,
        media_type="text/csv",
        headers={"Content-Disposition": 'attachment; filename="payments_report.csv"'},
    )


@router.get("/occupancy", response_model=APIResponse[Dict[str, Any]], status_code=status.HTTP_200_OK)
def get_occupancy_report(
    property_id: uuid.UUID = Query(..., description="Property ID filter"),
    current_user: User = Depends(require_roles("SUPER_ADMIN", "PROPERTY_MANAGER", "ADMIN", "OWNER")),
    db: Session = Depends(get_db),
):
    """Generates occupancy and bed utilization summary for a property."""
    verify_property_access(property_id, current_user, db)
    total_beds = db.scalar(
        sa.select(sa.func.count(Bed.id))
        .select_from(Bed)
        .join(Room, Bed.room_id == Room.id)
        .where(Room.property_id == property_id)
    ) or 0

    occupied_beds = db.scalar(
        sa.select(sa.func.count(sa.distinct(Bed.id)))
        .select_from(Bed)
        .join(Room, Bed.room_id == Room.id)
        .join(Resident, Resident.bed_id == Bed.id)
        .where(
            Room.property_id == property_id,
            Resident.property_id == property_id,
            Resident.status.in_(("ACTIVE", "NOTICE_PERIOD")),
        )
    ) or 0
    available_beds = max(total_beds - occupied_beds, 0)
    occupancy_rate_percent = round((occupied_beds / total_beds) * 100, 2) if total_beds else 0.0

    data = {
        "property_id": str(property_id),
        "total_beds": total_beds,
        "occupied_beds": occupied_beds,
        "available_beds": available_beds,
        "occupancy_rate_percent": occupancy_rate_percent,
    }
    return APIResponse(
        success=True,
        message="Occupancy summary generated.",
        data=data,
    )


@router.get("/occupancy/export", status_code=status.HTTP_200_OK)
def export_occupancy_csv(
    property_id: uuid.UUID = Query(..., description="Property ID filter"),
    current_user: User = Depends(require_roles("SUPER_ADMIN", "PROPERTY_MANAGER", "ADMIN", "OWNER")),
    db: Session = Depends(get_db),
):
    """Exports property room and bed occupancy breakdown to CSV."""
    verify_property_access(property_id, current_user, db)
    prop = db.get(Property, property_id)
    if not prop:
        raise NotFoundError("Property not found.")

    beds = (
        db.scalars(
            sa.select(Bed)
            .join(Room, Bed.room_id == Room.id)
            .where(Room.property_id == property_id)
            .order_by(Room.room_number.asc(), Bed.bed_number.asc())
        )
        .all()
    )

    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow([
        "Property",
        "Room Number",
        "Bed Number",
        "Bed Status",
        "Resident Name",
        "Resident Phone",
        "Check-in Date",
    ])

    for bed in beds:
        room = db.get(Room, bed.room_id)
        resident = db.scalar(
            sa.select(Resident).where(
                Resident.bed_id == bed.id,
                Resident.property_id == property_id,
                Resident.status.in_(("ACTIVE", "NOTICE_PERIOD")),
            )
        )
        res_user = resident.user if resident else None

        writer.writerow([
            prop.name,
            room.room_number if room else "",
            bed.bed_number,
            "OCCUPIED" if resident else "AVAILABLE",
            res_user.full_name if res_user else "",
            res_user.phone if res_user else "",
            resident.check_in_date.isoformat() if resident and resident.check_in_date else "",
        ])

    csv_data = output.getvalue()
    return Response(
        content=csv_data,
        media_type="text/csv",
        headers={"Content-Disposition": f'attachment; filename="occupancy_{prop.code or "property"}.csv"'},
    )
