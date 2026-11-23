import os

# Must run before the app (and its settings) are imported.
os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("DEBUG", "false")
os.environ.setdefault("DATABASE_URL", "postgresql+psycopg://postgres:postgres@localhost:5432/pg_management_test")
os.environ.setdefault("RATE_LIMIT_ENABLED", "false")
# Test-only owner registration key (the app ships with NO default key).
os.environ.setdefault("ADMIN_REGISTRATION_SUPER_KEY", "ORG-240-X7K9-PQ82")

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.db.base import Base
from app.dependencies import get_db
from app.main import app


@pytest.fixture(autouse=True)
def default_mock_email_provider(monkeypatch):
    """Ensures test suite defaults to MOCK email provider unless overridden."""
    from app.core.config import settings
    monkeypatch.setattr(settings, "EMAIL_PROVIDER", "MOCK")
    # Dummy credentials so SMTP tests (which mock smtplib) never depend on a local .env.
    monkeypatch.setattr(settings, "SMTP_PASSWORD", "test-smtp-password")
    monkeypatch.setattr(settings, "SMTP_USERNAME", "test@example.com")
    monkeypatch.setattr(settings, "SMTP_FROM_EMAIL", "noreply@example.com")


@pytest.fixture
def client():
    """Provides an isolated in-memory database for every API test.

    This deliberately overrides the production PostgreSQL dependency.  Tests
    must never depend on, or write to, the configured application database.
    """
    engine = create_engine(
        "sqlite+pysqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    testing_session = sessionmaker(bind=engine, autocommit=False, autoflush=False)
    Base.metadata.create_all(bind=engine)

    def override_get_db():
        db = testing_session()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = override_get_db
    app.state.testing_session = testing_session
    try:
        with TestClient(app) as test_client:
            yield test_client
    finally:
        app.dependency_overrides.clear()
        del app.state.testing_session
        Base.metadata.drop_all(bind=engine)
        engine.dispose()
