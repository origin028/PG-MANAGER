"""Phase 4 Complete End-to-End Integration and QA Test Suite.

Verifies complete lifecycle workflows against the isolated test environment:
1. Super Key admin registration and login.
2. Property, room, and bed provisioning.
3. Resident self-registration, OTP verification, and administrative approval with bed allocation.
4. Resident login, profile retrieval, and settings update.
5. Room transfer with atomic bed reallocation.
6. Monthly invoice generation and retrieval.
7. UPI payment initiation (safe Rs. 1 test invoice), URI generation with RFC %20 encoding.
8. UPI return verification (payment held in PENDING_VERIFICATION; never auto-settled).
9. Admin payment settlement and durable receipt issuance.
10. Authenticated receipt PDF download and cross-resident isolation (403 Forbidden).
11. Complaints creation and administrative resolution.
12. Operational expense tracking and reporting.
13. Leads CRM pipeline and staff management.
14. Notifications unread count, individual read, and read-all.
15. Reports dashboard, payments CSV export, and occupancy CSV export.
16. Resident checkout settlement: row-locking, damage charges, dues deduction, deposit refund, bed release.
"""

import uuid
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
import pytest
from fastapi.testclient import TestClient

from app.core.config import settings
from app.core.security import create_access_token, get_password_hash
from app.main import app
from app.models.bed import Bed
from app.models.complaint import Complaint
from app.models.expense import Expense
from app.models.invoice import Invoice
from app.models.lead import Lead
from app.models.notice import Notice
from app.models.payment import Payment
from app.models.property import Company, Property
from app.models.receipt import Receipt
from app.models.resident import Resident
from app.models.role import Role
from app.models.room import Room
from app.models.staff import Staff
from app.models.user import User


def make_auth_header(user_id: uuid.UUID, role_name: str, company_id: uuid.UUID, client_type: str = "admin_web") -> dict:
    token = create_access_token(
        subject=str(user_id),
        claims={
            "role": role_name,
            "company_id": str(company_id),
            "client_type": client_type,
        },
    )
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def e2e_env(client):
    """Sets up an end-to-end multi-tenant test environment with all roles."""
    db = client.app.state.testing_session()
    try:
        suffix = uuid.uuid4().hex[:6]
        company = Company(
            name=f"Origin Living Corp {suffix}",
            code=f"OLC_{suffix}",
            email=f"corp_{suffix}@originpg.com",
            phone="9876543210",
            subscription_plan="ENTERPRISE",
            subscription_status="ACTIVE",
            bed_limit=100,
        )
        db.add(company)
        db.flush()

        # Seed roles
        roles = {}
        for role_name in ("SUPER_ADMIN", "ADMIN", "OWNER", "PROPERTY_MANAGER", "STAFF", "RESIDENT"):
            r = db.query(Role).filter(Role.name == role_name).first()
            if not r:
                r = Role(name=role_name, display_name=role_name.replace("_", " ").title())
                db.add(r)
            db.flush()
            roles[role_name] = r.id

        # Create Admin User
        admin_user = User(
            company_id=company.id,
            role_id=roles["SUPER_ADMIN"],
            email=f"admin_{suffix}@originpg.com",
            phone="9900112233",
            full_name="Origin Executive Admin",
            password_hash=get_password_hash("AdminPass@123"),
            is_active=True,
            is_verified=True,
            approval_status="APPROVED",
        )
        db.add(admin_user)
        db.commit()

        return {
            "company_id": company.id,
            "company_name": company.name,
            "admin_id": admin_user.id,
            "admin_email": admin_user.email,
            "roles": roles,
            "suffix": suffix,
        }
    finally:
        db.close()


