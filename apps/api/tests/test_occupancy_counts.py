"""Occupancy figures count only beds that exist today: removed beds and archived rooms are excluded."""
from fastapi.testclient import TestClient

from tests.test_phase3_payment_completion import setup_test_context


def test_removed_beds_do_not_inflate_counts(client: TestClient):
    tokens, ids = setup_test_context(client.app.state.testing_session)
    owner = {"Authorization": f"Bearer {tokens['admin']}"}
    before = client.get(f"/api/v1/reports/occupancy?property_id={ids['p1']}", headers=owner).json()["data"]["total_beds"]
    assert client.delete(f"/api/v1/beds/{ids['bed2']}", headers=owner).status_code == 200
    after = client.get(f"/api/v1/reports/occupancy?property_id={ids['p1']}", headers=owner).json()["data"]
    assert after["total_beds"] == before - 1
    dash = client.get("/api/v1/reports/dashboard", headers=owner).json()["data"]
    assert dash["total_beds"] == after["total_beds"] + client.get(f"/api/v1/reports/occupancy?property_id={ids['p2']}", headers=owner).json()["data"]["total_beds"]
