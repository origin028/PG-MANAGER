import uuid
from typing import List, Optional
from fastapi import APIRouter, Depends, Query, Request, status
import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.api.deps import get_current_user, get_db, require_roles, verify_property_access
from app.core.exceptions import ConflictError, NotFoundError
from app.models.property import Property
from app.models.user import User
from app.schemas.bed import BedRead
from app.schemas.common import APIResponse
from app.schemas.property import PropertyCreate, PropertyRead, PropertySummary
from app.schemas.room import RoomCreate, RoomRead
from app.services.audit_service import record_audit_log
from app.services.property_service import get_properties_for_user, get_property_by_id
from app.services.room_service import create_room, list_beds, list_rooms

router = APIRouter()


@router.get("", response_model=APIResponse[List[PropertySummary]], status_code=status.HTTP_200_OK)
def list_user_properties(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Returns properties accessible to the current user.
    - Super Admins see all company PG properties.
    - Property Managers and Staff see only assigned properties.
    - Residents see only their assigned PG property.
    """
    properties = get_properties_for_user(db, current_user)
    summaries = [PropertySummary.model_validate(p) for p in properties]
    return APIResponse(
        success=True,
        message=f"Retrieved {len(summaries)} accessible properties.",
        data=summaries,
    )


@router.get("/{property_id}", response_model=APIResponse[PropertyRead], status_code=status.HTTP_200_OK)
def get_property_details(
    property_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Returns complete details of a property after server-side access verification.
    """
    verify_property_access(property_id, current_user, db)
    prop = get_property_by_id(db, property_id)
    if not prop:
        raise NotFoundError(f"Property with ID '{property_id}' not found.")

    return APIResponse(
        success=True,
        message="Property details retrieved successfully.",
        data=PropertyRead.model_validate(prop),
    )


@router.post("", response_model=APIResponse[PropertyRead], status_code=status.HTTP_201_CREATED)
def create_new_property(
    payload: PropertyCreate,
    current_user: User = Depends(require_roles("SUPER_ADMIN")),
    db: Session = Depends(get_db),
):
    """
    Create a new PG property. Restricted to Super Admin.
    """
    # Check property code uniqueness
    existing = db.scalar(sa.select(Property).where(Property.code == payload.code.upper()))
    if existing:
        raise ConflictError(f"A property with code '{payload.code}' already exists.")

    new_prop = Property(
        company_id=current_user.company_id,
        name=payload.name,
        code=payload.code.upper(),
        property_type=payload.property_type,
        address_line1=payload.address_line1,
        address_line2=payload.address_line2,
        city=payload.city,
        state=payload.state,
        pincode=payload.pincode,
        contact_phone=payload.contact_phone,
        contact_email=payload.contact_email,
        total_floors=payload.total_floors,
        is_active=payload.is_active,
        settings=payload.settings,
    )
    db.add(new_prop)
    db.commit()
    db.refresh(new_prop)

    record_audit_log(
        db=db,
        action="PROPERTY_CREATED",
        resource_type="property",
        user_id=current_user.id,
        user_email=current_user.email,
        user_role=current_user.role.name,
        company_id=current_user.company_id,
        property_id=new_prop.id,
        resource_id=str(new_prop.id),
        details={"name": new_prop.name, "code": new_prop.code},
    )

    return APIResponse(
        success=True,
        message="Property created successfully.",
        data=PropertyRead.model_validate(new_prop),
    )


@router.get("/{property_id}/rooms", response_model=APIResponse[List[RoomRead]], status_code=status.HTTP_200_OK)
def list_property_rooms(
    property_id: uuid.UUID,
    floor_number: Optional[int] = Query(None, description="Filter by floor number"),
    room_type: Optional[str] = Query(None, description="Filter by room type"),
    is_active: Optional[bool] = Query(None, description="Filter by active status"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """List rooms within a specific PG property."""
    rooms = list_rooms(
        db=db,
        user=current_user,
        property_id=property_id,
        floor_number=floor_number,
        room_type=room_type,
        is_active=is_active,
    )
    return APIResponse(
        success=True,
        message=f"Retrieved {len(rooms)} rooms for property.",
        data=rooms,
    )


@router.post("/{property_id}/rooms", response_model=APIResponse[RoomRead], status_code=status.HTTP_201_CREATED)
def create_property_room(
    property_id: uuid.UUID,
    payload: RoomCreate,
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Create a new room in a PG property. Restricted to Super Admin and Property Managers."""
    ip_address = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")

    room = create_room(
        db=db,
        property_id=property_id,
        data=payload,
        user=current_user,
        ip_address=ip_address,
        user_agent=user_agent,
    )
    return APIResponse(
        success=True,
        message="Room created successfully.",
        data=room,
    )


@router.get("/{property_id}/beds", response_model=APIResponse[List[BedRead]], status_code=status.HTTP_200_OK)
def list_property_beds(
    property_id: uuid.UUID,
    room_id: Optional[uuid.UUID] = Query(None, description="Filter by room ID"),
    bed_status: Optional[str] = Query(None, alias="status", description="Filter by status"),
    is_active: Optional[bool] = Query(None, description="Filter by active status"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """List all beds in a specific PG property."""
    beds = list_beds(
        db=db,
        user=current_user,
        property_id=property_id,
        room_id=room_id,
        status=bed_status,
        is_active=is_active,
    )
    return APIResponse(
        success=True,
        message=f"Retrieved {len(beds)} beds for property.",
        data=beds,
    )


@router.get("/{property_id}/dashboard", response_model=APIResponse[dict], status_code=status.HTTP_200_OK)
def get_property_dashboard(
    property_id: uuid.UUID,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "PROPERTY_MANAGER", "STAFF")),
    db: Session = Depends(get_db),
):
    """Aggregated operational and financial dashboard for a single PG property.

    Access is limited to administrative roles and is scoped to the properties the
    caller is explicitly assigned to. Residents cannot read property dashboards.
    """
    from calendar import monthrange
    from datetime import date
    from decimal import Decimal

    from app.models.bed import Bed
    from app.models.invoice import Invoice
    from app.models.payment import Payment
    from app.models.resident import Resident

    verify_property_access(property_id, current_user, db)

    total_tenants = db.query(Resident).filter(
        Resident.property_id == property_id,
        Resident.status.in_(["ACTIVE", "ADMITTED", "NOTICE_PERIOD"]),
    ).count()

    # Residents who still owe money on at least one non-cancelled invoice.
    unpaid_resident_ids = {
        row[0]
        for row in db.query(Invoice.resident_id)
        .filter(
            Invoice.property_id == property_id,
            Invoice.balance_amount > Decimal("0.00"),
            Invoice.status.not_in(["PAID", "CANCELLED"]),
        )
        .distinct()
        .all()
    }
    unpaid_tenants = len(unpaid_resident_ids)

    available_beds = db.query(Bed).filter(
        Bed.property_id == property_id,
        Bed.is_active == True,
        Bed.status == "AVAILABLE",
    ).count()

    today = date.today()
    first_of_month = today.replace(day=1)
    last_of_month = today.replace(day=monthrange(today.year, today.month)[1])

    def _month_revenue(start: date, end: date) -> Decimal:
        total = db.query(sa.func.coalesce(sa.func.sum(Payment.amount), 0)).filter(
            Payment.property_id == property_id,
            Payment.status == "COMPLETED",
            Payment.payment_date >= start,
            Payment.payment_date <= end,
        ).scalar()
        return Decimal(str(total or 0))

    revenue_this_month = _month_revenue(first_of_month, last_of_month)

    if today.month == 1:
        pm_year, pm_month = today.year - 1, 12
    else:
        pm_year, pm_month = today.year, today.month - 1
    pm_first = date(pm_year, pm_month, 1)
    pm_last = date(pm_year, pm_month, monthrange(pm_year, pm_month)[1])
    revenue_prev_month = _month_revenue(pm_first, pm_last)

    if revenue_prev_month == Decimal("0.00"):
        revenue_growth_percentage = 0.0
    else:
        revenue_growth_percentage = round(
            float((revenue_this_month - revenue_prev_month) / revenue_prev_month * 100), 2
        )

    data = {
        "total_tenants": total_tenants,
        "unpaid_tenants": unpaid_tenants,
        "available_beds": available_beds,
        "revenue_this_month": float(revenue_this_month),
        "revenue_growth_percentage": revenue_growth_percentage,
    }
    return APIResponse(success=True, message="Dashboard data retrieved successfully.", data=data)

