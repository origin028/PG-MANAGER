"""Owner adds a resident -> resident gets an email code -> sets own password -> signs in by email or phone."""
from fastapi.testclient import TestClient

from app.services.email_service import EmailService
from tests.test_phase3_payment_completion import setup_test_context


def auth(t):
    return {"Authorization": f"Bearer {t}"}


class Inbox:
    def __init__(self, monkeypatch):
        self.mail = []
        monkeypatch.setattr(EmailService, "send_account_invite", lambda _s, **kw: self.mail.append(("invite", kw)) or True)
        monkeypatch.setattr(EmailService, "send_password_change_otp", lambda _s, **kw: self.mail.append(("reset", kw)) or True)

    def last_code(self, to):
        return next(kw["otp"] for kind, kw in reversed(self.mail) if kw["to_email"] == to)


def add_resident(client, tokens, ids, email="neha.k@example.com", phone="9845066601"):
    r = client.post("/api/v1/residents", headers=auth(tokens["pm1"]), json={
        "full_name": "Neha Kapoor", "phone": phone, "email": email, "property_id": str(ids["p1"]),
        "monthly_rent": 7000, "check_in_date": "2026-11-24"})
    assert r.status_code == 201, r.text
    return r.json()["data"]


def login(client, identifier, password):
    return client.post("/api/v1/auth/login", json={"identifier": identifier, "password": password, "client_type": "resident_mobile"})


def test_owner_added_resident_sets_own_password_and_signs_in(client: TestClient, monkeypatch):
    inbox = Inbox(monkeypatch)
    tokens, ids = setup_test_context(client.app.state.testing_session)
    res = add_resident(client, tokens, ids)
    assert res["invite_sent"] is True
    kind, mail = inbox.mail[-1]
    assert kind == "invite" and mail["to_email"] == "neha.k@example.com" and mail["phone"] == "9845066601"
    assert mail["set_password_url"].endswith("/set-password") and mail["valid_hours"] == 48

    code = inbox.last_code("neha.k@example.com")
    weak = client.post("/api/v1/auth/change-password/reset-with-otp", json={"email": "neha.k@example.com", "otp": code, "new_password": "password"})
    assert weak.status_code == 422  # needs a letter and a number
    ok = client.post("/api/v1/auth/change-password/reset-with-otp", json={"email": "neha.k@example.com", "otp": code, "new_password": "Neha2026home"})
    assert ok.status_code == 200, ok.text
    # The code works once only.
    again = client.post("/api/v1/auth/change-password/reset-with-otp", json={"email": "neha.k@example.com", "otp": code, "new_password": "Other2026pass"})
    assert again.status_code >= 400

    for ident in ("neha.k@example.com", "NEHA.K@example.com", "9845066601", "+91 98450 66601", "098450 66601"):
        r = login(client, ident, "Neha2026home")
        assert r.status_code == 200, (ident, r.text)
    assert login(client, "9845066601", "wrong-pass-1").status_code == 401


def test_forgot_password_does_not_reveal_who_has_an_account(client: TestClient, monkeypatch):
    inbox = Inbox(monkeypatch)
    tokens, ids = setup_test_context(client.app.state.testing_session)
    add_resident(client, tokens, ids)
    known = client.post("/api/v1/auth/change-password/request-otp", json={"email": "neha.k@example.com"})
    unknown = client.post("/api/v1/auth/change-password/request-otp", json={"email": "nobody@example.com"})
    assert known.status_code == unknown.status_code == 200
    assert set(known.json()["data"]) == set(unknown.json()["data"])
    assert all(kw["to_email"] != "nobody@example.com" for _, kw in inbox.mail)


def test_resend_invite_rules(client: TestClient, monkeypatch):
    Inbox(monkeypatch)
    tokens, ids = setup_test_context(client.app.state.testing_session)
    with_email = add_resident(client, tokens, ids)
    no_email = add_resident(client, tokens, ids, email=None, phone="9845066602")
    assert no_email["invite_sent"] is False
    assert client.post(f"/api/v1/residents/{with_email['id']}/send-invite", headers=auth(tokens["pm1"])).status_code == 200
    assert client.post(f"/api/v1/residents/{no_email['id']}/send-invite", headers=auth(tokens["pm1"])).status_code == 400
    # Residents cannot trigger invites for anyone.
    assert client.post(f"/api/v1/residents/{with_email['id']}/send-invite", headers=auth(tokens["res1"])).status_code == 403


def test_password_reset_signs_out_old_sessions(client: TestClient, monkeypatch):
    inbox = Inbox(monkeypatch)
    tokens, ids = setup_test_context(client.app.state.testing_session)
    add_resident(client, tokens, ids)
    client.post("/api/v1/auth/change-password/reset-with-otp", json={"email": "neha.k@example.com", "otp": inbox.last_code("neha.k@example.com"), "new_password": "First2026pass"})
    refresh = login(client, "neha.k@example.com", "First2026pass").json()["data"]["refresh_token"]
    client.post("/api/v1/auth/change-password/request-otp", json={"email": "neha.k@example.com"})
    client.post("/api/v1/auth/change-password/reset-with-otp", json={"email": "neha.k@example.com", "otp": inbox.last_code("neha.k@example.com"), "new_password": "Second2026pass"})
    r = client.post("/api/v1/auth/refresh", json={"refresh_token": refresh, "client_type": "resident_mobile"})
    assert r.status_code == 401
