import abc
import json
import re
import smtplib
import socket
import ssl
import urllib.error
import urllib.request
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
    """
    Standard production-grade SMTP email delivery provider.
    Connects to external SMTP server using configured TLS, SSL, host, and port.
    Never exposes raw secrets or unhashed OTP codes in logs.
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
        self.user = username if username is not None else (settings.SMTP_USERNAME or settings.SMTP_USER)
        self.password = password if password is not None else settings.SMTP_PASSWORD
        self.from_email = from_email if from_email is not None else settings.SMTP_FROM_EMAIL
        self.from_name = from_name if from_name is not None else settings.SMTP_FROM_NAME
        self.use_tls = use_tls if use_tls is not None else getattr(settings, "SMTP_USE_TLS", settings.SMTP_TLS)

    def send_email(
        self,
        to_email: str,
        subject: str,
        body_text: str,
        body_html: Optional[str] = None,
    ) -> bool:
        if not self.host or self.host == "localhost":
            logger.error("[SMTPEmailProvider] SMTP_HOST is not configured.")
            raise EmailDeliveryError("Email delivery service host is not configured.")

        if not self.password and self.host != "localhost":
            logger.error("[SMTPEmailProvider] SMTP_PASSWORD is not configured.")
            raise EmailDeliveryError("Failed to send verification email: SMTP password is not configured on the server.")

        msg = EmailMessage()
        msg["Subject"] = subject
        msg["From"] = f"{self.from_name} <{self.from_email}>"
        msg["To"] = to_email.strip()
        msg.set_content(body_text)

        if body_html:
            msg.add_alternative(body_html, subtype="html")

        context = ssl.create_default_context()
        ports = [self.port]
        alt_port = 465 if self.port != 465 else 587
        if alt_port not in ports:
            ports.append(alt_port)

        last_exc = None
        for attempt_port in ports:
            try:
                if attempt_port == 465:
                    # Direct SSL (SMTPS)
                    with smtplib.SMTP_SSL(self.host, attempt_port, timeout=15, context=context) as server:
                        if self.user and self.password:
                            server.login(self.user, self.password)
                        server.send_message(msg)
                else:
                    # Standard SMTP with STARTTLS
                    with smtplib.SMTP(self.host, attempt_port, timeout=15) as server:
                        if self.use_tls:
                            server.starttls(context=context)
                        if self.user and self.password:
                            server.login(self.user, self.password)
                        server.send_message(msg)

                masked = mask_email(to_email)
                logger.info(f"[SMTPEmailProvider] Email delivered successfully to {masked} via port {attempt_port} | Subject: '{subject}'")
                return True
            except smtplib.SMTPAuthenticationError as exc:
                masked = mask_email(to_email)
                logger.error(f"[SMTPEmailProvider] SMTP authentication error delivering to {masked}: {exc}")
                raise EmailDeliveryError(f"Failed to send verification email: SMTP authentication failed: {exc}") from exc
            except smtplib.SMTPRecipientsRefused as exc:
                masked = mask_email(to_email)
                logger.error(f"[SMTPEmailProvider] SMTP recipient refused {masked}: {exc}")
                raise BadRequestError(f"Invalid email address. The recipient was refused by mail server: {exc}") from exc
            except Exception as exc:
                last_exc = exc
                masked = mask_email(to_email)
                logger.warning(
                    f"[SMTPEmailProvider] SMTP attempt on {self.host}:{attempt_port} failed for {masked}: {exc}."
                )

        masked = mask_email(to_email)
        logger.error(f"[SMTPEmailProvider] All SMTP attempts failed for {masked}: {last_exc}")
        err_msg = str(last_exc)
        if "timed out" in err_msg.lower() or "timeout" in err_msg.lower():
            raise EmailDeliveryError(f"SMTP connection timed out: {last_exc}. Cloud hosting may be blocking outbound SMTP ports.") from last_exc
        raise EmailDeliveryError(f"Failed to send verification email. SMTP delivery error: {last_exc}") from last_exc


class BrevoEmailProvider(EmailProvider):
    """
    HTTPS API email delivery provider using Brevo (formerly Sendinblue - https://brevo.com).
    Operates over port 443 (HTTPS), avoiding cloud firewall blocks on SMTP ports 25/465/587.

    Free Tier Features:
    - 300 free transactional emails per day forever.
    - Zero cost, zero credit card required.
    - Allows sending to ANY external recipient email address (Gmail, Yahoo, Outlook, custom).
    - Requires ONLY a single verified sender email address (e.g. tharadrataher@gmail.com verified via OTP link).
    - DOES NOT REQUIRE PURCHASING OR OWNING A CUSTOM DOMAIN.
    - Zero external pip dependencies (uses Python standard library urllib.request).
    """
    is_mock: bool = False

    def __init__(
        self,
        api_key: Optional[str] = None,
        from_email: Optional[str] = None,
        from_name: Optional[str] = None,
    ):
        self.api_key = (api_key or getattr(settings, "BREVO_API_KEY", "") or "").strip()
        self.from_email = (
            from_email
            or getattr(settings, "BREVO_FROM_EMAIL", None)
            or settings.SMTP_FROM_EMAIL
            or "tharadrataher@gmail.com"
        ).strip()
        self.from_name = (from_name or settings.SMTP_FROM_NAME or "Origin PG Living").strip()

    def send_email(
        self,
        to_email: str,
        subject: str,
        body_text: str,
        body_html: Optional[str] = None,
    ) -> bool:
        if not self.api_key:
            logger.error("[BrevoEmailProvider] BREVO_API_KEY is not configured on the server.")
            raise EmailDeliveryError("BREVO_API_KEY is not configured on the server.")

        payload = {
            "sender": {
                "name": self.from_name,
                "email": self.from_email,
            },
            "to": [
                {
                    "email": to_email.strip(),
                }
            ],
            "subject": subject,
            "textContent": body_text,
        }
        if body_html:
            payload["htmlContent"] = body_html

        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(
            "https://api.brevo.com/v3/smtp/email",
            data=data,
            headers={
                "api-key": self.api_key,
                "Content-Type": "application/json",
                "Accept": "application/json",
                "User-Agent": "OriginPG-Living/1.0",
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                if 200 <= resp.status < 300:
                    masked = mask_email(to_email)
                    logger.info(f"[BrevoEmailProvider] Email delivered successfully to {masked} | Subject: '{subject}'")
                    return True
        except urllib.error.HTTPError as exc:
            err_body = exc.read().decode("utf-8", errors="replace")
            masked = mask_email(to_email)
            logger.error(f"[BrevoEmailProvider] HTTP {exc.code} delivering to {masked}: {err_body}")

            err_msg = ""
            try:
                parsed = json.loads(err_body)
                err_msg = parsed.get("message") or parsed.get("code") or ""
            except Exception:
                err_msg = err_body[:200]

            if exc.code == 401:
                reason = "Brevo HTTPS delivery unauthorized (HTTP 401): invalid or expired BREVO_API_KEY."
            elif exc.code == 403:
                reason = f"Brevo HTTPS delivery forbidden (HTTP 403): {err_msg or 'sender address not verified in Brevo dashboard'}"
            elif exc.code == 400:
                reason = f"Brevo HTTPS delivery rejected (HTTP 400): {err_msg}"
            elif exc.code == 429:
                reason = f"Brevo daily sending limit reached (HTTP 429): {err_msg}"
            else:
                reason = f"Brevo HTTPS delivery failed with HTTP {exc.code}: {err_msg}"

            raise EmailDeliveryError(reason) from exc
        except Exception as exc:
            masked = mask_email(to_email)
            logger.error(f"[BrevoEmailProvider] Failed to deliver email to {masked}: {exc}")
            raise EmailDeliveryError(f"Failed to deliver verification email via HTTPS: {exc}") from exc


class SendGridEmailProvider(EmailProvider):
    """
    HTTPS API email delivery provider using SendGrid (https://sendgrid.com).
    Operates over port 443 (HTTPS), avoiding cloud firewall blocks on SMTP ports.
    Supports Single Sender Verification without purchasing a domain.
    Free tier allows 100 emails/day forever.
    """
    is_mock: bool = False

    def __init__(
        self,
        api_key: Optional[str] = None,
        from_email: Optional[str] = None,
        from_name: Optional[str] = None,
    ):
        self.api_key = (api_key or getattr(settings, "SENDGRID_API_KEY", "") or "").strip()
        self.from_email = (
            from_email
            or getattr(settings, "SENDGRID_FROM_EMAIL", None)
            or settings.SMTP_FROM_EMAIL
            or "tharadrataher@gmail.com"
        ).strip()
        self.from_name = (from_name or settings.SMTP_FROM_NAME or "Origin PG Living").strip()

    def send_email(
        self,
        to_email: str,
        subject: str,
        body_text: str,
        body_html: Optional[str] = None,
    ) -> bool:
        if not self.api_key:
            logger.error("[SendGridEmailProvider] SENDGRID_API_KEY is not configured on the server.")
            raise EmailDeliveryError("SENDGRID_API_KEY is not configured on the server.")

        content = [{"type": "text/plain", "value": body_text}]
        if body_html:
            content.append({"type": "text/html", "value": body_html})

        payload = {
            "personalizations": [{"to": [{"email": to_email.strip()}]}],
            "from": {"email": self.from_email, "name": self.from_name},
            "subject": subject,
            "content": content,
        }

        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(
            "https://api.sendgrid.com/v3/mail/send",
            data=data,
            headers={
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json",
                "User-Agent": "OriginPG-Living/1.0",
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                if 200 <= resp.status < 300:
                    masked = mask_email(to_email)
                    logger.info(f"[SendGridEmailProvider] Email delivered successfully to {masked} | Subject: '{subject}'")
                    return True
        except urllib.error.HTTPError as exc:
            err_body = exc.read().decode("utf-8", errors="replace")
            masked = mask_email(to_email)
            logger.error(f"[SendGridEmailProvider] HTTP {exc.code} delivering to {masked}: {err_body}")
            raise EmailDeliveryError(f"SendGrid HTTPS delivery failed (HTTP {exc.code}): {err_body[:200]}") from exc
        except Exception as exc:
            masked = mask_email(to_email)
            logger.error(f"[SendGridEmailProvider] Failed to deliver email to {masked}: {exc}")
            raise EmailDeliveryError(f"Failed to deliver verification email via HTTPS: {exc}") from exc


class ResendEmailProvider(EmailProvider):
    """
    HTTPS API email delivery provider using Resend (https://resend.com).
    Operates over port 443 (HTTPS), avoiding cloud firewall blocks on SMTP ports 25/465/587 (e.g., Render Free tier).
    Requires zero external pip dependencies (uses Python standard library urllib.request).
    """
    is_mock: bool = False

    def __init__(
        self,
        api_key: Optional[str] = None,
        from_email: Optional[str] = None,
        from_name: Optional[str] = None,
    ):
        self.api_key = (api_key or getattr(settings, "RESEND_API_KEY", "") or "").strip()
        configured_from = (
            from_email
            or getattr(settings, "RESEND_FROM_EMAIL", None)
            or settings.SMTP_FROM_EMAIL
            or "onboarding@resend.dev"
        ).strip()

        # Resend strictly forbids sending from public webmail domains (e.g. @gmail.com, @yahoo.com)
        # without domain verification, returning HTTP 403 Forbidden.
        # Fall back to Resend's sandbox domain if a public webmail domain is configured.
        public_webmail_domains = (
            "@gmail.com",
            "@yahoo.com",
            "@outlook.com",
            "@hotmail.com",
            "@icloud.com",
            "@live.com",
        )
        if any(configured_from.lower().endswith(dom) for dom in public_webmail_domains):
            logger.warning(
                f"[ResendEmailProvider] Configured from_email '{configured_from}' is a public webmail domain forbidden by Resend. "
                "Defaulting Resend sender to 'onboarding@resend.dev' to avoid HTTP 403."
            )
            self.from_email = "onboarding@resend.dev"
        else:
            self.from_email = configured_from

        self.from_name = (from_name or settings.SMTP_FROM_NAME or "Origin PG Living").strip()

    def send_email(
        self,
        to_email: str,
        subject: str,
        body_text: str,
        body_html: Optional[str] = None,
    ) -> bool:
        if not self.api_key:
            logger.error("[ResendEmailProvider] RESEND_API_KEY is not configured on the server.")
            raise EmailDeliveryError("RESEND_API_KEY is not configured on the server.")

        from_header = f"{self.from_name} <{self.from_email}>" if self.from_name else self.from_email
        payload = {
            "from": from_header,
            "to": [to_email.strip()],
            "subject": subject,
            "text": body_text,
        }
        if body_html:
            payload["html"] = body_html

        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(
            "https://api.resend.com/emails",
            data=data,
            headers={
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json",
                "User-Agent": "OriginPG-Living/1.0",
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                if 200 <= resp.status < 300:
                    masked = mask_email(to_email)
                    logger.info(f"[ResendEmailProvider] Email delivered successfully to {masked} | Subject: '{subject}'")
                    return True
        except urllib.error.HTTPError as exc:
            err_body = exc.read().decode("utf-8", errors="replace")
            masked = mask_email(to_email)
            logger.error(f"[ResendEmailProvider] HTTP {exc.code} delivering to {masked}: {err_body}")

            # Extract clean error message from Resend JSON response
            err_msg = ""
            try:
                parsed = json.loads(err_body)
                err_msg = parsed.get("message") or parsed.get("error") or ""
            except Exception:
                err_msg = err_body[:200]

            if exc.code == 403:
                reason = f"Resend HTTPS delivery forbidden (HTTP 403): {err_msg or 'domain/recipient not permitted on current Resend tier'}"
            elif exc.code == 401:
                reason = "Resend HTTPS delivery unauthorized (HTTP 401): invalid or expired RESEND_API_KEY."
            else:
                reason = f"Resend HTTPS delivery failed with HTTP {exc.code}: {err_msg}"

            raise EmailDeliveryError(reason) from exc
        except Exception as exc:
            masked = mask_email(to_email)
            logger.error(f"[ResendEmailProvider] Failed to deliver email to {masked}: {exc}")
            raise EmailDeliveryError(f"Failed to deliver verification email via HTTPS: {exc}") from exc


class ResilientEmailProvider(EmailProvider):
    """
    Composite provider that tries primary provider first, and automatically
    falls back to secondary provider(s) if primary encounters an error.
    Designed for production resilience across cloud firewalls and API restrictions.
    """
    def __init__(
        self,
        primary: EmailProvider,
        fallback: Optional[EmailProvider] = None,
        primary_name: Optional[str] = None,
        fallback_name: Optional[str] = None,
    ):
        self.primary = primary
        self.fallback = fallback
        self.primary_name = primary_name or primary.__class__.__name__
        self.fallback_name = fallback_name or (fallback.__class__.__name__ if fallback else "None")
        self.is_mock = getattr(primary, "is_mock", False) and (
            fallback is None or getattr(fallback, "is_mock", False)
        )

    def send_email(
        self,
        to_email: str,
        subject: str,
        body_text: str,
        body_html: Optional[str] = None,
    ) -> bool:
        masked = mask_email(to_email)
        try:
            return self.primary.send_email(
                to_email=to_email,
                subject=subject,
                body_text=body_text,
                body_html=body_html,
            )
        except Exception as exc:
            if not self.fallback:
                logger.error(
                    f"[ResilientEmailProvider] Primary provider ({self.primary_name}) failed for {masked}: {exc}. "
                    "No fallback provider available."
                )
                raise

            logger.warning(
                f"[ResilientEmailProvider] Primary provider ({self.primary_name}) failed for {masked}: {exc}. "
                f"Engaging automatic fallback to ({self.fallback_name})..."
            )
            try:
                res = self.fallback.send_email(
                    to_email=to_email,
                    subject=subject,
                    body_text=body_text,
                    body_html=body_html,
                )
                logger.info(
                    f"[ResilientEmailProvider] Fallback provider ({self.fallback_name}) successfully delivered email to {masked}!"
                )
                return res
            except Exception as fb_exc:
                logger.error(
                    f"[ResilientEmailProvider] Both primary ({self.primary_name}) and fallback ({self.fallback_name}) failed for {masked}. "
                    f"Primary: {exc} | Fallback: {fb_exc}"
                )
                raise EmailDeliveryError(
                    f"Email delivery failed across all providers. Primary ({self.primary_name}): {exc} | Fallback ({self.fallback_name}): {fb_exc}"
                ) from fb_exc


def get_email_provider() -> EmailProvider:
    """
    Factory returning active EmailProvider based on configuration and environment.
    Supports Brevo (free external recipient delivery without domain), SendGrid, Resend, and SMTP.
    Configurable via EMAIL_PROVIDER: "BREVO", "SENDGRID", "RESEND", "SMTP", "AUTO", or "MOCK".
    """
    provider_name = getattr(settings, "EMAIL_PROVIDER", "").strip().upper()
    env = getattr(settings, "ENVIRONMENT", "").strip().lower()

    has_brevo_key = bool(getattr(settings, "BREVO_API_KEY", None))
    has_sendgrid_key = bool(getattr(settings, "SENDGRID_API_KEY", None))
    has_resend_key = bool(getattr(settings, "RESEND_API_KEY", None))
    has_smtp_creds = bool(
        settings.SMTP_HOST
        and settings.SMTP_HOST != "localhost"
        and (settings.SMTP_PASSWORD or settings.SMTP_USERNAME or settings.SMTP_USER)
    )

    if provider_name == "MOCK" or (
        env in ("development", "test", "testing")
        and not has_brevo_key
        and not has_sendgrid_key
        and not has_resend_key
        and not has_smtp_creds
    ):
        return DevMockEmailProvider()

    # Explicit provider selection
    if provider_name == "BREVO" or (has_brevo_key and provider_name not in ("RESEND", "SENDGRID", "SMTP")):
        primary = BrevoEmailProvider()
        fallback = None
        if has_resend_key:
            fallback = ResendEmailProvider()
        elif has_smtp_creds:
            fallback = SMTPEmailProvider()
        return ResilientEmailProvider(primary=primary, fallback=fallback) if fallback else primary

    if provider_name == "SENDGRID" or (has_sendgrid_key and provider_name not in ("RESEND", "BREVO", "SMTP")):
        primary = SendGridEmailProvider()
        fallback = BrevoEmailProvider() if has_brevo_key else (ResendEmailProvider() if has_resend_key else None)
        return ResilientEmailProvider(primary=primary, fallback=fallback) if fallback else primary

    # Multi-provider Resilient chaining
    configured_providers = []
    if has_brevo_key:
        configured_providers.append(BrevoEmailProvider())
    if has_sendgrid_key:
        configured_providers.append(SendGridEmailProvider())
    if has_resend_key:
        configured_providers.append(ResendEmailProvider())
    if has_smtp_creds:
        configured_providers.append(SMTPEmailProvider())

    if len(configured_providers) >= 2:
        if provider_name == "RESEND":
            fallback = BrevoEmailProvider() if has_brevo_key else SMTPEmailProvider()
            return ResilientEmailProvider(primary=ResendEmailProvider(), fallback=fallback)
        elif provider_name == "SMTP":
            fallback = BrevoEmailProvider() if has_brevo_key else ResendEmailProvider()
            return ResilientEmailProvider(primary=SMTPEmailProvider(), fallback=fallback)
        else:
            return ResilientEmailProvider(primary=configured_providers[0], fallback=configured_providers[1])

    if configured_providers:
        return configured_providers[0]

    return DevMockEmailProvider()
