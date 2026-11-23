import pytest
from fastapi.testclient import TestClient

from app.core.config import settings
from tests.test_phase3_payment_completion import setup_test_context

KEY = {"X-Device-Key": "device-secret"}


@pytest.fixture
def ctx(client: TestClient, monkeypatch):
    monkeypatch.setattr(settings, "ATTENDANCE_DEVICE_KEY", "device-secret")
    tokens, ids = setup_test_context(client.app.state.testing_session)
    auth = {"Authorization": f"Bearer {tokens['admin']}"}
    r = client.put(f"/api/v1/attendance/residents/{ids['res1']}/biometric-id", json={"biometric_id": "17"}, headers=auth)
    assert r.status_code == 200, r.text
    return client, tokens, ids, auth


def body(ids, *punches):
    return {"property_id": str(ids["p1"]), "punches": [{"device_user_id": u, "punched_at": t} for u, t in punches]}


def test_device_key_required(ctx):
    client, _, ids, _ = ctx
    p = body(ids, ("17", "2026-03-01T08:00:00Z"))
    assert client.post("/api/v1/attendance/punches", json=p).status_code == 401
    assert client.post("/api/v1/attendance/punches", json=p, headers={"X-Device-Key": "nope"}).status_code == 401


def test_punches_alternate_in_out_and_dedupe(ctx):
    client, _, ids, auth = ctx
    p = body(ids, ("17", "2026-03-01T08:00:00Z"), ("17", "2026-03-01T13:00:00Z"), ("17", "2026-03-01T19:00:00Z"))
    r = client.post("/api/v1/attendance/punches", json=p, headers=KEY)
    assert r.json()["data"] == {"accepted": 3, "duplicates": 0, "unmatched": 0}
    again = client.post("/api/v1/attendance/punches", json=p, headers=KEY)
    assert again.json()["data"]["duplicates"] == 3 and again.json()["data"]["accepted"] == 0

    day = client.get(f"/api/v1/attendance?property_id={ids['p1']}&day=2026-03-01", headers=auth).json()["data"]
    assert [x["direction"] for x in day["punches"]] == ["IN", "OUT", "IN"]
    assert day["currently_in"] == 1 and day["punches"][0]["resident_name"] == "Test User 5"


def test_unmatched_fingerprint_is_recorded_not_dropped(ctx):
    client, _, ids, _ = ctx
    r = client.post("/api/v1/attendance/punches", json=body(ids, ("999", "2026-03-01T08:00:00Z")), headers=KEY)
    assert r.json()["data"]["unmatched"] == 1


def test_other_property_manager_cannot_view(ctx):
    client, tokens, ids, _ = ctx
    pm2 = {"Authorization": f"Bearer {tokens['pm2']}"}
    assert client.get(f"/api/v1/attendance?property_id={ids['p1']}", headers=pm2).status_code == 403
    res = {"Authorization": f"Bearer {tokens['res1']}"}
    assert client.get(f"/api/v1/attendance?property_id={ids['p1']}", headers=res).status_code == 403


def test_duplicate_biometric_id_rejected(ctx):
    client, _, ids, auth = ctx
    r = client.put(f"/api/v1/attendance/residents/{ids['res1']}/biometric-id", json={"biometric_id": "17"}, headers=auth)
    assert r.status_code == 200  # re-assigning to the same resident is fine
