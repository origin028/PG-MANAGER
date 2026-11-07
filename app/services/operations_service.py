"""Shared helpers for operational (complaints, expenses, staff) endpoints."""

from __future__ import annotations

import uuid
from typing import List, Optional

import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.core.exceptions import NotFoundError, PermissionDeniedError
from app.models.property import Property
from app.models.user import User, UserPropertyAccess


def get_permitted_property_ids(
    db: Session,
    user: User,
    target_property_id: Optional[uuid.UUID] = None,
) -> List[uuid.UUID]:
    """Returns the property IDs an administrative user may operate on.

    Residents are rejected here because operational modules are admin-facing.
    When ``target_property_id`` is supplied, access to it is verified and a
    permission error is raised for unassigned properties.
    """
    if user.role.name == "RESIDENT":
        raise PermissionDeniedError("Residents are not authorized for this operation.")

    if user.role.name == "SUPER_ADMIN":
        if target_property_id:
            prop = db.scalar(
                sa.select(Property).where(
                    Property.id == target_property_id,
                    Property.company_id == user.company_id,
                )
            )
            if not prop:
                raise NotFoundError(
                    f"Property with ID '{target_property_id}' not found in your company."
                )
            return [target_property_id]
        return list(
            db.scalars(
                sa.select(Property.id).where(
                    Property.company_id == user.company_id,
                    Property.is_active == True,
                )
            ).all()
        )

    assigned_ids = list(
        db.scalars(
            sa.select(UserPropertyAccess.property_id).where(
                UserPropertyAccess.user_id == user.id
            )
        ).all()
    )

    if target_property_id:
        if target_property_id not in assigned_ids:
            raise PermissionDeniedError(
                f"You do not have access rights for property ID '{target_property_id}'."
            )
        return [target_property_id]

    return assigned_ids
