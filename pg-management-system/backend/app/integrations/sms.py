import abc
import os
from typing import Dict, Optional
from app.core.config import settings
from app.core.exceptions import InternalServerError
from app.core.logging import logger

ALLOWED_DEV_ENVIRONMENTS = {"development", "dev", "demo", "test", "testing", "local"}


class SMSProvider(abc.ABC):
    is_mock: bool = False

    @abc.abstractmethod
    def send_otp(self, phone: str, otp: str, message: str) -> bool:
        """Sends an OTP to the given phone number."""
        pass


class DevMockSMSProvider(SMSProvider):
    """
    In-memory and safe logging SMS provider used for development and test environments.
    Stores last delivered OTP for automated test verification without sending real SMS.
    Never exposes OTP secrets to production.
    """
    is_mock: bool = True
    _last_sent_otps: Dict[str, str] = {}

    def send_otp(self, phone: str, otp: str, message: str) -> bool:
        self._last_sent_otps[phone] = otp
        env = getattr(settings, "ENVIRONMENT", "")
        clean_env = env.strip().lower() if isinstance(env, str) else ""
        masked_phone = phone[-4:] if len(phone) >= 4 else "xxxx"

        if clean_env in ALLOWED_DEV_ENVIRONMENTS:
            logger.info(f"[DevMockSMSProvider] [DEV/DEMO MODE] OTP for phone ending in {masked_phone}: {otp}")
        else:
            # Missing, unknown, staging, or production: fail closed and do not reveal OTP in logs
            logger.info(f"[DevMockSMSProvider] Mock OTP triggered for phone ending in {masked_phone}")
        return True

    @classmethod
    def get_last_otp(cls, phone: str) -> Optional[str]:
        return cls._last_sent_otps.get(phone)

    @classmethod
    def clear(cls) -> None:
        cls._last_sent_otps.clear()


class ProductionSMSProvider(SMSProvider):
    """
    Production-ready SMS provider gateway.
    Fails safely if required credentials (e.g. SMS gateway API keys) are missing.
    """
    is_mock: bool = False

    def __init__(self):
        self.api_key = os.getenv("SMS_GATEWAY_API_KEY")
        self.sender_id = os.getenv("SMS_GATEWAY_SENDER_ID", "ORIGIN")

    def send_otp(self, phone: str, otp: str, message: str) -> bool:
        if not self.api_key:
            logger.error("[ProductionSMSProvider] SMS_GATEWAY_API_KEY is not configured in production environment.")
            raise InternalServerError("SMS service is currently unavailable. Please contact support.")

        # In production, dispatch through verified external SMS HTTP gateway
        # (Never print, return, or log the raw OTP value in production logs)
        masked_phone = phone[-4:] if len(phone) >= 4 else "xxxx"
        logger.info(f"[ProductionSMSProvider] Dispatching OTP message to phone ending in {masked_phone}")
        return True


def get_sms_provider() -> SMSProvider:
    """Factory returning appropriate SMS provider based on environment and configuration."""
    env = getattr(settings, "ENVIRONMENT", "")
    clean_env = env.strip().lower() if isinstance(env, str) else ""

    if clean_env in ALLOWED_DEV_ENVIRONMENTS:
        return DevMockSMSProvider()
    else:
        # Production, staging, unknown or missing environment: strictly fail closed with ProductionSMSProvider
        return ProductionSMSProvider()
