import uuid
from datetime import date
from decimal import Decimal
import pytest

from app.core.config import settings
from app.core.security import create_access_token, get_password_hash
from app.models.invoice import Invoice
from app.models.property import Company, Property
from app.models.resident import Resident
from app.models.role import Role
from app.models.room import Room
from app.models.bed import Bed
from app.models.user import User, UserPropertyAccess


def make_token_header(user_id: uuid.UUID, role_name: str, company_id: uuid.UUID) -> dict:
    token = create_access_token(
        subject=str(user_id),
        claims={
            "role": role_name,
            "company_id": str(company_id),
            "client_type": "resident_mobile" if role_name == "RESIDENT" else "admin_web",
        },
    )
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def test_invoice_fixture(client):
    db = client.app.state.testing_session()
    try:
        company = Company(name="Smart PG Co", code=f"SMART_{uuid.uuid4().hex[:6]}")
        db.add(company)
        db.flush()

        role_admin = db.query(Role).filter(Role.name == "SUPER_ADMIN").first()
        if not role_admin:
            role_admin = Role(name="SUPER_ADMIN", display_name="Super Admin")
            db.add(role_admin)

        role_pm = db.query(Role).filter(Role.name == "PROPERTY_MANAGER").first()
        if not role_pm:
            role_pm = Role(name="PROPERTY_MANAGER", display_name="Property Manager")
            db.add(role_pm)

        role_res = db.query(Role).filter(Role.name == "RESIDENT").first()
        if not role_res:
            role_res = Role(name="RESIDENT", display_name="Resident")
            db.add(role_res)
        db.flush()

        prop = Property(
            company_id=company.id,
            name="Smart Luxury PG",
            code=f"SMP_{uuid.uuid4().hex[:4]}",
            address_line1="123 Tech Park Road",
            pincode="560100",
            is_active=True,
        )
        db.add(prop)
        db.flush()

        room = Room(
            property_id=prop.id,
            room_number="101",
            floor_number=1,
            room_type="DOUBLE_SHARING",
            base_monthly_rent=Decimal("8000.00"),
        )
        db.add(room)
        db.flush()

        bed = Bed(
            property_id=prop.id,
            room_id=room.id,
            bed_number="101-A",
            status="OCCUPIED",
        )
        db.add(bed)
        db.flush()

        admin_user = User(
            company_id=company.id,
            role_id=role_admin.id,
            email=f"admin_{uuid.uuid4().hex[:6]}@smartpg.com",
            phone=f"+9198{uuid.uuid4().int % 100000000:08d}",
            full_name="Super Admin",
            password_hash=get_password_hash("AdminPass123!"),
            is_active=True,
        )
        pm_user = User(
            company_id=company.id,
            role_id=role_pm.id,
            email=f"pm_{uuid.uuid4().hex[:6]}@smartpg.com",
            phone=f"+9197{uuid.uuid4().int % 100000000:08d}",
            full_name="Property Manager",
            password_hash=get_password_hash("ManagerPass123!"),
            is_active=True,
        )
        resident_user = User(
            company_id=company.id,
            role_id=role_res.id,
            email=f"resident_{uuid.uuid4().hex[:6]}@example.com",
            phone=f"+9199{uuid.uuid4().int % 100000000:08d}",
            full_name="Rohan Sharma",
            password_hash=get_password_hash("ResidentPass123!"),
            is_active=True,
        )
        db.add_all([admin_user, pm_user, resident_user])
        db.flush()

        db.add(UserPropertyAccess(user_id=pm_user.id, property_id=prop.id))
        db.flush()

        resident = Resident(
            property_id=prop.id,
            room_id=room.id,
            bed_id=bed.id,
            user_id=resident_user.id,
            status="ACTIVE",
            check_in_date=date(2026, 1, 1),
            monthly_rent=Decimal("8000.00"),
        )
        db.add(resident)
        db.flush()

        # Existing rent invoice
        rent_invoice = Invoice(
            property_id=prop.id,
            resident_id=resident.id,
            invoice_number=f"INV-RENT-{uuid.uuid4().hex[:4]}",
            invoice_type="RENT",
            billing_month="2026-11",
            amount=Decimal("8000.00"),
            paid_amount=Decimal("0.00"),
            status="PENDING",
            due_date=date(2026, 11, 5),
        )
        db.add(rent_invoice)
        db.commit()

        return {
            "company_id": company.id,
            "property_id": prop.id,
            "resident_id": resident.id,
            "resident_user_id": resident_user.id,
            "admin_user_id": admin_user.id,
            "pm_user_id": pm_user.id,
            "rent_invoice_id": rent_invoice.id,
        }
    finally:
        db.close()


def test_admin_can_create_1_rupee_test_invoice(client, test_invoice_fixture):
    ctx = test_invoice_fixture
    headers = make_token_header(ctx["admin_user_id"], "SUPER_ADMIN", ctx["company_id"])

    payload = {
        "property_id": str(ctx["property_id"]),
        "resident_id": str(ctx["resident_id"]),
        "amount": 1.00,
        "billing_month": "2026-11",
        "due_date": "2026-11-15",
        "invoice_type": "TEST",
        "notes": "₹1 UPI Integration Test Invoice",
    }

    resp = client.post("/api/v1/invoices", json=payload, headers=headers)
    assert resp.status_code == 201, resp.text
    data = resp.json()["data"]
    assert float(data["amount"]) == 1.00
    assert data["invoice_type"] == "TEST"
    assert data["status"] == "PENDING"
    assert data["billing_month"] == "2026-11"
    assert data["resident_id"] == str(ctx["resident_id"])


