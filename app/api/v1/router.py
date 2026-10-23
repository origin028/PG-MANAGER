from fastapi import APIRouter

from app.api.v1.endpoints import audit, auth, health, properties, users

api_router = APIRouter()

api_router.include_router(health.router, tags=["Health"])
api_router.include_router(auth.router, prefix="/auth", tags=["Authentication & Session"])
api_router.include_router(properties.router, prefix="/properties", tags=["Properties & Scoping"])
api_router.include_router(users.router, prefix="/users", tags=["Users & Staff Access"])
api_router.include_router(audit.router, prefix="/audit-logs", tags=["Audit & Security"])
