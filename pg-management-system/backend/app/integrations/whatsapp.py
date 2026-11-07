from abc import ABC, abstractmethod
from typing import Any


class WhatsAppProvider(ABC):
    """WhatsApp Business provider boundary; templates are required outside the 24-hour window."""

    @abstractmethod
    def send_template(self, to_phone: str, template: str, parameters: list[str]) -> str:
        """Return the provider message id or raise; never accept payment credentials."""


class WhatsAppCloudProvider(WhatsAppProvider):
    def __init__(self, phone_number_id: str, access_token: str):
        if not phone_number_id or not access_token:
            raise ValueError("WhatsApp Business Platform is not configured.")
        self.phone_number_id = phone_number_id
        self.access_token = access_token

    def send_template(self, to_phone: str, template: str, parameters: list[str]) -> str:
        if not template:
            raise ValueError("An approved WhatsApp template is required.")
        try:
            import requests
        except ImportError as exc:
            raise RuntimeError("requests is required for WhatsApp delivery.") from exc
        response = requests.post(
            f"https://graph.facebook.com/v20.0/{self.phone_number_id}/messages",
            headers={"Authorization": f"Bearer {self.access_token}"},
            json={"messaging_product": "whatsapp", "to": to_phone, "type": "template",
                  "template": {"name": template, "language": {"code": "en"},
                               "components": [{"type": "body", "parameters": [
                                   {"type": "text", "text": value} for value in parameters
                               ]}]}},
            timeout=15,
        )
        response.raise_for_status()
        return response.json()["messages"][0]["id"]
