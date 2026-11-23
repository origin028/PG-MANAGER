import sqlalchemy as sa
from fastapi.testclient import TestClient

from app.core.config import settings
from app.core.rate_limit import reset_rate_limits
from app.models.lead import Lead
from tests.test_phase3_payment_completion import setup_test_context


def test_enquiry_creates_lead_and_validates(client: TestClient):
    _, ids = setup_test_context(client.app.state.testing_session)
    ok = client.post("/api/v1/public/enquiries", json={"name": "Meera Iyer", "phone": "+91 98450 12345", "property_id": str(ids["p1"])})
    assert ok.status_code == 201, ok.text
    with client.app.state.testing_session() as db:
        lead = db.scalars(sa.select(Lead)).one()
        assert (lead.phone, lead.source, lead.status) == ("9845012345", "WEBSITE", "NEW")
    bad = client.post("/api/v1/public/enquiries", json={"name": "X Y", "phone": "12345", "property_id": str(ids["p1"])})
    assert bad.status_code == 422


def test_honeypot_stores_nothing(client: TestClient):
    _, ids = setup_test_context(client.app.state.testing_session)
    r = client.post("/api/v1/public/enquiries", json={"name": "Bot", "phone": "9845012345", "property_id": str(ids["p1"]), "website": "spam.example"})
    assert r.status_code == 201
    with client.app.state.testing_session() as db:
        assert db.scalars(sa.select(Lead)).first() is None


def test_enquiries_rate_limited(client: TestClient, monkeypatch):
    _, ids = setup_test_context(client.app.state.testing_session)
    reset_rate_limits()
    monkeypatch.setattr(settings, "RATE_LIMIT_ENABLED", True)
    body = {"name": "Meera Iyer", "phone": "9845012345", "property_id": str(ids["p1"])}
    codes = [client.post("/api/v1/public/enquiries", json=body).status_code for _ in range(6)]
    reset_rate_limits()
    assert codes[:5] == [201] * 5 and codes[5] == 429
