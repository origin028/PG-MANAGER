"""One resident's whole life through the public API: KYC signup -> approval -> rent -> deposit -> move-out.

This is the real-world scenario the owner described: online KYC instead of photocopies,
rent only (no extra charges), and a 50% deposit refund on exit regardless of stay length.
"""
import io
import uuid
from datetime import date

import sqlalchemy as sa
from fastapi.testclient import TestClient

from app.integrations.email import DevMockEmailProvider
from app.models.bed import Bed
from app.models.invoice import Invoice
from app.models.resident import Resident
from app.models.user import User
from app.services.file_service import UPLOAD_DIR
from app.tasks.invoice_jobs import generate_monthly_invoices
from tests.test_resident_registration_approval_workflow import make_auth_header, seed_workflow_context

JPEG = b"\xff\xd8\xff\xe0" + b"AADHAAR-FRONT-PIXELS" * 8
PHONE, EMAIL = "9876512345", "asha.nair@example.com"


def test_full_resident_lifecycle(client: TestClient):
    factory = client.app.state.testing_session
    ctx = seed_workflow_context(factory)
    owner = make_auth_header(ctx["admin_a_id"], "PROPERTY_MANAGER", ctx["comp_a_id"])
    other_owner = make_auth_header(ctx["admin_b_id"], "PROPERTY_MANAGER", ctx["comp_b_id"])

    # 1. Resident submits the online KYC form (no photocopies) and verifies the OTP sent to their email.
    form = {
        "full_name": "Asha Nair", "date_of_birth": "1999-03-02", "gender": "Female", "occupation": "Analyst",
        "primary_phone": PHONE, "email": EMAIL, "emergency_contact": "Mother - Latha - 9876500000",
        "house_flat_no": "12", "street": "MG Road", "landmark": "Metro", "city": "Kochi", "state": "Kerala",
        "pincode": "682001", "property_id": str(ctx["prop_a_id"]), "verification_method": "Aadhaar + PAN",
    }
    files = {
        "aadhaar_front_file": ("a_front.jpg", io.BytesIO(JPEG), "image/jpeg"),
        "aadhaar_back_file": ("a_back.jpg", io.BytesIO(JPEG), "image/jpeg"),
        "pan_card_file": ("pan.jpg", io.BytesIO(JPEG), "image/jpeg"),
        "resident_selfie_file": ("me.jpg", io.BytesIO(JPEG), "image/jpeg"),
    }
    DevMockEmailProvider.clear()
    assert client.post("/api/v1/auth/resident/register/otp/request", data=form, files=files).status_code == 200
    otp = DevMockEmailProvider.get_last_otp(EMAIL)
    done = client.post("/api/v1/auth/resident/register/otp/verify", json={"phone": PHONE, "otp": otp})
    assert done.status_code == 201, done.text
    resident_id = done.json()["data"]["resident_id"]

    # 2. Until the owner approves, the resident has no access to the app.
    pending = client.post("/api/v1/auth/resident/login/otp/request", json={"phone": PHONE})
    assert pending.status_code in (400, 403, 404), pending.text

    # 3. Owner opens the KYC document: decrypted correctly, while the file on disk is ciphertext.
    doc = client.get(f"/api/v1/residents/{resident_id}/kyc-document/aadhaar_front", headers=owner)
    assert doc.status_code == 200 and doc.content == JPEG and doc.headers["content-type"] == "image/jpeg"
    stored = [p for p in UPLOAD_DIR.glob("*.enc") if JPEG not in p.read_bytes()]
    assert stored, "KYC files must be encrypted at rest"
    #    ...and another PG company's owner cannot.
    assert client.get(f"/api/v1/residents/{resident_id}/kyc-document/aadhaar_front", headers=other_owner).status_code == 403

    # 4. Owner approves, assigning bed and monthly rent (rent only, no extra charges).
    ok = client.post(
        f"/api/v1/residents/{resident_id}/approve",
        json={"room_id": str(ctx["room_a_id"]), "bed_id": str(ctx["bed_a1_id"]), "monthly_rent": 9500.0},
        headers=owner,
    )
    assert ok.status_code == 200 and ok.json()["data"]["status"] == "ACTIVE"

    # 5. Owner records the Rs 5,000 deposit received.
    assert client.post(f"/api/v1/residents/{resident_id}/deposit", json={"amount": "5000.00"}, headers=owner).status_code == 201
    ledger = client.get(f"/api/v1/residents/{resident_id}/deposit", headers=owner).json()["data"]
    assert ledger["deposit_held"] == "5000.00" and ledger["refund_if_moving_out_today"] == "2500.00"

    # 6. Rent for the month is generated automatically, once.
    month = date.today().strftime("%Y-%m")
    with factory() as db:
        assert generate_monthly_invoices(db, month)["generated_count"] == 1
        assert generate_monthly_invoices(db, month)["generated_count"] == 0
        inv = db.scalars(sa.select(Invoice).where(Invoice.resident_id == uuid.UUID(resident_id))).one()
        assert float(inv.amount) == 9500.0
        inv.paid_amount, inv.status = inv.amount, "PAID"  # payment itself is covered by the payment suites
        db.commit()

    # 7. Moving out: 50% of the deposit comes back, the bed is freed, the login is closed.
    out = client.post(f"/api/v1/residents/{resident_id}/checkout", json={}, headers=owner)
    assert out.status_code == 200, out.text
    data = out.json()["data"]
    assert data["deposit_refund_amount"] == 2500.0 and data["bed_released"] is True
    with factory() as db:
        assert db.get(Bed, ctx["bed_a1_id"]).status == "AVAILABLE"
        res = db.get(Resident, uuid.UUID(resident_id))
        assert res.status == "CHECKED_OUT" and db.get(User, res.user_id).is_active is False
    final = client.get(f"/api/v1/residents/{resident_id}/deposit", headers=owner).json()["data"]
    assert final["deposit_held"] == "0.00"
    assert [e["type"] for e in final["entries"]] == [
        "DEPOSIT_RECEIVED", "DEPOSIT_FORFEITED", "DEPOSIT_REFUNDED",
    ]


def test_resident_sees_own_deposit_refund(client: TestClient):
    from tests.test_phase3_payment_completion import setup_test_context

    tokens, ids = setup_test_context(client.app.state.testing_session)
    r = client.get("/api/v1/resident/deposit", headers={"Authorization": f"Bearer {tokens['res1']}"})
    assert r.status_code == 200, r.text
    assert r.json()["data"] == {"deposit_held": 10000.0, "refund_percent": 50, "refund_on_exit": 5000.0}
    other = client.get("/api/v1/resident/deposit", headers={"Authorization": f"Bearer {tokens['admin']}"})
    assert other.status_code == 403
