import pytest
from fastapi.testclient import TestClient
from app.main import app


@pytest.fixture(scope="session")
def client():
    """Provides a TestClient for testing API endpoints."""
    with TestClient(app) as test_client:
        yield test_client
