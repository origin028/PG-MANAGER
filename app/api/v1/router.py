from fastapi import APIRouter

from app.api.v1.endpoints import (
    audit,
    auth,
    beds,
    health,
    invoices,
    payments,
    properties,
    residents,
    rooms,
    users,
    complaints,
    expenses,
    staff,
)

api_router = APIRouter()

api_router.include_router(health.router, tags=["Health"])
api_router.include_router(auth.router, prefix="/auth", tags=["Authentication & Session"])
api_router.include_router(properties.router, prefix="/properties", tags=["Properties & Scoping"])
api_router.include_router(rooms.router, prefix="/rooms", tags=["Rooms Management"])
api_router.include_router(beds.router, prefix="/beds", tags=["Beds Management"])
api_router.include_router(residents.router, prefix="/residents", tags=["Resident Admissions & Allocations"])
api_router.include_router(invoices.router, prefix="/invoices", tags=["Invoices & Billing"])
api_router.include_router(payments.router, prefix="/payments", tags=["Payments & Collections"])
api_router.include_router(users.router, prefix="/users", tags=["Users & Staff Access"])
api_router.include_router(audit.router, prefix="/audit-logs", tags=["Audit & Security"])
api_router.include_router(complaints.router, prefix="/complaints", tags=["Complaints"])
api_router.include_router(expenses.router, prefix="/expenses", tags=["Expenses"])
api_router.include_router(staff.router, prefix="/staff", tags=["Staff"])

