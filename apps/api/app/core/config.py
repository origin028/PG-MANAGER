"""Typed application settings with fail-fast validation per environment.

Design rules
------------
* ``ENVIRONMENT`` defaults to ``production`` and ``DEBUG`` to ``False`` so a deploy
  that forgets an env var is closed, never open.
* In production the process REFUSES TO BOOT with a missing/weak secret, a wildcard
  CORS list, a mock provider, or a localhost database.
* Local development and tests set ``ENVIRONMENT=development|test`` explicitly
  (see ``.env.example`` and ``tests/conftest.py``).
"""
import base64
import hashlib
import json
import secrets
from pathlib import Path
from typing import List, Optional, Union

from pydantic import field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

DEV_ENVIRONMENTS = {"development", "dev", "local", "test", "testing", "demo"}
_DEV_DB_URL = "postgresql+psycopg://postgres:postgres@localhost:5432/pg_management"
_DEV_CORS = [
    "http://localhost:3000",
    "http://localhost:5173",
    "http://localhost:8080",
    "http://127.0.0.1:5173",
    "http://127.0.0.1:8080",
]


class Settings(BaseSettings):
    PROJECT_NAME: str = "Origin PG Management System API"
    VERSION: str = "2.0.0"
    API_V1_STR: str = "/api/v1"
    ENVIRONMENT: str = "production"
    DEBUG: bool = False

    # ---- Secrets -----------------------------------------------------------
    SECRET_KEY: str = ""  # JWT signing key (>= 32 chars in production)
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    REFRESH_TOKEN_EXPIRE_DAYS: int = 30
    # Fernet key (urlsafe base64, 32 bytes) used to encrypt KYC files at rest.
    ENCRYPTION_KEY: str = ""

    # Owner registration gate. Provide EITHER the plain key or its SHA-256 hex hash.
    ADMIN_REGISTRATION_SUPER_KEY: str = ""
    ADMIN_REGISTRATION_SUPER_KEY_HASH: str = ""

    # ---- Database ----------------------------------------------------------
    DATABASE_URL: str = ""

    # ---- Payments (unchanged behaviour; mock is blocked in production) -----
    PAYMENT_GATEWAY_PROVIDER: str = "AUTO"
    RAZORPAY_KEY_ID: str = ""
    RAZORPAY_KEY_SECRET: str = ""
    RAZORPAY_WEBHOOK_SECRET: str = ""
    PAYMENT_LINK_BASE_URL: str = "http://localhost:3000/pay"

    WHATSAPP_PROVIDER: str = ""
    WHATSAPP_PHONE_NUMBER_ID: str = ""
    WHATSAPP_ACCESS_TOKEN: str = ""
    WHATSAPP_PAYMENT_TEMPLATE: str = ""
    WHATSAPP_RECEIPT_TEMPLATE: str = ""

    UPI_PAYEE_VPA: str = "9886699258-3@ybl"
    UPI_PAYEE_NAME: str = "SMART GROUP PG'S"
    UPI_MERCHANT_VPA: Optional[str] = "9886699258-3@ybl"
    UPI_MERCHANT_NAME: Optional[str] = "SMART GROUP PG'S"
    UPI_MERCHANT_CODE: Optional[str] = None
    UPI_BANK_NAME: str = "Bank of Baroda"
    UPI_BANK_TERMINAL_ID: Optional[str] = None
    UPI_BANK_WEBHOOK_SECRET: str = ""
    UPI_VERIFICATION_PROVIDER_URL: str = ""
    UPI_BANK_API_KEY: str = ""

    # ---- Email (SMTP only; "MOCK" allowed outside production) --------------
    EMAIL_PROVIDER: str = "SMTP"
    SMTP_HOST: str = "smtp.gmail.com"
    SMTP_PORT: int = 587
    SMTP_USERNAME: str = ""
    SMTP_PASSWORD: str = ""
    SMTP_FROM_EMAIL: str = ""
    SMTP_FROM_NAME: str = "Origin PG Living"
    SMTP_USE_TLS: bool = True

    # ---- HTTP hardening ----------------------------------------------------
    CORS_ORIGINS: Union[List[str], str] = []
    TRUSTED_PROXY_IPS: str = "127.0.0.1"  # comma separated; "*" only behind a trusted LB
    DOCS_ENABLED: Optional[bool] = None  # default: enabled outside production only
    RATE_LIMIT_ENABLED: bool = True
    LOGIN_MAX_ATTEMPTS: int = 5
    LOGIN_LOCKOUT_MINUTES: int = 15

    # ---- Business rules ----------------------------------------------------
    DEPOSIT_REFUND_PERCENT: int = 50

    LOG_LEVEL: str = "INFO"

    # ---- Derived helpers ---------------------------------------------------
    @property
    def is_production(self) -> bool:
        return self.ENVIRONMENT.strip().lower() not in DEV_ENVIRONMENTS

    @property
    def docs_enabled(self) -> bool:
        return self.DOCS_ENABLED if self.DOCS_ENABLED is not None else not self.is_production

    @property
    def trusted_proxies(self) -> List[str]:
        return [p.strip() for p in self.TRUSTED_PROXY_IPS.split(",") if p.strip()]

    # ---- Validators --------------------------------------------------------
    @field_validator("DATABASE_URL", mode="before")
    @classmethod
    def assemble_database_url(cls, v: str) -> str:
        """Adapts cloud-provided PostgreSQL URLs to the psycopg 3 driver."""
        if isinstance(v, str):
            if v.startswith("postgres://"):
                return v.replace("postgres://", "postgresql+psycopg://", 1)
            if v.startswith("postgresql://") and "+psycopg" not in v:
                return v.replace("postgresql://", "postgresql+psycopg://", 1)
        return v

    @field_validator("CORS_ORIGINS", mode="before")
    @classmethod
    def assemble_cors_origins(cls, v: Union[str, List[str]]) -> List[str]:
        if isinstance(v, str):
            v = v.strip()
            if v.startswith("["):
                try:
                    return [str(i) for i in json.loads(v)]
                except Exception as exc:
                    raise ValueError("CORS_ORIGINS must be valid JSON or comma separated") from exc
            return [i.strip() for i in v.split(",") if i.strip()]
        return [str(i) for i in v]

    @model_validator(mode="after")
    def apply_environment_rules(self) -> "Settings":
        if not self.is_production:
            # Developer conveniences. These can never apply in production.
            if not self.SECRET_KEY:
                self.SECRET_KEY = secrets.token_urlsafe(48)
            if not self.ENCRYPTION_KEY:
                digest = hashlib.sha256(self.SECRET_KEY.encode()).digest()
                self.ENCRYPTION_KEY = base64.urlsafe_b64encode(digest).decode()
            if not self.DATABASE_URL:
                self.DATABASE_URL = _DEV_DB_URL
            if not self.CORS_ORIGINS:
                self.CORS_ORIGINS = list(_DEV_CORS)
            return self

        problems: List[str] = []
        if self.DEBUG:
            problems.append("DEBUG must be false in production")
        if len(self.SECRET_KEY) < 32:
            problems.append("SECRET_KEY must be set and at least 32 characters")
        if not self.ENCRYPTION_KEY:
            problems.append("ENCRYPTION_KEY must be set (Fernet key)")
        else:
            try:
                from cryptography.fernet import Fernet

                Fernet(self.ENCRYPTION_KEY.encode())
            except Exception:
                problems.append("ENCRYPTION_KEY is not a valid Fernet key")
        if not self.DATABASE_URL or "localhost" in self.DATABASE_URL or "127.0.0.1" in self.DATABASE_URL:
            problems.append("DATABASE_URL must point to the production database")
        if not self.CORS_ORIGINS or "*" in self.CORS_ORIGINS:
            problems.append("CORS_ORIGINS must be an explicit allow-list (no '*')")
        if self.PAYMENT_GATEWAY_PROVIDER.strip().upper() == "MOCK":
            problems.append("PAYMENT_GATEWAY_PROVIDER=MOCK is not allowed in production")
        if self.EMAIL_PROVIDER.strip().upper() != "SMTP":
            problems.append("EMAIL_PROVIDER must be SMTP in production")
        elif not (self.SMTP_USERNAME and self.SMTP_PASSWORD and self.SMTP_FROM_EMAIL):
            problems.append("SMTP_USERNAME, SMTP_PASSWORD and SMTP_FROM_EMAIL are required")
        if not (self.ADMIN_REGISTRATION_SUPER_KEY or self.ADMIN_REGISTRATION_SUPER_KEY_HASH):
            problems.append("ADMIN_REGISTRATION_SUPER_KEY or its hash must be set")
        if problems:
            raise ValueError("Refusing to start with insecure production configuration: " + "; ".join(problems))
        return self

    model_config = SettingsConfigDict(
        env_file=str(Path(__file__).resolve().parent.parent.parent / ".env"),
        env_file_encoding="utf-8",
        case_sensitive=True,
        extra="ignore",
    )


settings = Settings()
