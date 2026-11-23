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


SYSTEM_ROLES_DATA = [
    {
        "name": RoleEnum.SUPER_ADMIN.value,
        "display_name": "Super Administrator / Owner",
        "description": "Full platform management access across all modules",
        "permissions": ROLE_PERMISSIONS[RoleEnum.SUPER_ADMIN],
    },
    {
        "name": RoleEnum.PROPERTY_MANAGER.value,
        "display_name": "Property Manager",
        "description": "Property management, resident onboarding, invoicing, complaints",
        "permissions": ROLE_PERMISSIONS[RoleEnum.PROPERTY_MANAGER],
    },
    {
        "name": RoleEnum.STAFF.value,
        "display_name": "Staff / Warden",
        "description": "Day-to-day operations, bed inspections, and complaints handling",
        "permissions": ROLE_PERMISSIONS[RoleEnum.STAFF],
    },
    {
        "name": RoleEnum.RESIDENT.value,
        "display_name": "Resident",
        "description": "Resident mobile portal access: stay details, rent payments, complaints",
        "permissions": ROLE_PERMISSIONS[RoleEnum.RESIDENT],
    },
]


def is_role_allowed(user_role: str, allowed_roles: List[str]) -> bool:
    """Checks whether the user's role is in the list of allowed roles."""
    return user_role in allowed_roles


def has_permission(user_role: str, required_permission: str) -> bool:
    """Verifies if a role has a specific granular permission or wildcard."""
    perms = ROLE_PERMISSIONS.get(RoleEnum(user_role), [])
    if "*" in perms:
        return True
    return required_permission in perms
