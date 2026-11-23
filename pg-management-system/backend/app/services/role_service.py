import uuid
from typing import Dict, List, Optional, Union
import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.core.logging import logger
from app.core.permissions import RoleEnum, SYSTEM_ROLES_DATA, ROLE_PERMISSIONS
from app.models.role import Role


def ensure_system_roles_exist(db: Session) -> Dict[str, Role]:
    """
    Idempotently verifies and initializes all 4 canonical system roles:
    SUPER_ADMIN, PROPERTY_MANAGER, STAFF, and RESIDENT.

    Safe to run repeatedly on startup, during migrations, or inside request handlers.
    Preserves all existing role records, IDs, and assignments without duplication.
    """
    role_map: Dict[str, Role] = {}
    needs_commit = False

    for role_def in SYSTEM_ROLES_DATA:
        name = role_def["name"]
        existing = db.scalar(sa.select(Role).where(Role.name == name))
        if not existing:
            new_role = Role(
                id=uuid.uuid4(),
                name=name,
                display_name=role_def["display_name"],
                description=role_def["description"],
                is_system_role=True,
                permissions=role_def["permissions"],
            )
            db.add(new_role)
            db.flush()
            role_map[name] = new_role
            needs_commit = True
            logger.info(f"[RoleService] Initialized missing system role: {name} (ID: {new_role.id})")
        else:
            # Ensure is_system_role flag is True
            if not existing.is_system_role:
                existing.is_system_role = True
                needs_commit = True
            # Update permissions if empty
            if not existing.permissions and role_def["permissions"]:
                existing.permissions = role_def["permissions"]
                needs_commit = True
            role_map[name] = existing

    if needs_commit:
        db.commit()

    return role_map


def get_or_create_system_role(db: Session, role_name: Union[RoleEnum, str]) -> Role:
    """
    Resolves a canonical system role by name.
    If the role is not yet present in the database, automatically and safely
    initializes the system roles and returns the requested role.
    Guarantees that RESIDENT, PROPERTY_MANAGER, STAFF, and SUPER_ADMIN are always resolvable.
    """
    clean_name = (
        role_name.value
        if isinstance(role_name, RoleEnum)
        else str(role_name).strip().upper()
    )

    # 1. Direct query
    role = db.scalar(sa.select(Role).where(Role.name == clean_name))
    if role:
        return role

    # 2. Not found: run idempotent system role initialization
    logger.warning(
        f"[RoleService] System role '{clean_name}' was not found in database. Initializing system roles..."
    )
    roles = ensure_system_roles_exist(db)
    if clean_name in roles:
        return roles[clean_name]

    # 3. Re-query in case of transaction isolation / concurrent insertion
    role = db.scalar(sa.select(Role).where(Role.name == clean_name))
    if role:
        return role

    # 4. Fallback creation for any unrecognized role name
    fallback = Role(
        id=uuid.uuid4(),
        name=clean_name,
        display_name=clean_name.replace("_", " ").title(),
        description=f"System role for {clean_name}",
        is_system_role=True,
        permissions=ROLE_PERMISSIONS.get(clean_name, []),
    )
    db.add(fallback)
    db.commit()
    db.refresh(fallback)
    logger.info(f"[RoleService] Created fallback system role: {clean_name}")
    return fallback
