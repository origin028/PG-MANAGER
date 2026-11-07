from fastapi import APIRouter

from app.api.v1.endpoints import (
    audit_logs,
    auth,
    beds,
    company,
    complaints,
    expenses,
    food_menus,
    health,
    invoices,
    leads,
    notices,
    notifications,
    payments,
    properties,
    receipts,
    reports,
    resident_mobile,
    residents,
    rooms,
    settings,
    staff,
    users,
)

v1_router = APIRouter()

v1_router.include_router(health.router, tags=["Health"])
v1_router.include_router(company.router, prefix="/company", tags=["Company & Bed Capacity"])
v1_router.include_router(auth.router, prefix="/auth", tags=["Authentication & Session"])
v1_router.include_router(resident_mobile.router, prefix="/resident", tags=["Resident Mobile App"])
v1_router.include_router(properties.router, prefix="/properties", tags=["Properties & Scoping"])
v1_router.include_router(users.router, prefix="/users", tags=["Users & Staff Access"])
v1_router.include_router(rooms.router, prefix="/rooms", tags=["Rooms"])
v1_router.include_router(beds.router, prefix="/beds", tags=["Beds & Allocations"])
v1_router.include_router(residents.router, prefix="/residents", tags=["Residents & KYC"])
v1_router.include_router(invoices.router, prefix="/invoices", tags=["Invoices & Billing"])
v1_router.include_router(payments.router, prefix="/payments", tags=["Payments & Ledger"])
v1_router.include_router(receipts.router, prefix="/receipts", tags=["Receipts & Invoicing"])
v1_router.include_router(complaints.router, prefix="/complaints", tags=["Complaints & Maintenance"])
v1_router.include_router(expenses.router, prefix="/expenses", tags=["Expenses"])
v1_router.include_router(food_menus.router, prefix="/food-menus", tags=["Food Menu"])
v1_router.include_router(staff.router, prefix="/staff", tags=["Staff"])
v1_router.include_router(leads.router, prefix="/leads", tags=["Leads & CRM"])
v1_router.include_router(notices.router, prefix="/notices", tags=["Notices & Broadcasts"])
v1_router.include_router(notifications.router, prefix="/notifications", tags=["Notifications"])
v1_router.include_router(reports.router, prefix="/reports", tags=["Reports & Analytics"])
v1_router.include_router(settings.router, prefix="/settings", tags=["Settings & Enterprise"])
v1_router.include_router(audit_logs.router, prefix="/audit-logs", tags=["Audit & Security"])
