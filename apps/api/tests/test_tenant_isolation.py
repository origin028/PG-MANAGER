"""Security regressions found in the pre-launch audit (Nov 2026).

1. An owner of one PG company could read and change another company's data.
2. A resident could hand-set any bill in their home to PAID.
3. The "demo pay" shortcut worked in production.
"""
import uuid
from datetime import date
from decimal import Decimal

import pytest
from fastapi.testclient import TestClient

from app.core.config import settings
from app.core.security import create_access_token
from app.models.expense import Expense
from app.models.property import Company, Property
from app.models.role import Role
from app.models.user import User
from tests.test_phase3_payment_completion import setup_test_context


def auth(t):
    return {"Authorization": f"Bearer {t}"}


def other_company_owner(session_factory) -> str:
    db = session_factory()
    role = db.query(Role).filter_by(name="SUPER_ADMIN").one()
    co = Company(name="Rival PG", code=f"RIVAL_{uuid.uuid4().hex[:6].upper()}")
    db.add(co)
    db.flush()
    db.add(Property(company_id=co.id, name="Rival Home", code=f"RV{uuid.uuid4().hex[:5].upper()}", address_line1="x", pincode="560010"))
    owner = User(company_id=co.id, role_id=role.id, email=f"rival_{uuid.uuid4().hex[:6]}@example.com", phone=f"91{uuid.uuid4().int % 10**8:08d}",
                 full_name="Rival Owner", password_hash="x", is_active=True, approval_status="APPROVED")
    db.add(owner)
    db.commit()
    token = create_access_token(str(owner.id), {"role": "SUPER_ADMIN"})
    db.close()
    return token


def make_invoice(client, tokens, ids) -> str:
    r = client.post("/api/v1/invoices", headers=auth(tokens["pm1"]), json={
        "property_id": str(ids["p1"]), "resident_id": str(ids["res1"]), "billing_month": "2026-11",
        "invoice_type": "RENT", "amount": 5000.0, "due_date": "2026-11-10"})
    assert r.status_code == 201, r.text
    return r.json()["data"]["id"]


def test_other_company_owner_is_locked_out(client: TestClient):
    tokens, ids = setup_test_context(client.app.state.testing_session)
    inv = make_invoice(client, tokens, ids)
    db = client.app.state.testing_session()
    company_id = db.get(Property, ids["p1"]).company_id
    db.add(Expense(company_id=company_id, property_id=ids["p1"], category="GROCERIES", title="Secret veg bill", amount=Decimal("999"), method="UPI", date=date(2026, 11, 2)))
    db.commit()
    db.close()
    rival = auth(other_company_owner(client.app.state.testing_session))

    # Direct reads and writes by id.
    for method, url in [
        ("GET", f"/api/v1/properties/{ids['p1']}"), ("PATCH", f"/api/v1/properties/{ids['p1']}"),
        ("GET", f"/api/v1/residents/{ids['res1']}"), ("PATCH", f"/api/v1/residents/{ids['res1']}"),
        ("POST", f"/api/v1/residents/{ids['res1']}/kyc/verify"),
        ("GET", f"/api/v1/invoices/{inv}"), ("PATCH", f"/api/v1/invoices/{inv}"),
        ("GET", f"/api/v1/users/{ids['res_user1']}"),
        ("GET", f"/api/v1/rooms?property_id={ids['p1']}"), ("GET", f"/api/v1/residents?property_id={ids['p1']}"),
    ]:
        r = client.request(method, url, headers=rival, json={} if method != "GET" else None)
        assert r.status_code in (403, 404), (method, url, r.status_code, r.text[:200])

    # Lists with no property chosen must only ever contain the caller's own company.
    for url in ["/api/v1/properties", "/api/v1/expenses", "/api/v1/complaints", "/api/v1/staff", "/api/v1/leads",
                "/api/v1/residents/pending-approvals", "/api/v1/reports/payments", "/api/v1/reports/financial", "/api/v1/reports/dashboard"]:
        r = client.get(url, headers=rival)
        assert r.status_code == 200, (url, r.text[:200])
        body = r.text
        assert str(ids["p1"]) not in body and "Secret veg bill" not in body and "Smart PG" not in body, url
    fin = client.get("/api/v1/reports/financial", headers=rival).json()["data"]
    assert not any(v for k, v in fin.items() if isinstance(v, (int, float)) and "expense" in k.lower())


def test_resident_cannot_edit_bills(client: TestClient):
    tokens, ids = setup_test_context(client.app.state.testing_session)
    inv = make_invoice(client, tokens, ids)
    for who in ("res1", "res2"):
        r = client.patch(f"/api/v1/invoices/{inv}", headers=auth(tokens[who]), json={"status": "PAID"})
        assert r.status_code == 403, r.text
    assert client.get(f"/api/v1/invoices/{inv}", headers=auth(tokens["pm1"])).json()["data"]["status"] == "PENDING"


def test_owner_cannot_hand_set_a_bill_to_paid(client: TestClient):
    tokens, ids = setup_test_context(client.app.state.testing_session)
    inv = make_invoice(client, tokens, ids)
    assert client.patch(f"/api/v1/invoices/{inv}", headers=auth(tokens["admin"]), json={"status": "PAID"}).status_code == 400
    assert client.patch(f"/api/v1/invoices/{inv}", headers=auth(tokens["admin"]), json={"status": "OVERDUE"}).status_code == 200


def test_demo_pay_is_disabled_in_production(client: TestClient, monkeypatch: pytest.MonkeyPatch):
    tokens, ids = setup_test_context(client.app.state.testing_session)
    inv = make_invoice(client, tokens, ids)
    monkeypatch.setattr(settings, "ENVIRONMENT", "production")
    r = client.post("/api/v1/payments/demo/pay", headers=auth(tokens["res1"]), json={"invoice_id": inv})
    assert r.status_code == 404
    monkeypatch.setattr(settings, "ENVIRONMENT", "development")
    assert client.get(f"/api/v1/invoices/{inv}", headers=auth(tokens["pm1"])).json()["data"]["status"] == "PENDING"


def test_resident_sees_only_own_complaints(client: TestClient):
    tokens, ids = setup_test_context(client.app.state.testing_session)
    client.post("/api/v1/resident/complaints", headers=auth(tokens["res2"]), json={"category": "PLUMBING", "title": "Tap leak in 2B", "description": "Leaking"})
    r = client.get("/api/v1/complaints", headers=auth(tokens["res1"]))
    assert r.status_code in (200, 403)
    if r.status_code == 200:
        assert "Tap leak in 2B" not in r.text
