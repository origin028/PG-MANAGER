"""Owner adds name/phone/email -> resident completes KYC -> 7-day deadline -> access auto-off -> owner switch."""
import io
import uuid
from datetime import datetime, timedelta, timezone

from fastapi.testclient import TestClient

from app.models.property import Company, Property
from app.models.resident import Resident
from app.services import portal_service
from app.services.email_service import EmailService
from tests.test_phase3_payment_completion import setup_test_context
from tests.test_resident_invite import Inbox, auth


def png():
    return io.BytesIO(b"\x89PNG\r\n\x1a\n" + b"\x00" * 200)


def quick_add(client, tokens, ids, phone="9845077701", email="arjun.n@example.com"):
    r = client.post("/api/v1/residents", headers=auth(tokens["pm1"]), json={"full_name": "Arjun Nair", "phone": phone, "email": email, "property_id": str(ids["p1"])})
    assert r.status_code == 201, r.text
    return r.json()["data"]


def resident_token(client, inbox, email="arjun.n@example.com", pw="Arjun2026room"):
    client.post("/api/v1/auth/change-password/reset-with-otp", json={"email": email, "otp": inbox.last_code(email), "new_password": pw})
    r = client.post("/api/v1/auth/login", json={"identifier": email, "password": pw, "client_type": "resident_mobile"})
    assert r.status_code == 200, r.text
    return r.json()["data"]["access_token"]


def submit_kyc(client, tok):
    data = {"date_of_birth": "2000-05-04", "gender": "Male", "occupation": "Analyst", "emergency_contact_name": "Ravi Nair",
            "emergency_contact_phone": "9845077799", "house_flat_no": "12", "street": "MG Road", "city": "Kochi", "state": "Kerala",
            "pincode": "682001", "verification_method": "Aadhaar + PAN"}
    files = {k: (f"{k}.png", png(), "image/png") for k in ("aadhaar_front_file", "aadhaar_back_file", "pan_card_file", "resident_selfie_file")}
    return client.post("/api/v1/resident/kyc", headers=auth(tok), data=data, files=files)


def push_deadline_to_past(client, rid):
    db = client.app.state.testing_session()
    db.get(Resident, uuid.UUID(rid)).kyc_due_at = datetime.now(timezone.utc) - timedelta(minutes=1)
    db.commit()
    db.close()


def test_quick_add_starts_seven_day_clock_and_resident_does_kyc(client: TestClient, monkeypatch):
    inbox = Inbox(monkeypatch)
    tokens, ids = setup_test_context(client.app.state.testing_session)
    res = quick_add(client, tokens, ids)  # only name, phone, email
    assert res["invite_sent"] is True and res["portal_enabled"] is True and res["kyc_days_left"] == 7 and res["kyc_submitted"] is False
    tok = resident_token(client, inbox)

    me = client.get("/api/v1/resident/kyc", headers=auth(tok)).json()["data"]
    assert me["full_name"] == "Arjun Nair" and me["days_left"] == 7 and me["kyc_status"] == "PENDING"
    bad = client.post("/api/v1/resident/kyc", headers=auth(tok), data={"verification_method": "Aadhaar + PAN"})
    assert bad.status_code == 400
    ok = submit_kyc(client, tok)
    assert ok.status_code == 200, ok.text
    detail = client.get(f"/api/v1/residents/{res['id']}", headers=auth(tokens["pm1"])).json()["data"]
    assert detail["kyc_status"] == "SUBMITTED" and detail["kyc_submitted"] is True
    dash = client.get(f"/api/v1/reports/dashboard?property_id={ids['p1']}", headers=auth(tokens["admin"])).json()["data"]
    assert dash["kyc_to_verify"] == 1
    # Owner verifies -> deadline gone.
    client.post(f"/api/v1/residents/{res['id']}/kyc/verify", headers=auth(tokens["pm1"]), json={})
    detail = client.get(f"/api/v1/residents/{res['id']}", headers=auth(tokens["pm1"])).json()["data"]
    assert detail["kyc_status"] == "VERIFIED" and detail["kyc_days_left"] is None and detail["kyc_due_at"] is None