def test_multiple_test_invoices_suffix_safely(client, test_invoice_fixture):
    ctx = test_invoice_fixture
    headers = make_token_header(ctx["admin_user_id"], "SUPER_ADMIN", ctx["company_id"])

    # 1st test invoice
    payload1 = {
        "property_id": str(ctx["property_id"]),
        "resident_id": str(ctx["resident_id"]),
        "amount": 1.00,
        "billing_month": "2026-11",
        "due_date": "2026-11-15",
        "invoice_type": "TEST",
        "notes": "₹1 UPI Integration Test Invoice Iteration 1",
    }
    resp1 = client.post("/api/v1/invoices", json=payload1, headers=headers)
    assert resp1.status_code == 201, resp1.text
    assert resp1.json()["data"]["invoice_type"] == "TEST"

    # 2nd test invoice in the exact same cycle for the same resident
    payload2 = {
        "property_id": str(ctx["property_id"]),
        "resident_id": str(ctx["resident_id"]),
        "amount": 1.00,
        "billing_month": "2026-11",
        "due_date": "2026-11-16",
        "invoice_type": "TEST",
        "notes": "₹1 UPI Integration Test Invoice Iteration 2",
    }
    resp2 = client.post("/api/v1/invoices", json=payload2, headers=headers)
    assert resp2.status_code == 201, resp2.text
    # Safely suffixed to TEST_2 to protect uq_resident_invoice_cycle
    assert resp2.json()["data"]["invoice_type"] == "TEST_2"


def test_invoice_amount_must_be_greater_than_zero(client, test_invoice_fixture):
    ctx = test_invoice_fixture
    headers = make_token_header(ctx["admin_user_id"], "SUPER_ADMIN", ctx["company_id"])

    payload_zero = {
        "property_id": str(ctx["property_id"]),
        "resident_id": str(ctx["resident_id"]),
        "amount": 0.00,
        "billing_month": "2026-11",
        "due_date": "2026-11-15",
        "invoice_type": "TEST",
    }
    resp = client.post("/api/v1/invoices", json=payload_zero, headers=headers)
    assert resp.status_code in (400, 422), resp.text


def test_property_manager_can_create_test_invoice(client, test_invoice_fixture):
    ctx = test_invoice_fixture
    headers = make_token_header(ctx["pm_user_id"], "PROPERTY_MANAGER", ctx["company_id"])

    payload = {
        "property_id": str(ctx["property_id"]),
        "resident_id": str(ctx["resident_id"]),
        "amount": 1.00,
        "billing_month": "2026-11",
        "due_date": "2026-11-20",
        "invoice_type": "TEST",
        "notes": "Created by Property Manager",
    }
    resp = client.post("/api/v1/invoices", json=payload, headers=headers)
    assert resp.status_code == 201, resp.text
    assert float(resp.json()["data"]["amount"]) == 1.00


def test_resident_mobile_api_returns_test_invoice_and_can_initiate_upi(client, test_invoice_fixture, monkeypatch):
    monkeypatch.setattr(settings, "UPI_PAYEE_VPA", "masisokatali90900@okaxis")
    monkeypatch.setattr(settings, "UPI_PAYEE_NAME", "Saukatali Masi")

    ctx = test_invoice_fixture
    admin_headers = make_token_header(ctx["admin_user_id"], "SUPER_ADMIN", ctx["company_id"])
    resident_headers = make_token_header(ctx["resident_user_id"], "RESIDENT", ctx["company_id"])

    # 1. Admin creates ₹1.00 test invoice
    create_payload = {
        "property_id": str(ctx["property_id"]),
        "resident_id": str(ctx["resident_id"]),
        "amount": 1.00,
        "billing_month": "2026-11",
        "due_date": "2026-11-15",
        "invoice_type": "TEST",
        "notes": "₹1 UPI Integration Test Invoice",
    }
    create_resp = client.post("/api/v1/invoices", json=create_payload, headers=admin_headers)
    assert create_resp.status_code == 201, create_resp.text
    test_invoice_id = create_resp.json()["data"]["id"]

    # 2. Resident queries mobile invoices endpoint
    list_resp = client.get("/api/v1/resident/invoices", headers=resident_headers)
    assert list_resp.status_code == 200, list_resp.text
    invoices = list_resp.json()["data"]
    assert len(invoices) >= 2  # Rent invoice (8000) + Test invoice (1.00)

    found_test_invoice = next((inv for inv in invoices if inv["id"] == test_invoice_id), None)
    assert found_test_invoice is not None
    assert float(found_test_invoice["amount"]) == 1.00
    assert found_test_invoice["invoice_type"] == "TEST"

    # 3. Resident initiates direct UPI intent for ₹1.00 test invoice
    upi_payload = {
        "invoice_id": test_invoice_id,
        "idempotency_key": f"UPI-TEST-{uuid.uuid4().hex[:6]}",
    }
    upi_resp = client.post("/api/v1/payments/upi/initiate", json=upi_payload, headers=resident_headers)
    assert upi_resp.status_code == 201, upi_resp.text
    upi_data = upi_resp.json()["data"]

    assert float(upi_data["amount"]) == 1.00
    assert upi_data["payee_vpa"] == "masisokatali90900@okaxis"
    assert upi_data["payee_name"] == "Saukatali Masi"
    assert "am=1.00" in upi_data["upi_uri"]
    assert "masisokatali90900" in upi_data["upi_uri"]
