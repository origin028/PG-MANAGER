import abc
import re
import smtplib
import ssl
from email.message import EmailMessage
from typing import Dict, Optional

from app.core.config import settings
from app.core.exceptions import BadRequestError, EmailDeliveryError, InternalServerError
from app.core.logging import logger

ALLOWED_DEV_ENVIRONMENTS = {"development", "dev", "demo", "test", "testing", "local"}


def mask_email(email: str) -> str:
    """Masks an email for safe logging and responses (e.g., r***h@example.com)."""
    if not email or "@" not in email:
        return "****"
    user_part, domain = email.split("@", 1)
    if len(user_part) <= 2:
        masked_user = user_part[0] + "*"
    else:
        masked_user = user_part[0] + "*" * (len(user_part) - 2) + user_part[-1]
    return f"{masked_user}@{domain}"


class EmailProvider(abc.ABC):
    is_mock: bool = False

    @abc.abstractmethod
    def send_email(
        self,
        to_email: str,
        subject: str,
        body_text: str,
        body_html: Optional[str] = None,
    ) -> bool:
        """Sends an email to the recipient."""
        pass


class DevMockEmailProvider(EmailProvider):
    """
    In-memory mock email provider for development and testing.
    Records dispatched emails and OTPs for automated test assertions.
    Never exposes plain secrets in production logs.
    """
    is_mock: bool = True
    _last_sent_emails: Dict[str, dict] = {}
    _last_sent_otps: Dict[str, str] = {}

    def send_email(
        self,
        to_email: str,
        subject: str,
        body_text: str,
        body_html: Optional[str] = None,
    ) -> bool:
        normalized_email = to_email.strip().lower()
        self._last_sent_emails[normalized_email] = {
            "to": normalized_email,
            "subject": subject,
            "body_text": body_text,
            "body_html": body_html,
        }

        # Extract 6-digit OTP code from body if present
        otp_match = re.search(r"\b\d{6}\b", body_text)
        if otp_match:
            self._last_sent_otps[normalized_email] = otp_match.group(0)

        env = getattr(settings, "ENVIRONMENT", "")
        clean_env = env.strip().lower() if isinstance(env, str) else ""
        masked = mask_email(normalized_email)
        is_debug = bool(getattr(settings, "DEBUG", False))

        if clean_env in ALLOWED_DEV_ENVIRONMENTS and is_debug:
            otp_val = otp_match.group(0) if otp_match else "N/A"
            logger.info(f"[DevMockEmailProvider] [DEV/DEMO MODE] Email sent to {masked} | Subject: '{subject}' | OTP: {otp_val}")
        else:
            logger.info(f"[DevMockEmailProvider] Mock email dispatched to {masked} | Subject: '{subject}'")

        return True

    @classmethod
    def get_last_otp(cls, to_email: str) -> Optional[str]:
        return cls._last_sent_otps.get(to_email.strip().lower())

    @classmethod
    def get_last_email(cls, to_email: str) -> Optional[dict]:
        return cls._last_sent_emails.get(to_email.strip().lower())

    @classmethod
    def clear(cls) -> None:
        cls._last_sent_emails.clear()
        cls._last_sent_otps.clear()


class SMTPEmailProvider(EmailProvider):
    """Production SMTP delivery (Gmail / Google Workspace / any SMTP relay).

    Port 465 uses implicit SSL; any other port uses STARTTLS when SMTP_USE_TLS is true.
    Never logs secrets or OTP codes.
    """

    is_mock: bool = False

    def __init__(
        self,
        host: Optional[str] = None,
        port: Optional[int] = None,
        username: Optional[str] = None,
        password: Optional[str] = None,
        from_email: Optional[str] = None,
        from_name: Optional[str] = None,
        use_tls: Optional[bool] = None,
    ):
        self.host = host if host is not None else settings.SMTP_HOST
        self.port = port if port is not None else settings.SMTP_PORT
        self.user = username if username is not None else settings.SMTP_USERNAME
        self.password = password if password is not None else settings.SMTP_PASSWORD
        self.from_email = from_email if from_email is not None else settings.SMTP_FROM_EMAIL
        self.from_name = from_name if from_name is not None else settings.SMTP_FROM_NAME
        self.use_tls = use_tls if use_tls is not None else settings.SMTP_USE_TLS

    def send_email(
        self,
        to_email: str,
        subject: str,
        body_text: str,
        body_html: Optional[str] = None,
    ) -> bool:
        masked = mask_email(to_email)
        if not self.host or self.host == "localhost":
            logger.error("[SMTP] SMTP_HOST is not configured.")
            raise EmailDeliveryError("Email delivery service host is not configured.")
        if not self.password:
            logger.error("[SMTP] SMTP_PASSWORD is not configured.")
            raise EmailDeliveryError("Failed to send verification email: SMTP password is not configured on the server.")

        msg = EmailMessage()
        msg["Subject"] = subject
        msg["From"] = f"{self.from_name} <{self.from_email}>"
        msg["To"] = to_email.strip()
        msg.set_content(body_text)
        if body_html:
            msg.add_alternative(body_html, subtype="html")

        context = ssl.create_default_context()
        try:
            if self.port == 465:
                with smtplib.SMTP_SSL(self.host, self.port, timeout=15, context=context) as server:
                    if self.user:
                        server.login(self.user, self.password)
                    server.send_message(msg)
            else:
                with smtplib.SMTP(self.host, self.port, timeout=15) as server:
                    if self.use_tls:
                        server.starttls(context=context)
                    if self.user:
                        server.login(self.user, self.password)
                    server.send_message(msg)
        except smtplib.SMTPAuthenticationError as exc:
            logger.error(f"[SMTP] authentication failed delivering to {masked}: {exc}")
            raise EmailDeliveryError("Failed to send verification email: SMTP authentication failed.") from exc
        except smtplib.SMTPRecipientsRefused as exc:
            logger.error(f"[SMTP] recipient refused {masked}: {exc}")
            raise BadRequestError("Invalid email address. The recipient was refused by the mail server.") from exc
        except Exception as exc:
            logger.error(f"[SMTP] delivery to {masked} via {self.host}:{self.port} failed: {exc}")
            raise EmailDeliveryError(f"Failed to send verification email. SMTP delivery error: {exc}") from exc

        logger.info(f"[SMTP] delivered to {masked} | Subject: '{subject}'")
        return True


def get_email_provider() -> EmailProvider:
    """Returns the SMTP provider, or the in-memory mock outside production.

    EMAIL_PROVIDER is "SMTP" or "MOCK". The mock is refused in production by
    settings validation, so a missing configuration can never silently drop OTPs.
    """
    if (settings.EMAIL_PROVIDER or "").strip().upper() == "SMTP":
        return SMTPEmailProvider()
    return DevMockEmailProvider()
