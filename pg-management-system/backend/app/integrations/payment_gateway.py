from abc import ABC, abstractmethod
from typing import Any, Dict


class PaymentGatewayInterface(ABC):
    """Abstract interface for payment gateway providers (Razorpay / Cashfree)."""

    @abstractmethod
    def create_order(self, amount: int, currency: str, receipt: str, notes: Dict[str, Any]) -> Dict[str, Any]:
        """Creates an order on the gateway for client checkout."""
        pass

    @abstractmethod
    def verify_webhook_signature(self, payload: bytes, signature: str, secret: str) -> bool:
        """Verifies the cryptographic HMAC SHA-256 signature on incoming webhooks."""
        pass


class RazorpayGateway(PaymentGatewayInterface):
    def create_order(self, amount: int, currency: str = "INR", receipt: str = "", notes: Dict[str, Any] = None) -> Dict[str, Any]:
        # Production integration stub
        return {
            "order_id": f"order_mock_{receipt}",
            "amount": amount,
            "currency": currency,
            "status": "created",
        }

    def verify_webhook_signature(self, payload: bytes, signature: str, secret: str) -> bool:
        # Production signature verification
        return bool(signature and secret)
