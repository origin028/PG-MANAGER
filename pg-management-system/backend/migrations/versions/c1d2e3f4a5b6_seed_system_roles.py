"""seed system roles

Revision ID: c1d2e3f4a5b6
Revises: b8c9d0e1f2a3
Create Date: 2026-11-23 10:00:00.000000

"""
from typing import Sequence, Union
import json
import uuid
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'c1d2e3f4a5b6'
down_revision: Union[str, None] = 'b8c9d0e1f2a3'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SYSTEM_ROLES = [
    {
        "name": "SUPER_ADMIN",
        "display_name": "Super Administrator / Owner",
        "description": "Full platform management access across all modules",
        "permissions": ["*"],
    },
    {
        "name": "PROPERTY_MANAGER",
        "display_name": "Property Manager",
        "description": "Property management, resident onboarding, invoicing, complaints",
        "permissions": [
            "properties:read", "rooms:read", "rooms:manage", "beds:read", "beds:manage",
            "residents:read", "residents:manage", "invoices:read", "invoices:manage",
            "payments:read", "payments:record", "complaints:read", "complaints:manage",
            "expenses:read", "expenses:manage", "staff:read", "leads:read", "leads:manage",
            "notices:read", "notices:manage", "reports:read",
        ],
    },
    {
        "name": "STAFF",
        "display_name": "Staff / Warden",
        "description": "Day-to-day operations, bed inspections, and complaints handling",
        "permissions": [
            "properties:read", "rooms:read", "beds:read", "beds:status_update",
            "residents:read", "complaints:read", "complaints:update", "notices:read",
        ],
    },
    {
        "name": "RESIDENT",
        "display_name": "Resident",
        "description": "Resident mobile portal access: stay details, rent payments, complaints",
        "permissions": [
            "profile:self", "bed:self", "invoices:self", "payments:self",
            "complaints:self", "notices:read",
        ],
    },
]


def upgrade() -> None:
    bind = op.get_bind()
    for role in SYSTEM_ROLES:
        existing = bind.execute(
            sa.text("SELECT id FROM roles WHERE name = :name"),
            {"name": role["name"]},
        ).fetchone()
        if not existing:
            bind.execute(
                sa.text(
                    "INSERT INTO roles (id, name, display_name, description, is_system_role, permissions, created_at, updated_at) "
                    "VALUES (:id, :name, :display_name, :description, true, :permissions, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)"
                ),
                {
                    "id": str(uuid.uuid4()),
                    "name": role["name"],
                    "display_name": role["display_name"],
                    "description": role["description"],
                    "permissions": json.dumps(role["permissions"]),
                },
            )
        else:
            bind.execute(
                sa.text(
                    "UPDATE roles SET is_system_role = true WHERE name = :name"
                ),
                {"name": role["name"]},
            )


def downgrade() -> None:
    # Non-destructive: preserve existing roles and user assignments
    pass
