"""Security deposit: record receipt and view the append-only ledger."""
import uuid
from decimal import Decimal
from typing import Optional

from fastapi import APIRouter, Depends, status
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.core.exceptions import NotFoundError
from app.db.session import get_db
from app.dependencies import require_roles, verify_property_access
from app.models.resident import Resident
from app.models.user import User
from app.schemas.common import APIResponse
from app.services.audit_service import record_audit_log
from app.services.deposit_service import DepositService, compute_exit_settlement

router = APIRouter()


class DepositReceived(BaseModel):
    amount: Decimal = Field(gt=0, max_digits=10, decimal_places=2)
    note: Optional[str] = Field(default=None, max_length=255)


def _load(db: Session, resident_id: uuid.UUID, user: User) -> Resident:
    resident = db.get(Resident, resident_id)
    if not resident:
        raise NotFoundError("Resident not found.")
    verify_property_access(resident.property_id, user, db)
    return resident


@router.post("/{resident_id}/deposit", status_code=status.HTTP_201_CREATED)
def record_deposit(
    resident_id: uuid.UUID,
    payload: DepositReceived,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Records a security deposit received from the resident (cash / UPI to the owner)."""
    resident = _load(db, resident_id, current_user)
    svc = DepositService(db)
    entry = svc.record_received(resident, current_user.company_id, payload.amount, payload.note, current_user.id)
    db.commit()
    record_audit_log(
        db=db, action="DEPOSIT_RECEIVED", resource_type="resident", user_id=current_user.id,
        user_email=current_user.email, user_role=current_user.role.name, property_id=resident.property_id,
        resource_id=str(resident.id), details={"amount": str(entry.amount)},
    )
    return APIResponse(
        success=True, message="Deposit recorded.",
        data={"deposit_held": str(svc.balance(resident.id)), "entry_id": str(entry.id)},
    )


@router.get("/{resident_id}/deposit", status_code=status.HTTP_200_OK)
def get_deposit(
    resident_id: uuid.UUID,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Ledger, current balance and what a move-out today would refund (50% policy)."""
    resident = _load(db, resident_id, current_user)
    svc = DepositService(db)
    held = svc.balance(resident.id)
    preview = compute_exit_settlement(held)
    return APIResponse(
        success=True, message="Deposit ledger retrieved.",
        data={
            "deposit_held": str(held),
            "refund_if_moving_out_today": str(preview.refund),
            "retained_by_policy": str(preview.forfeited),
            "entries": [
                {"type": e.entry_type, "amount": str(e.amount), "note": e.note, "at": e.created_at.isoformat()}
                for e in svc.entries(resident.id)
            ],
        },
    )
