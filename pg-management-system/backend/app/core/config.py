import json
from pathlib import Path
from typing import List, Optional, Union
from pydantic import field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    PROJECT_NAME: str = "Origin PG Management System API"
    VERSION: str = "1.0.3"
    API_V1_STR: str = "/api/v1"
    ENVIRONMENT: str = "development"
    DEBUG: bool = True

    # Security & JWT Secrets
    SECRET_KEY: str = "change-this-in-production-to-a-secure-random-32-char-key"
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60
    REFRESH_TOKEN_EXPIRE_DAYS: int = 30

    # Common Super Key for PG Owner Administrator Registration (shared by Origin Company)
    ADMIN_REGISTRATION_SUPER_KEY: str = "ORG-240-X7K9-PQ82"
    ADMIN_REGISTRATION_SUPER_KEY_HASH: str = "4a9cf98caf4de59247a8cad40229adaf500b9ef1aaedca7cad460b002fef649f"

    # PostgreSQL Connection String (Psycopg 3 driver)
    DATABASE_URL: str = "postgresql+psycopg://postgres:postgres@localhost:5432/pg_management"

    @field_validator("DATABASE_URL", mode="before")
    @classmethod
    def assemble_database_url(cls, v: str) -> str:
        """Adapts cloud-provided PostgreSQL URLs (postgres:// or postgresql://) to psycopg 3 driver."""
        if isinstance(v, str):
            if v.startswith("postgres://"):
                return v.replace("postgres://", "postgresql+psycopg://", 1)
            elif v.startswith("postgresql://") and "+psycopg" not in v:
                return v.replace("postgresql://", "postgresql+psycopg://", 1)
        return v

    # Payment Gateway Configuration (AUTO, MOCK, or RAZORPAY)
    PAYMENT_GATEWAY_PROVIDER: str = "AUTO"
    RAZORPAY_KEY_ID: str = ""
    RAZORPAY_KEY_SECRET: str = ""
    RAZORPAY_WEBHOOK_SECRET: str = ""

    WHATSAPP_PROVIDER: str = ""
    WHATSAPP_PHONE_NUMBER_ID: str = ""
    WHATSAPP_ACCESS_TOKEN: str = ""
    WHATSAPP_PAYMENT_TEMPLATE: str = ""
    WHATSAPP_RECEIPT_TEMPLATE: str = ""

    # Public Base URL for resident payment links (e.g., https://pg.example.com or http://localhost:3000)
    PAYMENT_LINK_BASE_URL: str = "http://localhost:3000/pay"

    # Business UPI Configuration for Direct Resident Payments (No Payment Gateway)
    # Official Origin PG Merchant Details (SMART GROUP PG'S)
    UPI_PAYEE_VPA: str = "9886699258-3@ybl"
    UPI_PAYEE_NAME: str = "SMART GROUP PG'S"

    # Merchant Acquiring Configuration (PhonePe / Direct Bank UPI Intent)
    UPI_MERCHANT_VPA: Optional[str] = "9886699258-3@ybl"
    UPI_MERCHANT_NAME: Optional[str] = "SMART GROUP PG'S"
    UPI_MERCHANT_CODE: Optional[str] = None  # None: Direct in-app intent MUST NOT pass unsigned mc (prevents security/bank limits)
    UPI_BANK_NAME: str = "Bank of Baroda"
    UPI_BANK_TERMINAL_ID: Optional[str] = None
    UPI_BANK_WEBHOOK_SECRET: str = ""
    UPI_VERIFICATION_PROVIDER_URL: str = ""
    UPI_BANK_API_KEY: str = ""

    # Email & SMTP Configuration (for resident OTP delivery)
    EMAIL_PROVIDER: str = "MOCK"  # "MOCK" or "SMTP"
    SMTP_HOST: str = "localhost"
    SMTP_PORT: int = 587
    SMTP_USER: str = ""
    SMTP_USERNAME: str = ""
    SMTP_PASSWORD: str = ""
    SMTP_FROM_EMAIL: str = "noreply@smartgrouppg.com"
    SMTP_FROM_NAME: str = "SMART GROUP PG'S"
    SMTP_TLS: bool = True
    SMTP_USE_TLS: bool = True

    @model_validator(mode="after")
    def sync_smtp_aliases(self) -> "Settings":
        # Synchronize SMTP_USERNAME and SMTP_USER
        if self.SMTP_USERNAME and not self.SMTP_USER:
            self.SMTP_USER = self.SMTP_USERNAME
        elif self.SMTP_USER and not self.SMTP_USERNAME:
            self.SMTP_USERNAME = self.SMTP_USER

        # Synchronize SMTP_USE_TLS and SMTP_TLS
        if not self.SMTP_TLS and self.SMTP_USE_TLS:
            self.SMTP_USE_TLS = False
        elif not self.SMTP_USE_TLS and self.SMTP_TLS:
            self.SMTP_TLS = False
        return self

    # CORS Allowed Origins
    CORS_ORIGINS: Union[List[str], str] = ["*"]

    @field_validator("CORS_ORIGINS", mode="before")
    @classmethod
    def assemble_cors_origins(cls, v: Union[str, List[str]]) -> List[str]:
        if isinstance(v, str) and not v.startswith("["):
            return [i.strip() for i in v.split(",") if i.strip()]
        elif isinstance(v, str) and v.startswith("["):
            try:
                return json.loads(v)
            except Exception:
                return [v]
        elif isinstance(v, list):
            return [str(i) for i in v]
        elif isinstance(v, str):
            return [v]
        raise ValueError(v)

    @model_validator(mode="after")
    def enforce_test_database_safety(self):
        """Prevents accidental connections to production database in dev/test environment."""
        if self.ENVIRONMENT in ("development", "test", "testing"):
            if "pg_management" in self.DATABASE_URL and "pg_management_test" not in self.DATABASE_URL:
                self.DATABASE_URL = self.DATABASE_URL.replace("/pg_management", "/pg_management_test")
        return self

    # Logging
    LOG_LEVEL: str = "INFO"

    model_config = SettingsConfigDict(
        env_file=str(Path(__file__).resolve().parent.parent.parent / ".env"),
        env_file_encoding="utf-8",
        case_sensitive=True,
        extra="ignore",
    )


settings = Settings()
