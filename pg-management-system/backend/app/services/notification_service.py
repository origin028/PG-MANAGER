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
    ) -> Notification:
        """Enqueues or dispatches a notification record."""
        notification = Notification(
            user_id=user_id,
            title=title,
            body=body,
            channel=channel,
            status="PENDING",
        )
        self.db.add(notification)
        self.db.commit()
        self.db.refresh(notification)
        logger.info(f"Notification queued: [{channel}] {title} for user {user_id}")
        return notification