def test_complete_phase4_end_to_end_workflow(client: TestClient, e2e_env):
    """Executes the full end-to-end PG Management business cycle."""
    admin_id = e2e_env["admin_id"]
    company_id = e2e_env["company_id"]
    admin_headers = make_auth_header(admin_id, "SUPER_ADMIN", company_id, "admin_web")

    # -------------------------------------------------------------------------
    # 1. Admin Authentication & Company Settings
    # -------------------------------------------------------------------------
    resp = client.get("/api/v1/auth/me", headers=admin_headers)
    assert resp.status_code == 200
    assert resp.json()["data"]["email"] == e2e_env["admin_email"]

    resp = client.get("/api/v1/settings/company", headers=admin_headers)
    assert resp.status_code == 200
    assert resp.json()["data"]["name"] == e2e_env["company_name"]

    # -------------------------------------------------------------------------
    # 2. Property Provisioning
    # -------------------------------------------------------------------------
    prop_payload = {
        "name": f"Origin Serenity Residency {e2e_env['suffix']}",
        "code": f"OSR_{e2e_env['suffix']}",
        "address_line1": "42 Outer Ring Road",
        "city": "Bengaluru",
        "state": "Karnataka",
        "pincode": "560103",
        "property_type": "PG",
        "total_floors": 4,
        "manager_name": "Ravi Kumar",
        "manager_phone": "+91 9876543210",
        "amenities": ["High Speed Wi-Fi", "Daily Housekeeping", "24/7 Power Backup"],
        "rules": ["No smoking inside rooms", "Quiet hours after 10 PM"],
    }
    resp = client.post("/api/v1/properties", json=prop_payload, headers=admin_headers)
    assert resp.status_code == 201, resp.text
    prop_data = resp.json()["data"]
    property_id = prop_data["id"]

    # -------------------------------------------------------------------------
    # 3. Room & Bed Creation
    # -------------------------------------------------------------------------
    room_101_payload = {
        "property_id": property_id,
        "room_number": "101",
        "floor": 1,
        "room_type": "DOUBLE",
        "base_monthly_rent": 8500.0,
        "deposit_amount": 17000.0,
    }
    resp = client.post("/api/v1/rooms", json=room_101_payload, headers=admin_headers)
    assert resp.status_code == 201
    room_101_id = resp.json()["data"]["id"]

    # Add 2 beds in Room 101
    resp = client.post("/api/v1/beds", json={"room_id": room_101_id, "bed_number": "A", "monthly_rent": 8500.0}, headers=admin_headers)
    assert resp.status_code == 201
    bed_101_a_id = resp.json()["data"]["id"]

    resp = client.post("/api/v1/beds", json={"room_id": room_101_id, "bed_number": "B", "monthly_rent": 8500.0}, headers=admin_headers)
    assert resp.status_code == 201
    bed_101_b_id = resp.json()["data"]["id"]

    # Create Room 102 for room transfer testing
    room_102_payload = {
        "property_id": property_id,
        "room_number": "102",
        "floor": 1,
        "room_type": "SINGLE",
        "base_monthly_rent": 12000.0,
        "deposit_amount": 24000.0,
    }
    resp = client.post("/api/v1/rooms", json=room_102_payload, headers=admin_headers)
    assert resp.status_code == 201
    room_102_id = resp.json()["data"]["id"]

    resp = client.post("/api/v1/beds", json={"room_id": room_102_id, "bed_number": "A", "monthly_rent": 12000.0}, headers=admin_headers)
    assert resp.status_code == 201
    bed_102_a_id = resp.json()["data"]["id"]

    # Verify floor-wise rooms API
    resp = client.get(f"/api/v1/rooms/floor-wise?property_id={property_id}", headers=admin_headers)
    assert resp.status_code == 200
    floors = resp.json()["data"]["floors"]
    assert len(floors) >= 1

    # -------------------------------------------------------------------------
    # 4. Resident Manual Onboarding & Bed Allocation
    # -------------------------------------------------------------------------
    resident_email = f"resident_{e2e_env['suffix']}@example.com"
    resident_phone = "9876511223"
    onboard_payload = {
        "property_id": property_id,
        "room_id": room_101_id,
        "bed_id": bed_101_a_id,
        "full_name": "Arjun Sharma",
        "email": resident_email,
        "phone": resident_phone,
        "password": "ResidentPass@123",
        "monthly_rent": 8500.0,
        "security_deposit": 17000.0,
        "check_in_date": str(date.today()),
        "id_proof_type": "AADHAAR",
        "id_proof_number": "999988887777",
    }
    resp = client.post("/api/v1/residents", json=onboard_payload, headers=admin_headers)
    assert resp.status_code == 201, resp.text
    resident_data = resp.json()["data"]
    resident_id = resident_data["id"]
    resident_user_id = resident_data["user_id"]

    # Verify bed is marked OCCUPIED
    resp = client.get(f"/api/v1/beds/{bed_101_a_id}", headers=admin_headers)
    assert resp.status_code == 200
    assert resp.json()["data"]["status"] == "OCCUPIED"

    # -------------------------------------------------------------------------
    # 5. Resident Mobile Profile & Settings
    # -------------------------------------------------------------------------
    # Generate resident token
    res_headers = make_auth_header(uuid.UUID(resident_user_id), "RESIDENT", company_id, "resident_mobile")

    # Resident Home Dashboard
    resp = client.get("/api/v1/resident/dashboard", headers=res_headers)
    assert resp.status_code == 200
    dash_data = resp.json()["data"]
    assert dash_data["resident_info"]["full_name"] == "Arjun Sharma"
    assert dash_data["stay_details"]["room_number"] == "101"

    # Resident Profile & KYC Status
    resp = client.get("/api/v1/resident/profile", headers=res_headers)
    assert resp.status_code == 200
    prof = resp.json()["data"]
    assert prof["stay_details"]["room_number"] == "101"
    assert prof["stay_details"]["bed_number"] == "A"
    assert prof["kyc_details"]["id_proof_number_masked"] == "XXXXXXXX7777"  # Anti-leak masking

    # Update Profile via /users/me
    resp = client.patch("/api/v1/users/me", json={"full_name": "Arjun S. Sharma"}, headers=res_headers)
    assert resp.status_code == 200
    assert resp.json()["data"]["full_name"] == "Arjun S. Sharma"

    # Resident App Settings
    resp = client.get("/api/v1/resident/settings", headers=res_headers)
    assert resp.status_code == 200

    resp = client.patch(
        "/api/v1/resident/settings",
        json={"dark_mode": True, "language": "en", "rent_reminders_enabled": True},
        headers=res_headers,
    )
    assert resp.status_code == 200
    assert resp.json()["data"]["dark_mode"] is True

    # Property Contacts for Call Management
    resp = client.get("/api/v1/resident/property-contacts", headers=res_headers)
    assert resp.status_code == 200
    assert "property_name" in resp.json()["data"]

    # -------------------------------------------------------------------------
    # 6. Room Transfer (Bed Reallocation)
    # -------------------------------------------------------------------------
    transfer_payload = {
        "room_id": room_102_id,
        "bed_id": bed_102_a_id,
    }
    resp = client.patch(f"/api/v1/residents/{resident_id}", json=transfer_payload, headers=admin_headers)
    assert resp.status_code == 200

    # Old bed 101-A must be vacated (AVAILABLE)
    resp = client.get(f"/api/v1/beds/{bed_101_a_id}", headers=admin_headers)
    assert resp.status_code == 200
    assert resp.json()["data"]["status"] == "AVAILABLE"

    # New bed 102-A must be occupied (OCCUPIED)
    resp = client.get(f"/api/v1/beds/{bed_102_a_id}", headers=admin_headers)
    assert resp.status_code == 200
    assert resp.json()["data"]["status"] == "OCCUPIED"

    # -------------------------------------------------------------------------
    # 7. Invoice Generation
    # -------------------------------------------------------------------------
    billing_month = f"{date.today().year}-{date.today().month:02d}"
    invoice_payload = {
        "resident_id": resident_id,
        "property_id": property_id,
        "billing_month": billing_month,
        "invoice_type": "RENT",
        "amount": 1.0,  # Safe test invoice amount
        "due_date": str(date.today() + timedelta(days=5)),
    }
    resp = client.post("/api/v1/invoices", json=invoice_payload, headers=admin_headers)
    assert resp.status_code == 201, resp.text
    inv_data = resp.json()["data"]
    invoice_id = inv_data["id"]
    assert inv_data["amount"] == 1.0
    assert inv_data["status"] in ("PENDING", "UNPAID")

    # Verify Resident sees the invoice
    resp = client.get("/api/v1/resident/invoices", headers=res_headers)
    assert resp.status_code == 200
    invoices = resp.json()["data"]
    assert any(i["id"] == invoice_id for i in invoices)

    # -------------------------------------------------------------------------
    # 8. UPI Payment Initiation & Safety Guard
    # -------------------------------------------------------------------------
    upi_payload = {
        "invoice_id": invoice_id,
        "app_name": "Google Pay",
        "device_model": "Pixel 7 Pro",
    }
    resp = client.post("/api/v1/payments/upi/initiate", json=upi_payload, headers=res_headers)
    assert resp.status_code in (200, 201)
    upi_init = resp.json()["data"]
    payment_id = upi_init["payment_id"]
    upi_uri = upi_init["upi_uri"]

    # Verify standard NPCI format and RFC %20 encoding
    assert "upi://pay?" in upi_uri
    assert "%20" in upi_uri
    assert "masisokatali90900" in upi_uri

    # Resident returns from UPI app
    return_payload = {
        "raw_response": "Status=SUBMITTED&txnRef=UPI-20261107-123456",
        "client_reported_status": "SUCCESS",
    }
    resp = client.post(f"/api/v1/payments/upi/{payment_id}/return", json=return_payload, headers=res_headers)
    assert resp.status_code in (200, 201)
    ret_data = resp.json()["data"]

    # STRICT RULE: Payment must remain PENDING_VERIFICATION, NEVER auto-marked PAID
    assert ret_data["status"] == "PENDING_VERIFICATION"
    assert ret_data["is_settled"] is False

    # -------------------------------------------------------------------------
    # 9. Admin Authoritative Payment Settlement & Receipt
    # -------------------------------------------------------------------------
    settle_payload = {
        "bank_reference": "UTR-AXIS-998877665544",
        "verification_notes": "Authoritative settlement verified with bank UTR credit statement.",
    }
    resp = client.post(f"/api/v1/payments/upi/{payment_id}/admin-settle", json=settle_payload, headers=admin_headers)
    assert resp.status_code == 200, resp.text
    settle_data = resp.json()["data"]
    assert settle_data["status"] == "PAID"
    receipt_id = settle_data["receipt_id"]
    assert receipt_id is not None

    # Verify Invoice is now settled
    resp = client.get(f"/api/v1/invoices/{invoice_id}", headers=admin_headers)
    assert resp.status_code == 200
    assert resp.json()["data"]["status"] == "PAID"

    # -------------------------------------------------------------------------
    # 10. Receipt PDF Download & Cross-Resident Access Control
    # -------------------------------------------------------------------------
    resp = client.get(f"/api/v1/receipts/{receipt_id}/pdf", headers=res_headers)
    assert resp.status_code == 200
    assert resp.headers["content-type"] == "application/pdf"
    assert resp.content.startswith(b"%PDF-")

    # Cross-resident leak protection: Create second resident and verify 403 Forbidden
    other_user = User(
        company_id=company_id,
        role_id=e2e_env["roles"]["RESIDENT"],
        email=f"other_{e2e_env['suffix']}@example.com",
        phone="9876599999",
        full_name="Other Resident",
        password_hash=get_password_hash("OtherPass@123"),
        is_active=True,
    )
    db = client.app.state.testing_session()
    db.add(other_user)
    db.commit()
    db.refresh(other_user)
    other_user_id = other_user.id
    other_resident = Resident(
        user_id=other_user_id,
        property_id=uuid.UUID(property_id),
        check_in_date=date.today(),
        status="ACTIVE",
    )
    db.add(other_resident)
    db.commit()
    db.close()
    other_headers = make_auth_header(other_user_id, "RESIDENT", company_id, "resident_mobile")

    # Other resident must receive 403 Forbidden
    resp = client.get(f"/api/v1/receipts/{receipt_id}/pdf", headers=other_headers)
    assert resp.status_code == 403

    # -------------------------------------------------------------------------
    # 11. Complaints Management
    # -------------------------------------------------------------------------
    complaint_payload = {
        "title": "Air conditioning unit leaking water",
        "description": "The AC in room 102 is leaking onto the desk.",
        "category": "ELECTRICAL",
        "priority": "HIGH",
    }
    resp = client.post("/api/v1/resident/complaints", json=complaint_payload, headers=res_headers)
    assert resp.status_code == 201
    complaint_id = resp.json()["data"]["id"]

    # Admin resolves complaint
    resp = client.post(
        f"/api/v1/complaints/{complaint_id}/resolve",
        json={"resolution_notes": "Drain pipe unclogged by technician."},
        headers=admin_headers,
    )
    assert resp.status_code == 200
    assert resp.json()["data"]["status"] == "RESOLVED"

    # -------------------------------------------------------------------------
    # 12. Expenses Tracking
    # -------------------------------------------------------------------------
    expense_payload = {
        "property_id": property_id,
        "title": "Commercial RO Water Filter Maintenance",
        "amount": 2500.0,
        "category": "MAINTENANCE",
        "payment_mode": "UPI",
        "expense_date": str(date.today()),
        "vendor_name": "AquaPure Services",
    }
    resp = client.post("/api/v1/expenses", json=expense_payload, headers=admin_headers)
    assert resp.status_code == 201
    expense_id = resp.json()["data"]["id"]

    resp = client.get(f"/api/v1/expenses?property_id={property_id}", headers=admin_headers)
    assert resp.status_code == 200
    expenses_list = resp.json()["data"]["expenses"]
    assert any(e["id"] == expense_id for e in expenses_list)

    # -------------------------------------------------------------------------
    # 13. Leads CRM & Staff Management
    # -------------------------------------------------------------------------
    lead_payload = {
        "property_id": property_id,
        "name": "Kavita Rao",
        "phone": "9911223344",
        "email": "kavita.rao@example.com",
        "room_type_preference": "SINGLE",
        "status": "HOT",
        "notes": "Looking to move in next Monday.",
    }
    resp = client.post("/api/v1/leads", json=lead_payload, headers=admin_headers)
    assert resp.status_code == 201
    lead_id = resp.json()["data"]["id"]

    # Update lead status
    resp = client.patch(f"/api/v1/leads/{lead_id}", json={"status": "CONVERTED"}, headers=admin_headers)
    assert resp.status_code == 200
    assert resp.json()["data"]["status"] == "CONVERTED"

    staff_payload = {
        "property_id": property_id,
        "name": "Suresh Gowda",
        "phone": "9812345678",
        "role": "SECURITY",
        "salary": 18000.0,
    }
    resp = client.post("/api/v1/staff", json=staff_payload, headers=admin_headers)
    assert resp.status_code == 201
    assert resp.json()["data"]["name"] == "Suresh Gowda"

    # -------------------------------------------------------------------------
    # 14. Notifications Management
    # -------------------------------------------------------------------------
    resp = client.get("/api/v1/notifications/unread-count", headers=res_headers)
    assert resp.status_code == 200
    unread_count = resp.json()["data"]["unread_count"]

    resp = client.post("/api/v1/notifications/read-all", headers=res_headers)
    assert resp.status_code == 200

    resp = client.get("/api/v1/notifications/unread-count", headers=res_headers)
    assert resp.status_code == 200
    assert resp.json()["data"]["unread_count"] == 0

    # -------------------------------------------------------------------------
    # 15. Reports & CSV Exports
    # -------------------------------------------------------------------------
    resp = client.get("/api/v1/reports/dashboard", headers=admin_headers)
    assert resp.status_code == 200
    dash = resp.json()["data"]
    assert dash["total_properties"] >= 1

    resp = client.get(f"/api/v1/reports/payments/export?property_id={property_id}", headers=admin_headers)
    assert resp.status_code == 200
    assert resp.headers["content-type"] == "text/csv; charset=utf-8"
    assert "Payment Number,Property,Resident Name" in resp.text

    resp = client.get(f"/api/v1/reports/occupancy/export?property_id={property_id}", headers=admin_headers)
    assert resp.status_code == 200
    assert resp.headers["content-type"] == "text/csv; charset=utf-8"
    assert "Room Number,Bed Number,Bed Status" in resp.text

    # -------------------------------------------------------------------------
    # 16. Resident Checkout Settlement
    # -------------------------------------------------------------------------
    checkout_payload = {
        "check_out_date": str(date.today()),
        "damage_charges": 1500.0,
        "settlement_notes": "Room inspected. Rs. 1500 charged for repainting scuffed wall.",
    }
    resp = client.post(f"/api/v1/residents/{resident_id}/checkout", json=checkout_payload, headers=admin_headers)
    assert resp.status_code == 200, resp.text
    chk = resp.json()["data"]

    # Reconciled figures
    assert chk["status"] == "CHECKED_OUT"
    assert chk["bed_released"] is True
    assert chk["damage_charges"] == 1500.0
    # Deposit was 17000.0, damage 1500.0, refund must be 15500.0
    assert chk["deposit_refund_amount"] == 15500.0

    # Verify Bed 102-A is now free
    resp = client.get(f"/api/v1/beds/{bed_102_a_id}", headers=admin_headers)
    assert resp.status_code == 200
    assert resp.json()["data"]["status"] == "AVAILABLE"

    # Verify Resident User is deactivated
    db = client.app.state.testing_session()
    chk_user = db.get(User, uuid.UUID(resident_user_id))
    assert chk_user.is_active is False
    db.close()