def test_access_turns_off_after_deadline_and_owner_can_turn_it_on(client: TestClient, monkeypatch):
    inbox = Inbox(monkeypatch)
    tokens, ids = setup_test_context(client.app.state.testing_session)
    res = quick_add(client, tokens, ids)
    tok = resident_token(client, inbox)
    assert client.get("/api/v1/resident/dashboard", headers=auth(tok)).status_code == 200

    push_deadline_to_past(client, res["id"])
    blocked = client.get("/api/v1/resident/dashboard", headers=auth(tok))
    assert blocked.status_code == 403 and blocked.json()["error"]["code"] == "PORTAL_OFF"
    portal = client.get("/api/v1/resident/portal", headers=auth(tok)).json()["data"]
    assert portal["enabled"] is False and portal["reason"] == "KYC_OVERDUE" and portal["days_left"] == 0
    assert client.get("/api/v1/resident/property-contacts", headers=auth(tok)).status_code == 200  # can still reach the PG
    assert submit_kyc(client, tok).status_code == 200  # can still submit KYC while paused
    assert client.get(f"/api/v1/reports/dashboard?property_id={ids['p1']}", headers=auth(tokens["admin"])).json()["data"]["access_paused"] == 1

    # Owner turns it back on -> a fresh 7 days, app works again.
    on = client.post(f"/api/v1/residents/{res['id']}/access", headers=auth(tokens["pm1"]), json={"enabled": True})
    assert on.status_code == 200 and on.json()["data"]["portal_enabled"] is True and on.json()["data"]["kyc_days_left"] == 7
    assert client.get("/api/v1/resident/dashboard", headers=auth(tok)).status_code == 200

    # Owner turns it off by hand.
    off = client.post(f"/api/v1/residents/{res['id']}/access", headers=auth(tokens["pm1"]), json={"enabled": False})
    assert off.json()["data"]["portal_reason"] == "OWNER"
    assert client.get("/api/v1/resident/dashboard", headers=auth(tok)).json()["error"]["code"] == "PORTAL_OFF"
    # Residents cannot flip the switch.
    assert client.post(f"/api/v1/residents/{res['id']}/access", headers=auth(tok), json={"enabled": True}).status_code == 403


def test_verifying_kyc_reopens_access_closed_for_kyc(client: TestClient, monkeypatch):
    inbox = Inbox(monkeypatch)
    tokens, ids = setup_test_context(client.app.state.testing_session)
    res = quick_add(client, tokens, ids)
    tok = resident_token(client, inbox)
    submit_kyc(client, tok)
    push_deadline_to_past(client, res["id"])
    assert client.get("/api/v1/resident/dashboard", headers=auth(tok)).status_code == 403
    client.post(f"/api/v1/residents/{res['id']}/kyc/verify", headers=auth(tokens["pm1"]), json={})
    assert client.get("/api/v1/resident/dashboard", headers=auth(tok)).status_code == 200


def test_daily_job_reminds_then_pauses_and_spares_existing_residents(client: TestClient, monkeypatch):
    Inbox(monkeypatch)
    sent = []
    monkeypatch.setattr(EmailService, "send_notice", lambda _s, to, subject, *a, **k: sent.append((to, subject)) or True)
    tokens, ids = setup_test_context(client.app.state.testing_session)
    res = quick_add(client, tokens, ids)
    db = client.app.state.testing_session()
    r = db.get(Resident, uuid.UUID(res["id"]))
    base = r.kyc_due_at
    # 6 days in: reminder only.
    out = portal_service.run_daily(db, now=base - timedelta(days=1))
    assert out["reminders_sent"] == 1 and out["access_paused"] == 0 and "finish your KYC" in sent[-1][1]
    assert portal_service.run_daily(db, now=base - timedelta(hours=12))["reminders_sent"] == 0  # only once
    # Past the deadline: paused + email.
    out = portal_service.run_daily(db, now=base + timedelta(minutes=5))
    assert out["access_paused"] == 1 and "paused" in sent[-1][1]
    # Existing residents (no deadline) were never touched.
    assert all(x.portal_enabled for x in db.query(Resident).filter(Resident.id != r.id).all())
    db.close()


def test_owner_sets_deadline_days(client: TestClient, monkeypatch):
    Inbox(monkeypatch)
    tokens, ids = setup_test_context(client.app.state.testing_session)
    assert client.patch("/api/v1/settings/company", headers=auth(tokens["admin"]), json={"kyc_deadline_days": 3}).json()["data"]["kyc_deadline_days"] == 3
    assert client.patch("/api/v1/settings/company", headers=auth(tokens["admin"]), json={"kyc_deadline_days": 0}).status_code == 422
    assert quick_add(client, tokens, ids)["kyc_days_left"] == 3
    db = client.app.state.testing_session()
    company = db.get(Company, db.get(Property, ids["p1"]).company_id)
    assert company.kyc_deadline_days == 3
    db.close()
