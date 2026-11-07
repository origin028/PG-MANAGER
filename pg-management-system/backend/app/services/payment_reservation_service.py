from datetime import datetime, timezone
import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.models.payment import Payment


class PaymentReservationService:
    """Idempotently expires only unconfirmed, time-limited payment requests."""
    def __init__(self, db: Session):
        self.db = db

    def expire_due(self, now: datetime | None = None) -> int:
        now = now or datetime.now(timezone.utc)
        result = self.db.execute(
            sa.update(Payment)
            .execution_options(synchronize_session=False)
            .where(Payment.status == "PENDING", Payment.reservation_expires_at.is_not(None), Payment.reservation_expires_at <= now)
            .values(status="EXPIRED")
        )
        self.db.commit()
        return result.rowcount
