"""Meal passes: one meal per resident per sitting; screenshots, outsiders and other homes are refused."""
import uuid
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import sqlalchemy as sa
from fastapi.testclient import TestClient

from app.core.security import create_access_token, get_password_hash
from app.models.resident import Resident
from app.models.role import Role
from app.models.user import User
from app.services.meal_service import issue_pass, scan
from tests.test_phase3_payment_completion import setup_test_context

IST = ZoneInfo("Asia/Kolkata")
BREAKFAST = datetime(2026, 3, 2, 8, 15, tzinfo=IST)   # default window 07:00-10:00 (+30 min grace)
LUNCH = datetime(2026, 3, 2, 13, 0, tzinfo=IST)
AFTERNOON = datetime(2026, 3, 2, 16, 30, tzinfo=IST)  # between meals


def _ctx(client):
    tokens, ids = setup_test_context(client.app.state.testing_session)
    return tokens, ids, client.app.state.testing_session


def test_pass_serves_once(client: TestClient):
    _, ids, factory = _ctx(client)
    with factory() as db:
        r = db.get(Resident, ids["res1"])
        token, ttl = issue_pass(r, "BREAKFAST", BREAKFAST.date(), BREAKFAST)
        assert ttl == 90
        first = scan(db, token, None, ids["res_user1"], BREAKFAST + timedelta(seconds=5))
        assert first.status == "SERVED" and first.meal == "BREAKFAST"
        again, _ = issue_pass(r, "BREAKFAST", BREAKFAST.date(), BREAKFAST + timedelta(minutes=1))
        assert scan(db, again, None, ids["res_user1"], BREAKFAST + timedelta(minutes=1)).status == "ALREADY_SERVED"
        # Lunch is a separate sitting.
        lunch, _ = issue_pass(r, "LUNCH", LUNCH.date(), LUNCH)
        assert scan(db, lunch, None, ids["res_user1"], LUNCH).status == "SERVED"


def test_screenshot_expires(client: TestClient):
    _, ids, factory = _ctx(client)
    with factory() as db:
        token, _ = issue_pass(db.get(Resident, ids["res1"]), "BREAKFAST", BREAKFAST.date(), BREAKFAST)
        assert scan(db, token, None, ids["res_user1"], BREAKFAST + timedelta(seconds=120)).status == "EXPIRED"


def test_wrong_meal_wrong_home_and_between_meals(client: TestClient):
    _, ids, factory = _ctx(client)
    with factory() as db:
        r = db.get(Resident, ids["res1"])
        bf_at_lunch, _ = issue_pass(r, "BREAKFAST", LUNCH.date(), LUNCH)
        assert scan(db, bf_at_lunch, None, ids["res_user1"], LUNCH).status == "WRONG_MEAL"
        t, _ = issue_pass(r, "BREAKFAST", BREAKFAST.date(), BREAKFAST)
        assert scan(db, t, {ids["p2"]}, ids["res_user1"], BREAKFAST).status == "WRONG_HOME"
        t2, _ = issue_pass(r, "LUNCH", AFTERNOON.date(), AFTERNOON)
        assert scan(db, t2, None, ids["res_user1"], AFTERNOON).status == "NOT_SERVING_NOW"


def test_checked_out_resident_refused_and_forged_token_rejected(client: TestClient):
    _, ids, factory = _ctx(client)
    with factory() as db:
        r = db.get(Resident, ids["res1"])
        r.status = "CHECKED_OUT"
        db.commit()
        t, _ = issue_pass(r, "BREAKFAST", BREAKFAST.date(), BREAKFAST)
        assert scan(db, t, None, ids["res_user1"], BREAKFAST).status == "NOT_ACTIVE"
        assert scan(db, "eyJhbGciOiJIUzI1NiJ9.e30.forged-signature-value", None, ids["res_user1"], BREAKFAST).status == "INVALID"


def _kitchen_token(factory, company_id):
    with factory() as db:
        role = db.scalar(sa.select(Role).where(Role.name == "KITCHEN"))
        if not role:
            role = Role(name="KITCHEN", display_name="Kitchen Staff")
            db.add(role)
            db.flush()
        u = User(company_id=company_id, role_id=role.id, email=f"k{uuid.uuid4().hex[:6]}@x.com", phone="9811100000",
                 full_name="Cook", password_hash=get_password_hash("kitchen1"), is_active=True, approval_status="APPROVED")
        db.add(u)
        db.commit()
        return create_access_token(str(u.id), {"role": "KITCHEN"})


def test_kitchen_role_can_scan_and_edit_menu_but_nothing_else(client: TestClient):
    tokens, ids, factory = _ctx(client)
    with factory() as db:
        company_id = db.get(User, ids["res_user1"]).company_id
    k = {"Authorization": f"Bearer {_kitchen_token(factory, company_id)}"}

    r = client.post("/api/v1/kitchen/scan", json={"token": "not-a-real-meal-pass-token-value"}, headers=k)
    assert r.status_code == 200 and r.json()["data"]["status"] == "INVALID"
    assert client.get(f"/api/v1/kitchen/today?property_id={ids['p1']}", headers=k).status_code == 200

    menu = client.post("/api/v1/food-menus", headers=k, json={
        "property_id": str(ids["p1"]), "day_of_week": "MONDAY", "meal_type": "LUNCH", "dishes": ["Rice", "Dal"], "start_time": "12:30 PM", "end_time": "02:30 PM"})
    assert menu.status_code == 201, menu.text

    for path in ("/reports/dashboard", "/residents/pending-approvals", f"/payments?property_id={ids['p1']}", "/expenses"):
        assert client.get(f"/api/v1{path}", headers=k).status_code == 403, path
    # Residents cannot scan.
    assert client.post("/api/v1/kitchen/scan", json={"token": "x" * 30}, headers={"Authorization": f"Bearer {tokens['res1']}"}).status_code == 403


def test_resident_gets_meal_pass_endpoint(client: TestClient):
    tokens, _, _ = _ctx(client)
    r = client.get("/api/v1/resident/meal-pass", headers={"Authorization": f"Bearer {tokens['res1']}"})
    assert r.status_code == 200
    d = r.json()["data"]
    assert ("token" in d and d["expires_in"] == 90) or d["meal"] is None


def test_resident_cannot_list_other_peoples_data(client: TestClient):
    tokens, ids, _ = _ctx(client)
    res = {"Authorization": f"Bearer {tokens['res1']}"}
    for path in (f"/payments?property_id={ids['p1']}", "/residents", "/rooms", f"/beds?property_id={ids['p1']}"):
        assert client.get(f"/api/v1{path}", headers=res).status_code == 403, path
    # Owner still can.
    owner = {"Authorization": f"Bearer {tokens['admin']}"}
    for path in (f"/payments?property_id={ids['p1']}", "/residents", "/rooms", f"/beds?property_id={ids['p1']}"):
        assert client.get(f"/api/v1{path}", headers=owner).status_code == 200, path


def test_demo_open_mode_serves_any_hour_but_is_off_by_default(client: TestClient, monkeypatch):
    from app.core.config import settings

    _, ids, factory = _ctx(client)
    with factory() as db:
        r = db.get(Resident, ids["res1"])
        t, _ = issue_pass(r, "DINNER", AFTERNOON.date(), AFTERNOON)
        assert scan(db, t, None, ids["res_user1"], AFTERNOON).status == "NOT_SERVING_NOW"
        monkeypatch.setattr(settings, "MEAL_DEMO_OPEN", True)
        assert scan(db, t, None, ids["res_user1"], AFTERNOON).status == "SERVED"
