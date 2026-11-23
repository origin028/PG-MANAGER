import uuid
from typing import Any, Dict, Optional
import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.core.exceptions import BadRequestError, ConflictError, NotFoundError, PermissionDeniedError
from app.core.logging import logger
from app.integrations.email import mask_email
from app.models.pending_registration import PendingResidentRegistration
from app.models.user import User
from app.repositories.user_repository import UserRepository
from app.services.audit_service import record_audit_log


class UserService:
    def __init__(self, db: Session):
        self.db = db
        self.repo = UserRepository(db)

    def update_user_email(
        self,
        user_id: uuid.UUID,
        new_email: str,
        current_admin: User,
        reason: Optional[str] = None,
        ip_address: Optional[str] = None,
        user_agent: Optional[str] = None,
    ) -> Dict[str, Any]:
        """
        Updates the email address of a target user/resident in an atomic database transaction.
        Enforces tenant isolation, uniqueness, normalization, staged registration synchronization,
        and records an immutable audit log.
        """
        # 1. Look up target user
        target_user = self.repo.get_by_id(user_id)
        if not target_user:
            raise NotFoundError(f"User with ID '{user_id}' not found.")

        # 2. Enforce company boundary (tenant isolation)
        if target_user.company_id != current_admin.company_id:
            raise PermissionDeniedError("Cannot modify a user outside your company organization.")

        # 3. Normalize new email
        norm_email = new_email.strip().lower()
        old_email = target_user.email

        # 4. Check if new email is identical to existing email
        if old_email and old_email.strip().lower() == norm_email:
            raise BadRequestError(f"User already has email address '{norm_email}'.")

        # 5. Check duplicate email usage across all other users in system
        existing_user = self.repo.get_by_email_exclude_user(norm_email, target_user.id)
        if existing_user:
            raise ConflictError(f"Email address '{norm_email}' is already in use by another user.")

        # 6. Resolve target property if user has an associated resident profile
        resident_profile = target_user.resident_profile
        target_prop_id = resident_profile.property_id if resident_profile else None

        try:
            # 7. Synchronize staged PendingResidentRegistration if present
            pending = self.db.scalar(
                sa.select(PendingResidentRegistration).where(
                    PendingResidentRegistration.phone == target_user.phone
                )
            )
            if pending:
                pending.email = norm_email
                if isinstance(pending.registration_data, dict):
                    reg_dict = dict(pending.registration_data)
                    reg_dict["email"] = norm_email
                    pending.registration_data = reg_dict

            # 8. Update User.email (the authoritative source for resident OTP login)
            target_user.email = norm_email

            # 9. Record Audit Log in the SAME database transaction
            record_audit_log(
                db=self.db,
                action="USER_EMAIL_UPDATE",
                resource_type="user",
                user_id=current_admin.id,
                user_email=current_admin.email,
                user_role=current_admin.role.name,
                company_id=target_user.company_id,
                property_id=target_prop_id,
                resource_id=str(target_user.id),
                details={
                    "resident_user_id": str(target_user.id),
                    "resident_name": target_user.full_name,
                    "resident_phone": target_user.phone,
                    "resident_role": target_user.role.name,
                    "old_email": old_email,
                    "new_email": norm_email,
                    "reason": reason or "Administrative email correction",
                },
                ip_address=ip_address,
                user_agent=user_agent,
                commit=False,
            )

            # 10. Atomic transaction commit
            self.db.commit()
            self.db.refresh(target_user)

        except Exception as exc:
            self.db.rollback()
            logger.error(f"Failed to update user email for {target_user.id}: {exc}", exc_info=True)
            raise exc

        # 11. Safe logging with masked emails
        logger.info(
            f"[UserService] Super admin '{mask_email(current_admin.email)}' ({current_admin.id}) "
            f"updated email for user '{target_user.full_name}' ({target_user.id}) "
            f"from '{mask_email(old_email)}' to '{mask_email(norm_email)}'."
        )

        return {
            "user_id": target_user.id,
            "full_name": target_user.full_name,
            "phone": target_user.phone,
            "old_email": old_email,
            "new_email": norm_email,
            "role_name": target_user.role.name,
            "approval_status": target_user.approval_status,
            "updated_at": target_user.updated_at,
        }
