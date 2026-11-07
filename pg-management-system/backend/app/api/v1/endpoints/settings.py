import uuid
from typing import Any, Dict, Optional
from fastapi import APIRouter, Depends, status
from pydantic import BaseModel
import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.core.exceptions import NotFoundError
from app.dependencies import get_current_user, get_db, require_roles
from app.models.property import Company, Property
from app.models.resident import Resident
from app.models.user import User
from app.schemas.common import APIResponse
from app.services.audit_service import record_audit_log

router = APIRouter()


class CompanySettingsUpdate(BaseModel):
    name: Optional[str] = None
    phone: Optional[str] = None
    email: Optional[str] = None
    address: Optional[str] = None
    tax_id: Optional[str] = None


@router.get("/company", response_model=APIResponse[Dict[str, Any]], status_code=status.HTTP_200_OK)
def get_company_settings(
    current_user: User = Depends(require_roles("SUPER_ADMIN", "ADMIN", "OWNER", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Retrieves enterprise company details and operational profile."""
    company = db.get(Company, current_user.company_id)
    if not company:
        raise NotFoundError("Company record not found.")

    data = {
        "id": str(company.id),
        "name": company.name,
        "code": company.code,
        "email": company.email,
        "phone": company.phone,
        "address": company.address,
        "tax_id": company.tax_id,
        "subscription_plan": getattr(company, "subscription_plan", "STANDARD"),
        "subscription_status": getattr(company, "subscription_status", "ACTIVE"),
        "is_active": company.is_active,
    }
    return APIResponse(
        success=True,
        message="Company profile retrieved successfully.",
        data=data,
    )


@router.patch("/company", response_model=APIResponse[Dict[str, Any]], status_code=status.HTTP_200_OK)
def update_company_settings(
    payload: CompanySettingsUpdate,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "OWNER")),
    db: Session = Depends(get_db),
):
    """Updates company enterprise profile."""
    company = db.get(Company, current_user.company_id)
    if not company:
        raise NotFoundError("Company record not found.")

    update_data = payload.model_dump(exclude_unset=True)
    if "name" in update_data and update_data["name"]:
        company.name = update_data["name"].strip()
    if "phone" in update_data:
        company.phone = update_data["phone"].strip() if update_data["phone"] else None
    if "email" in update_data:
        company.email = update_data["email"].strip().lower() if update_data["email"] else None
    if "address" in update_data:
        company.address = update_data["address"]
    if "tax_id" in update_data:
        company.tax_id = update_data["tax_id"]

    record_audit_log(
        db=db,
        action="UPDATE_COMPANY_SETTINGS",
        resource_type="companies",
        user_id=current_user.id,
        user_email=current_user.email,
        user_role=current_user.role.name if current_user.role else None,
        property_id=None,
        resource_id=str(company.id),
        details={"updated_fields": list(update_data.keys())},
    )

    db.commit()
    db.refresh(company)

    data = {
        "id": str(company.id),
        "name": company.name,
        "code": company.code,
        "email": company.email,
        "phone": company.phone,
        "address": company.address,
        "tax_id": company.tax_id,
        "subscription_plan": getattr(company, "subscription_plan", "STANDARD"),
        "subscription_status": getattr(company, "subscription_status", "ACTIVE"),
        "is_active": company.is_active,
    }
    return APIResponse(
        success=True,
        message="Company profile updated successfully.",
        data=data,
    )


@router.get("/subscription", response_model=APIResponse[Dict[str, Any]], status_code=status.HTTP_200_OK)
def get_subscription_details(
    current_user: User = Depends(require_roles("SUPER_ADMIN", "ADMIN", "OWNER")),
    db: Session = Depends(get_db),
):
    """Retrieves subscription tier, usage counts, and quotas."""
    company = db.get(Company, current_user.company_id)
    if not company:
        raise NotFoundError("Company record not found.")

    total_props = db.scalar(
        sa.select(sa.func.count(Property.id)).where(Property.company_id == company.id, Property.is_active.is_(True))
    ) or 0
    total_residents = db.scalar(
        sa.select(sa.func.count(Resident.id))
        .join(Property, Resident.property_id == Property.id)
        .where(Property.company_id == company.id, Resident.status == "ACTIVE")
    ) or 0

    plan = getattr(company, "subscription_plan", "STANDARD") or "STANDARD"
    limits = {
        "STANDARD": {"max_properties": 5, "max_residents": 250},
        "ENTERPRISE": {"max_properties": 50, "max_residents": 5000},
        "UNLIMITED": {"max_properties": 9999, "max_residents": 999999},
    }.get(plan, {"max_properties": 5, "max_residents": 250})

    data = {
        "plan": plan,
        "status": getattr(company, "subscription_status", "ACTIVE"),
        "active_properties": total_props,
        "active_residents": total_residents,
        "limits": limits,
        "features": [
            "Online & Offline Rent Collection",
            "Super Key 2FA Authentication",
            "Resident Mobile App & KYC Onboarding",
            "Room & Bed Allocation Management",
            "Maintenance & Complaint Tracking",
            "Operational Expense Ledger",
            "Staff Management",
            "Weekly Food Menu Management",
            "Financial & Occupancy CSV Reporting",
            "Audit Logging & Security Verification",
        ],
    }
    return APIResponse(
        success=True,
        message="Subscription details retrieved successfully.",
        data=data,
    )
