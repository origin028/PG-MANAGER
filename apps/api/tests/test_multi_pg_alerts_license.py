"""Self sign-up with 'ID photos later' + owner alerts, the all-PGs overview, and the (switched-off) licence key."""
import io
import uuid
from datetime import date, timedelta

import pytest
import sqlalchemy as sa
from fastapi.testclient import TestClient

from app.core.config import settings
from app.integrations.email import DevMockEmailProvider
from app.models.notification import Notification
from app.models.property import Company, Property
from app.models.resident import Resident
from app.services import license_service
from tests.test_phase3_payment_completion import setup_test_context
from tests.test_resident_invite import auth


def signup(client, prop_id, email="riya.k@example.com", phone="9811122233", later=True):
    form = {"full_name": "Riya Kapoor", "date_of_birth": "2001-02-03", "gender": "Female", "occupation": "Student", "primary_phone": phone,
            "email": email, "emergency_contact": "Mother - 9811122299", "house_flat_no": "7", "street": "MG Road", "city": "Pune",
            "state": "Maharashtra", "pincode": "411001", "property_id": str(prop_id), "verification_method": "LATER" if later else "Passport Only"}
    jpeg = b"\xff\xd8\xff\xe0" + b"\x00" * 200
    files = None if later else {k: (f"{k}.jpg", io.BytesIO(jpeg), "image/jpeg") for k in ("passport_file", "resident_selfie_file")}
    r = client.post("/api/v1/auth/resident/register/otp/request", data=form, files=files)
    assert r.status_code == 200, r.text
    v = client.post("/api/v1/auth/resident/register/otp/verify", json={"phone": phone, "otp": DevMockEmailProvider.get_last_otp(email)})
    assert v.status_code in (200, 201), v.text
    return v.json()["data"]["resident_id"]


def test_self_signup_without_photos_alerts_the_right_people_and_starts_kyc_clock_on_approval(client: TestClient):
    tokens, ids = setup_test_context(client.app.state.testing_session)
    rid = signup(client, ids["p1"])

    # Owner and the manager of this PG get an alert that opens the approvals screen; the other PG's manager does not.
    owner = client.get("/api/v1/notifications", headers=auth(tokens["admin"])).json()["data"]
    assert owner and owner[0]["kind"] == "NEW_SIGNUP" and owner[0]["link"] == "/manage/approvals" and "Riya Kapoor" in owner[0]["body"]
    assert client.get("/api/v1/notifications", headers=auth(tokens["pm1"])).json()["data"]
    assert not client.get("/api/v1/notifications", headers=auth(tokens["pm2"])).json()["data"]
    assert client.get("/api/v1/notifications/unread-count", headers=auth(tokens["admin"])).json()["data"]

    # Approved without photos -> KYC still pending, with the usual deadline (not marked verified).
    ok = client.post(f"/api/v1/residents/{rid}/approve", headers=auth(tokens["pm1"]), json={})
    assert ok.status_code == 200, ok.text
    detail = client.get(f"/api/v1/residents/{rid}", headers=auth(tokens["pm1"])).json()["data"]
    assert detail["kyc_status"] == "PENDING" and detail["kyc_days_left"] == 7


def test_self_signup_with_photos_is_verified_on_approval(client: TestClient):
    tokens, ids = setup_test_context(client.app.state.testing_session)
    rid = signup(client, ids["p1"], later=False)
    client.post(f"/api/v1/residents/{rid}/approve", headers=auth(tokens["admin"]), json={})
    detail = client.get(f"/api/v1/residents/{rid}", headers=auth(tokens["admin"])).json()["data"]
    assert detail["kyc_status"] == "VERIFIED" and detail["kyc_days_left"] is None


def test_later_is_only_allowed_without_files(client: TestClient):
    tokens, ids = setup_test_context(client.app.state.testing_session)
    form = {"full_name": "X Y", "date_of_birth": "2001-02-03", "gender": "Male", "occupation": "Student", "primary_phone": "9811122244",
            "email": "x.y@example.com", "emergency_contact": "Dad 9811122200", "house_flat_no": "1", "street": "s", "city": "c", "state": "s",
            "pincode": "411001", "property_id": str(ids["p1"]), "verification_method": "Aadhaar + PAN"}
    r = client.post("/api/v1/auth/resident/register/otp/request", data=form)  # no files and not LATER
    assert r.status_code == 400


