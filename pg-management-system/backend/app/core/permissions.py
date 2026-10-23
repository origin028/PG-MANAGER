from enum import Enum
from typing import List


class RoleEnum(str, Enum):
    SUPER_ADMIN = "SUPER_ADMIN"
    PROPERTY_MANAGER = "PROPERTY_MANAGER"
    STAFF = "STAFF"
    RESIDENT = "RESIDENT"


class ClientTypeEnum(str, Enum):
    ADMIN_WEB = "admin_web"
    ADMIN_MOBILE = "admin_mobile"
    RESIDENT_MOBILE = "resident_mobile"


# Permission scopes defining feature access boundaries
ROLE_PERMISSIONS = {
    RoleEnum.SUPER_ADMIN: ["*"],
    RoleEnum.PROPERTY_MANAGER: [
        "properties:read",
        "rooms:read",
        "rooms:manage",
        "beds:read",
        "beds:manage",
        "residents:read",
        "residents:manage",
        "invoices:read",
        "invoices:manage",
        "payments:read",
        "payments:record",
        "complaints:read",
        "complaints:manage",
        "expenses:read",
        "expenses:manage",
        "staff:read",
        "leads:read",
        "leads:manage",
        "notices:read",
        "notices:manage",
        "reports:read",
    ],
    RoleEnum.STAFF: [
        "properties:read",
        "rooms:read",
        "beds:read",
        "beds:status_update",
        "residents:read",
        "complaints:read",
        "complaints:update",
        "notices:read",
    ],
    RoleEnum.RESIDENT: [
        "profile:self",
        "bed:self",
        "invoices:self",
        "payments:self",
        "complaints:self",
        "notices:read",
    ],
}


def is_role_allowed(user_role: str, allowed_roles: List[str]) -> bool:
    """Checks whether the user's role is in the list of allowed roles."""
    return user_role in allowed_roles


def has_permission(user_role: str, required_permission: str) -> bool:
    """Verifies if a role has a specific granular permission or wildcard."""
    perms = ROLE_PERMISSIONS.get(RoleEnum(user_role), [])
    if "*" in perms:
        return True
    return required_permission in perms
