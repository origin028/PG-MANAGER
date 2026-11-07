"""SMTP e-mail delivery.

Delivery is only attempted when ``EMAIL_ENABLED`` is true and the required SMTP
settings are present. Every function returns a boolean so callers never claim a
message was delivered when no SMTP transport actually ran.
"""

from __future__ import annotations

import smtplib
from email.message import EmailMessage

from app.core.config import settings
from app.core.logging import logger


def send_email(to_address: str, subject: str, body: str) -> bool:
    """Sends a plain-text e-mail through the configured SMTP server.

    Returns ``True`` only when the SMTP server accepted the message. Missing
    configuration, a disabled transport, or a transport error returns ``False``
    and is logged. No exception is raised so registration can still complete
    and the caller can report the real delivery state.
    """
    if not settings.EMAIL_ENABLED:
        logger.warning(
            "Email delivery skipped: EMAIL_ENABLED is false. "
            "Configure SMTP settings and set EMAIL_ENABLED=true to enable delivery."
        )
        return False

    if not settings.SMTP_HOST or not settings.EMAIL_FROM:
        logger.error(
            "Email delivery skipped: SMTP_HOST and EMAIL_FROM must be configured "
            "when EMAIL_ENABLED is true."
        )
        return False

    message = EmailMessage()
    message["From"] = settings.EMAIL_FROM
    message["To"] = to_address
    message["Subject"] = subject
    message.set_content(body)

    try:
        with smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT, timeout=10) as smtp:
            smtp.ehlo()
            if settings.SMTP_PORT != 25:
                smtp.starttls()
                smtp.ehlo()
            if settings.SMTP_USER:
                smtp.login(settings.SMTP_USER, settings.SMTP_PASSWORD)
            smtp.send_message(message)
        logger.info(f"Email '{subject}' delivered to {to_address}.")
        return True
    except Exception as exc:  # pragma: no cover - depends on external SMTP server
        logger.error(f"Email delivery to {to_address} failed: {exc}")
        return False


def send_otp_email(to_address: str, otp: str) -> bool:
    """Sends a one-time registration verification code."""
    body = (
        "Welcome to Origin PG Management.\n\n"
        f"Your verification code is: {otp}\n\n"
        f"This code expires in {settings.OTP_EXPIRE_MINUTES} minutes. "
        "If you did not request this code, you can ignore this message.\n"
    )
    return send_email(to_address, "Verify your Origin PG Management account", body)
