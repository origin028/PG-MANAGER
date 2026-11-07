import pytest
import sqlalchemy as sa
from sqlalchemy.orm import Session, sessionmaker
from fastapi.testclient import TestClient

from app.core.config import settings
from app.db.session import engine, SessionLocal, get_db
from app.main import app


@pytest.fixture(scope="session", autouse=True)
def verify_postgresql_environment():
    """
    Enforces that this test suite runs strictly against PostgreSQL.
    Fails immediately if PostgreSQL is unreachable or if SQLite is configured.
    """
    if not settings.DATABASE_URL.startswith("postgresql"):
        pytest.fail(
            f"PostgreSQL integration tests require a PostgreSQL database URL. "
            f"Configured scheme is not PostgreSQL. Silently falling back to SQLite is strictly forbidden."
        )

    try:
        with engine.connect() as conn:
            db_name = conn.execute(sa.text("SELECT current_database();")).scalar()
            rev = conn.execute(sa.text("SELECT version_num FROM alembic_version;")).scalar()
            assert db_name == "pg_management_test", f"Target database must be 'pg_management_test', got '{db_name}'"
            assert rev in ["910643d8744a", "2f6bb8bc3b44", "b518259e353b", "7174ab3bff4c", "6cb475ecad6d", "7d2e4f6a8b10"], f"Alembic revision unexpected: '{rev}'"
    except Exception as exc:
        pytest.fail(f"PostgreSQL connectivity verification failed: {exc}")


@pytest.fixture
def pg_session():
    """
    Provides a transactional database session for each test that rolls back
    any test-generated mutations (such as login refresh tokens or audit logs),
    preserving the initial seeded state.
    """
    connection = engine.connect()
    transaction = connection.begin()
    nested = connection.begin_nested()
    session = SessionLocal(bind=connection)

    @sa.event.listens_for(session, "after_transaction_end")
    def restart_savepoint(s, trans):
        nonlocal nested
        if trans.nested and not trans._parent.nested:
            nested = connection.begin_nested()

    yield session

    session.close()
    transaction.rollback()
    connection.close()


@pytest.fixture
def client(pg_session):
    """
    FastAPI TestClient wired directly to the live PostgreSQL test transaction.
    """
    def override_get_db():
        try:
            yield pg_session
        finally:
            pass

    app.dependency_overrides[get_db] = override_get_db
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()
