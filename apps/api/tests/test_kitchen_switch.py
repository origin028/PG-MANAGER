"""The kitchen module is opt-in per company; the owner controls it and the kitchen staff logins."""
import io

import sqlalchemy as sa
from fastapi.testclient import TestClient

from app.models.food_menu import FoodMenu
from app.models.property import Company
from app.models.user import User
from tests.test_phase3_payment_completion import setup_test_context

JPEG = b"\xff\xd8\xff\xe0" + b"meal" * 20


def _setup(client):
    tokens, ids = setup_test_context(client.app.state.testing_session)
    owner = {"Authorization": f"Bearer {tokens['admin']}"}
    res = {"Authorization": f"Bearer {tokens['res1']}"}
    return tokens, ids, owner, res


def _login(client, ident, pw):
    return client.post("/api/v1/auth/login", json={"identifier": ident, "password": pw, "client_type": "admin_mobile"})


def test_owner_switches_kitchen_and_manages_staff(client: TestClient):
    _, ids, owner, res = _setup(client)

    s = client.get("/api/v1/kitchen/settings", headers=owner).json()["data"]
    assert s == {"enabled": False, "staff": []}

    # Off: no meal pass for residents.
    assert client.get("/api/v1/resident/meal-pass", headers=res).json()["data"]["enabled"] is False

    staff = client.post("/api/v1/kitchen/staff", headers=owner, json={"full_name": "Ramu Cook", "username": "ramu", "phone": "9811122233", "password": "cook1234"})
    assert staff.status_code == 201, staff.text
    staff_id = staff.json()["data"]["id"]
    dup = client.post("/api/v1/kitchen/staff", headers=owner, json={"full_name": "Xavier", "username": "RAMU", "phone": "9811122299", "password": "cook1234"})
    assert dup.status_code == 409

    # Off: kitchen staff cannot sign in.
    r = _login(client, "ramu", "cook1234")
    assert r.status_code == 403 and "switched off" in r.json()["error"]["message"]

    # On: they can, by username or phone; residents get passes.
    assert client.put("/api/v1/kitchen/settings", headers=owner, json={"enabled": True}).status_code == 200
    tok = _login(client, "ramu", "cook1234")
    assert tok.status_code == 200, tok.text
    assert _login(client, "9811122233", "cook1234").status_code == 200
    k = {"Authorization": f"Bearer {tok.json()['data']['access_token']}"}
    assert client.get(f"/api/v1/kitchen/today?property_id={ids['p1']}", headers=k).status_code == 200
    assert client.get("/api/v1/resident/meal-pass", headers=res).json()["data"]["enabled"] is True

    # Turning it off locks out an already signed-in kitchen session immediately.
    client.put("/api/v1/kitchen/settings", headers=owner, json={"enabled": False})
    assert client.get(f"/api/v1/kitchen/today?property_id={ids['p1']}", headers=k).status_code == 403
    assert client.post("/api/v1/kitchen/scan", headers=owner, json={"token": "x" * 40}).status_code == 403

    # Owner deactivates and resets.
    client.put("/api/v1/kitchen/settings", headers=owner, json={"enabled": True})
    assert client.patch(f"/api/v1/kitchen/staff/{staff_id}", headers=owner, json={"is_active": False}).status_code == 200
    assert _login(client, "ramu", "cook1234").status_code == 401
    client.patch(f"/api/v1/kitchen/staff/{staff_id}", headers=owner, json={"is_active": True, "password": "newpass99"})
    assert _login(client, "ramu", "cook1234").status_code == 401
    assert _login(client, "ramu", "newpass99").status_code == 200


def test_only_owner_can_change_kitchen_settings(client: TestClient):
    tokens, _, _, res = _setup(client)
    assert client.get("/api/v1/kitchen/settings", headers=res).status_code == 403
    assert client.put("/api/v1/kitchen/settings", headers={"Authorization": f"Bearer {tokens['staff']}"}, json={"enabled": True}).status_code == 403


def test_menu_photo_upload_and_visibility(client: TestClient):
    _, ids, owner, res = _setup(client)
    created = client.post("/api/v1/food-menus", headers=owner, json={"property_id": str(ids["p1"]), "day_of_week": "MONDAY", "meal_type": "LUNCH", "dishes": ["Rice"]})
    menu_id = created.json()["data"]["id"]
    up = client.post(f"/api/v1/food-menus/{menu_id}/image", headers=owner, files={"photo": ("lunch.jpg", io.BytesIO(JPEG), "image/jpeg")})
    assert up.status_code == 200, up.text
    bad = client.post(f"/api/v1/food-menus/{menu_id}/image", headers=owner, files={"photo": ("x.jpg", io.BytesIO(b"<script>"), "image/jpeg")})
    assert bad.status_code == 400

    img = client.get(f"/api/v1/food-menus/{menu_id}/image", headers=res)
    assert img.status_code == 200 and img.content == JPEG
    assert client.get("/api/v1/resident/food-menu", headers=res).json()["data"]["menu_by_day"]["MONDAY"][0]["has_image"] is True

    # A resident of another home cannot see it.
    with client.app.state.testing_session() as db:
        menu = db.get(FoodMenu, __import__("uuid").UUID(menu_id))
        menu.property_id = ids["p2"]
        db.commit()
    assert client.get(f"/api/v1/food-menus/{menu_id}/image", headers=res).status_code == 403
