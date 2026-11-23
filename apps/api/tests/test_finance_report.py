"""Finance page: month figures and month-over-month comparison with known data."""
from datetime import date, datetime, time
from decimal import Decimal
from zoneinfo import ZoneInfo

import sqlalchemy as sa
from fastapi.testclient import TestClient

from app.models.expense import Expense
from app.models.invoice import Invoice
from app.models.payment import Payment
from app.models.resident import Resident
from app.models.user import User
from app.services.finance_service import finance_report, month_summary, scope_for
from tests.test_phase3_payment_completion import setup_test_context

IST = ZoneInfo("Asia/Kolkata")
MAR, APR = date(2026, 3, 1), date(2026, 4, 1)
TODAY = date(2026, 5, 10)


def at(d: date) -> datetime:
    return datetime.combine(d, time(11, 0), IST)


def seed(factory, ids):
    with factory() as db:
        company = db.get(User, ids["res_user1"]).company_id
        res1 = db.get(Resident, ids["res1"])
        res2 = db.get(Resident, ids["res2"])
        # res1 lives in p1 since Jan; res2 (p2) joins in April; res1 moves out in May (after the window).
        res2.check_in_date = date(2026, 4, 3)
        def bill(r, ym, amt, paid, status):
            inv = Invoice(property_id=r.property_id, resident_id=r.id, invoice_number=f"T-{r.id.hex[:4]}-{ym}", billing_month=ym,
                          invoice_type="RENT", amount=Decimal(amt), paid_amount=Decimal(paid), due_date=date.fromisoformat(f"{ym}-05"), status=status)
            db.add(inv); db.flush(); return inv
        i1 = bill(res1, "2026-03", 5000, 5000, "PAID")
        i2 = bill(res1, "2026-04", 5000, 5000, "PAID")
        i3 = bill(res2, "2026-04", 6000, 0, "OVERDUE")
        for inv, d, mode in [(i1, date(2026, 3, 4), "UPI"), (i2, date(2026, 4, 2), "CASH")]:
            db.add(Payment(property_id=inv.property_id, invoice_id=inv.id, resident_id=inv.resident_id, payment_number=f"P-{inv.invoice_number}",
                           amount=inv.amount, payment_mode=mode, status="SUCCESS", paid_at=at(d)))
        db.add(Payment(property_id=i3.property_id, invoice_id=i3.id, resident_id=i3.resident_id, payment_number="P-FAILED",
                       amount=Decimal(6000), payment_mode="UPI", status="FAILED", paid_at=at(date(2026, 4, 9))))  # must not count
        db.add(Expense(company_id=company, property_id=ids["p1"], category="GROCERIES", title="Veg", amount=Decimal(1000), method="UPI", date=date(2026, 3, 10)))
        db.add(Expense(company_id=company, property_id=None, category="SALARIES", title="Cook", amount=Decimal(3000), method="CASH", date=date(2026, 4, 1)))
        db.commit()
        return company


def test_month_figures_and_comparison(client: TestClient):
    _, ids = setup_test_context(client.app.state.testing_session)
    factory = client.app.state.testing_session
    company = seed(factory, ids)
    with factory() as db:
        r = finance_report(db, scope_for(db, company, None), APR, today=TODAY)
        cur, prev, ch = r["current"], r["previous"], r["change"]

        assert (prev["collected"], prev["spent"], prev["profit"]) == (5000.0, 1000.0, 4000.0)
        assert prev["margin_percent"] == 80.0 and prev["collected_by_mode"] == {"UPI": 5000.0}
        assert (cur["collected"], cur["spent"], cur["profit"]) == (5000.0, 3000.0, 2000.0)  # failed payment excluded
        assert cur["collected_by_mode"] == {"CASH": 5000.0}

        assert cur["billed"] == 11000.0 and cur["billed_paid"] == 5000.0 and cur["collection_rate_percent"] == 45.5
        assert cur["unpaid_now"] == 6000.0  # overdue bill counts as unpaid
        assert (prev["residents"], cur["residents"]) == (1, 2)
        assert (cur["joined"], cur["left"], cur["net_growth"]) == (1, 0, 1)

        assert ch["profit"] == {"change": -2000.0, "percent": -50.0}
        assert ch["spent"] == {"change": 2000.0, "percent": 200.0}
        assert ch["residents"] == {"change": 1, "percent": 100.0}
        assert [t["month"] for t in r["trend"]] == ["2025-11", "2025-12", "2026-01", "2026-02", "2026-03", "2026-04"]
        assert r["trend"][-1]["profit"] == 2000.0


def test_move_out_counted_in_its_month_and_scoped_by_property(client: TestClient):
    tokens, ids = setup_test_context(client.app.state.testing_session)
    factory = client.app.state.testing_session
    company = seed(factory, ids)
    owner = {"Authorization": f"Bearer {tokens['admin']}"}
    # Real check-out through the API on a fixed date records the move-out month.
    co = client.post(f"/api/v1/residents/{ids['res1']}/checkout", headers=owner, json={"check_out_date": "2026-04-20", "force_checkout": True})
    assert co.status_code == 200, co.text
    with factory() as db:
        assert db.get(Resident, ids["res1"]).actual_check_out_date == date(2026, 4, 20)
        apr = month_summary(db, scope_for(db, company, None), APR, TODAY)
        assert apr["left"] == 1 and apr["residents"] == 1
        only_p1 = month_summary(db, scope_for(db, company, ids["p1"]), APR, TODAY)
        assert only_p1["joined"] == 0 and only_p1["billed"] == 5000.0


def test_finance_endpoint_permissions(client: TestClient):
    tokens, ids = setup_test_context(client.app.state.testing_session)
    ok = client.get("/api/v1/reports/finance?month=2026-04", headers={"Authorization": f"Bearer {tokens['admin']}"})
    assert ok.status_code == 200 and set(ok.json()["data"]) == {"current", "previous", "change", "trend"}
    assert client.get("/api/v1/reports/finance", headers={"Authorization": f"Bearer {tokens['res1']}"}).status_code == 403
    assert client.get("/api/v1/reports/finance?month=2026-4", headers={"Authorization": f"Bearer {tokens['admin']}"}).status_code == 422