def test_homes_overview_lists_every_pg_with_totals_and_capacity(client: TestClient):
    tokens, ids = setup_test_context(client.app.state.testing_session)
    d = client.get("/api/v1/reports/homes", headers=auth(tokens["admin"])).json()["data"]
    names = {h["id"] for h in d["homes"]}
    assert {str(ids["p1"]), str(ids["p2"])} <= names
    assert d["totals"]["homes"] == len(d["homes"]) and d["totals"]["residents"] == sum(h["residents"] for h in d["homes"])
    assert d["capacity"]["limit"] > 0
    # A manager assigned to one PG only sees that PG.
    pm = client.get("/api/v1/reports/homes", headers=auth(tokens["pm1"])).json()["data"]
    assert [h["id"] for h in pm["homes"]] == [str(ids["p1"])]
    # Residents cannot see it.
    assert client.get("/api/v1/reports/homes", headers=auth(tokens["res1"])).status_code == 403


# ---- licence (super key): built, switched off -----------------------------------------------------------
def keypair():
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    from cryptography.hazmat.primitives.serialization import Encoding, NoEncryption, PrivateFormat, PublicFormat

    k = Ed25519PrivateKey.generate()
    return (license_service._b64(k.private_bytes(Encoding.Raw, PrivateFormat.Raw, NoEncryption())),
            license_service._b64(k.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)))


def test_license_keys_cannot_be_forged_or_edited():
    priv, pub = keypair()
    key = license_service.sign({"v": 1, "lid": "a", "beds": 250, "exp": None, "to": "PG"}, priv)
    assert license_service.parse(key, pub).max_beds == 250
    head, body, sig = key.split(".")
    forged = license_service._b64(license_service._unb64(body).replace(b"250", b"900"))
    with pytest.raises(Exception):
        license_service.parse(f"{head}.{forged}.{sig}", pub)
    _, other_pub = keypair()
    with pytest.raises(Exception):
        license_service.parse(key, other_pub)
    expired = license_service.sign({"v": 1, "lid": "b", "beds": 10, "exp": (date.today() - timedelta(days=1)).isoformat()}, priv)
    with pytest.raises(Exception):
        license_service.parse(expired, pub)


def test_license_off_by_default_then_enforced(client: TestClient, monkeypatch):
    tokens, ids = setup_test_context(client.app.state.testing_session)
    priv, pub = keypair()
    monkeypatch.setattr(settings, "LICENSE_PUBLIC_KEY", pub)
    # Off (testing phase): nothing is blocked, status says so.
    st = client.get("/api/v1/settings/license", headers=auth(tokens["admin"])).json()["data"]
    assert st["enforced"] is False and st["active"] is False
    assert client.get("/api/v1/reports/homes", headers=auth(tokens["admin"])).status_code == 200

    # Switched on: owner screens need a licence, activation still works, then the key's bed limit applies.
    monkeypatch.setattr(settings, "LICENSE_ENFORCED", True)
    blocked = client.get("/api/v1/reports/homes", headers=auth(tokens["admin"]))
    assert blocked.status_code == 402 and blocked.json()["error"]["code"] == "LICENSE_REQUIRED"
    bad = client.post("/api/v1/settings/license/activate", headers=auth(tokens["admin"]), json={"key": "OL1.not.valid-key-at-all"})
    assert bad.status_code == 400
    key = license_service.sign({"v": 1, "lid": str(uuid.uuid4()), "beds": 3, "exp": None, "to": "Test"}, priv)
    act = client.post("/api/v1/settings/license/activate", headers=auth(tokens["admin"]), json={"key": key})
    assert act.status_code == 200 and act.json()["data"]["bed_limit_in_force"] == 3
    assert client.get("/api/v1/reports/homes", headers=auth(tokens["admin"])).status_code == 200
    # Residents are never blocked by the licence.
    assert client.get("/api/v1/resident/portal", headers=auth(tokens["res1"])).status_code == 200
    db = client.app.state.testing_session()
    company = db.get(Company, db.get(Property, ids["p1"]).company_id)
    assert company.bed_limit == 3 and company.license_max_beds == 3
    db.close()


def test_kyc_submission_alerts_owner(client: TestClient, monkeypatch):
    from tests.test_kyc_portal import quick_add, resident_token, submit_kyc
    from tests.test_resident_invite import Inbox

    inbox = Inbox(monkeypatch)
    tokens, ids = setup_test_context(client.app.state.testing_session)
    res = quick_add(client, tokens, ids)
    submit_kyc(client, resident_token(client, inbox))
    db = client.app.state.testing_session()
    alerts = db.scalars(sa.select(Notification).where(Notification.kind == "KYC_SUBMITTED")).all()
    assert alerts and all(a.link == f"/manage/resident/{res['id']}" for a in alerts)
    assert db.get(Resident, uuid.UUID(res["id"])).kyc_status == "SUBMITTED"
    db.close()
