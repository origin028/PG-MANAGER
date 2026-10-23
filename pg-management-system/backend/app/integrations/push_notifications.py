from abc import ABC, abstractmethod
from typing import Any, Dict


class PushNotificationProvider(ABC):
    """Abstract interface for push notifications targeting Flutter mobile applications."""

    @abstractmethod
    def send_push(self, device_token: str, title: str, body: str, payload: Dict[str, Any]) -> bool:
        pass


class MockPushProvider(PushNotificationProvider):
    def send_push(self, device_token: str, title: str, body: str, payload: Dict[str, Any]) -> bool:
        return True
