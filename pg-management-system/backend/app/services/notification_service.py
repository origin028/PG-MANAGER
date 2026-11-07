import uuid
from typing import Optional
from sqlalchemy.orm import Session

from app.core.logging import logger
from app.models.notification import Notification


class NotificationService:
    def __init__(self, db: Session):
        self.db = db

    def dispatch(
        self,
        user_id: uuid.UUID,
        title: str,
        body: str,
        channel: str = "PUSH",
    ) -> Optional[Notification]:
        """
        Enqueues or dispatches a notification record safely without crashing caller transactions.
        Uses a nested transaction savepoint so notification failures roll back ONLY the nested
        savepoint and never abort or roll back outer caller transactions.
        """
        try:
            with self.db.begin_nested():
                notification = Notification(
                    user_id=user_id,
                    title=title,
                    body=body,
                    channel=channel,
                    status="PENDING",
                )
                self.db.add(notification)
                self.db.flush()
            # Savepoint was successfully committed/released.
            # Do NOT call self.db.commit() here to avoid prematurely committing outer caller changes.
            logger.info(f"Notification queued: [{channel}] {title} for user {user_id}")
            return notification
        except Exception as err:
            # The begin_nested() context manager (__exit__) automatically rolled back to the savepoint.
            # CRITICAL: Do NOT call self.db.rollback() here because that would roll back the outer
            # transaction and discard the caller's pending database changes.
            logger.warning(f"[NotificationService] Failed to queue notification for user {user_id}: {err}")
            return None
