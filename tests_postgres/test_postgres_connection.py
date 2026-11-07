import pytest
import sqlalchemy as sa
from app.db.session import engine


def test_postgresql_live_connection(pg_session):
    """Verifies that queries execute against the live PostgreSQL server."""
    result = pg_session.execute(sa.text("SELECT current_database(), current_user, version();")).fetchone()
    assert result is not None
    db_name, db_user, version_str = result
    assert db_name == "pg_management_test"
    assert db_user == "postgres"
    assert "PostgreSQL" in version_str


def test_postgresql_alembic_revision(pg_session):
    """Verifies the active Alembic migration revision recorded in PostgreSQL."""
    rev = pg_session.execute(sa.text("SELECT version_num FROM alembic_version;")).scalar()
    assert rev in ["910643d8744a", "2f6bb8bc3b44", "b518259e353b", "7174ab3bff4c", "6cb475ecad6d", "7d2e4f6a8b10"]


def test_postgresql_seeded_record_counts(pg_session):
    """Verifies the exact row counts for seeded development data."""
    tables_expected = {
        "companies": 1,
        "roles": 4,
        "properties": 5,
        "users": 4,
        "user_property_access": 4,
    }
    for table_name, expected_count in tables_expected.items():
        actual = pg_session.execute(sa.text(f"SELECT count(*) FROM {table_name};")).scalar()
        assert actual == expected_count, f"Table '{table_name}' expected {expected_count} rows, found {actual}"


def test_postgresql_seeded_identifiers(pg_session):
    """Verifies non-sensitive identifiers of the seeded entities in PostgreSQL."""
    # Company
    company_code = pg_session.execute(sa.text("SELECT code FROM companies WHERE code = 'ORIGIN';")).scalar()
    assert company_code == "ORIGIN"

    # Roles
    roles = set(pg_session.execute(sa.text("SELECT name FROM roles;")).scalars().all())
    assert roles == {"SUPER_ADMIN", "PROPERTY_MANAGER", "STAFF", "RESIDENT"}

    # Properties
    prop_codes = set(pg_session.execute(sa.text("SELECT code FROM properties;")).scalars().all())
    assert prop_codes == {"OG-KOR", "OG-HSR", "OG-IND", "OG-ELC", "OG-BLR"}

    # Users
    user_emails = set(pg_session.execute(sa.text("SELECT email FROM users;")).scalars().all())
    assert user_emails == {
        "admin@originpg.com",
        "manager@originpg.com",
        "staff@originpg.com",
        "resident@originpg.com",
    }


def test_postgresql_health_endpoint(client):
    """Verifies /api/v1/health probe queries live PostgreSQL successfully."""
    response = client.get("/api/v1/health")
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True
    assert data["data"]["status"] == "online"
    assert data["data"]["database"] == "healthy"
    assert "version" in data["data"]


def test_postgresql_root_endpoint(client):
    """Verifies root endpoint."""
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert "service" in data
    assert "health" in data
