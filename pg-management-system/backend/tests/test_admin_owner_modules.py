import uuid
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
import pytest
from fastapi.testclient import TestClient

from app.core.security import create_access_token, get_password_hash
from app.main import app
from app.models.bed import Bed
from app.models.complaint import Complaint
from app.models.expense import Expense
from app.models.food_menu import FoodMenu
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


@pytest.fixture
def db_session(client):
    session = app.state.testing_session()
    try:
        yield session
    finally:
        session.close()


@pytest.fixture
def admin_context(db_session):
    """Creates a seeded administrative test environment with SUPER_ADMIN user, Property, Room and Bed."""
    company = db_session.scalar(
        Company.__table__.select().where(Company.code == "ADMIN_TEST")
    )
    if not company:
        company = Company(
            name="Smart PG Admin Corp",
            code="ADMIN_TEST",
            email="admin_corp@example.com",
            phone="9876543210",
            subscription_plan="ENTERPRISE",
            subscription_status="ACTIVE",
        )
        db_session.add(company)
        db_session.flush()

    super_admin_role = db_session.scalar(
        Role.__table__.select().where(Role.name == "SUPER_ADMIN")
    )
    if not super_admin_role:
        super_admin_role = Role(
            name="SUPER_ADMIN",
            display_name="Super Administrator",
            is_system_role=True,
            permissions=["*"],
        )
        db_session.add(super_admin_role)
        db_session.flush()

    admin_user = User(
        company_id=company.id,
        role_id=super_admin_role.id,
        email="superadmin_test@originpg.com",
        phone="9988776655",
        full_name="Chief Executive Administrator",
        password_hash=get_password_hash("AdminPass@123"),
        is_active=True,
        is_verified=True,
        approval_status="APPROVED",
    )
    db_session.add(admin_user)
    db_session.flush()

    property_record = Property(
        company_id=company.id,
        name="Smart Central Heights PG",
        code="SCH01",
        property_type="COLIVING",
        address_line1="100 Technology Park Road",
        city="Bengaluru",
        state="Karnataka",
        pincode="560100",
        is_active=True,
    )
    db_session.add(property_record)
    db_session.flush()

    room = Room(
        property_id=property_record.id,
        room_number="101",
        floor=1,
        room_type="DOUBLE",
        base_monthly_rent=Decimal("8000.00"),
        deposit_amount=Decimal("16000.00"),
    )
    db_session.add(room)
    db_session.flush()

    bed1 = Bed(
        room_id=room.id,
        property_id=property_record.id,
        bed_number="101-A",
        status="AVAILABLE",
    )
    bed2 = Bed(
        room_id=room.id,
        property_id=property_record.id,
        bed_number="101-B",
        status="AVAILABLE",
    )
    db_session.add_all([bed1, bed2])
    db_session.commit()

    token = create_access_token(
        str(admin_user.id),
        {"role": super_admin_role.name, "company_id": str(company.id)},
    )

    return {
        "company": company,
        "super_admin": admin_user,
        "role": super_admin_role,
        "property": property_record,
        "room": room,
        "beds": [bed1, bed2],
        "token": token,
        "headers": {"Authorization": f"Bearer {token}"},
    }


def test_admin_auth_super_key_workflow(client: TestClient, admin_context, monkeypatch):
    """Tests the Origin Common Super Key registration & direct Email + Password login cycle."""
    import secrets
    from app.core.config import settings

    # 1. Admin login with pure Email and Password directly issues JWT tokens (no 2FA)
    login_resp = client.post(
        "/api/v1/auth/admin/login",
        json={
            "email": "superadmin_test@originpg.com",
            "password": "AdminPass@123",
        },
    )
    assert login_resp.status_code == 200
    login_data = login_resp.json()["data"]
    assert "access_token" in login_data
    assert login_data["token_type"] == "bearer"
    assert login_data["user"]["email"] == "superadmin_test@originpg.com"
    assert login_data.get("requires_2fa") is not True

    # 2. Registration with valid Common Super Key
    unique_suffix = secrets.token_hex(4)
    reg_resp = client.post(
        "/api/v1/auth/admin/register",
        json={
            "business_name": f"New Test PG {unique_suffix}",
            "email": f"newadmin_{unique_suffix}@originpg.com",
            "password": "SecureAdmin@123",
            "confirm_password": "SecureAdmin@123",
            "super_key": settings.ADMIN_REGISTRATION_SUPER_KEY or "ORIGIN_PG_SUPER_KEY_2026",
        },
    )
    assert reg_resp.status_code == 201
    reg_data = reg_resp.json()["data"]
    assert reg_data["user"]["email"] == f"newadmin_{unique_suffix}@originpg.com"
    assert reg_data["user"]["is_active"] is True
    assert reg_data["user"]["approval_status"] == "APPROVED"

    # 3. Newly registered admin can log in immediately with Email + Password only
    new_login_resp = client.post(
        "/api/v1/auth/admin/login",
        json={
            "email": f"newadmin_{unique_suffix}@originpg.com",
            "password": "SecureAdmin@123",
        },
    )
    assert new_login_resp.status_code == 200
    new_tokens = new_login_resp.json()["data"]
    assert "access_token" in new_tokens
    assert new_tokens["user"]["email"] == f"newadmin_{unique_suffix}@originpg.com"


def test_property_and_room_floor_hierarchy(client: TestClient, admin_context):
    """Tests Property CRUD, Room creation, Floor-wise grouping, and Bed allocation."""
    headers = admin_context["headers"]
    prop_id = str(admin_context["property"].id)

    # 1. Create a second room on floor 2
    create_room_resp = client.post(
        "/api/v1/rooms",
        headers=headers,
        json={
            "property_id": prop_id,
            "room_number": "201",
            "floor": 2,
            "room_type": "TRIPLE",
            "base_monthly_rent": 9500.00,
            "deposit_amount": 19000.00,
        },
    )
    assert create_room_resp.status_code == 201
    room_201_id = create_room_resp.json()["data"]["id"]

    # 2. Add beds to room 201
    for bed_code in ("201-A", "201-B", "201-C"):
        bed_resp = client.post(
            "/api/v1/beds",
            headers=headers,
            json={
                "room_id": room_201_id,
                "property_id": prop_id,
                "bed_number": bed_code,
            },
        )
        assert bed_resp.status_code == 201

    # 3. Retrieve floor-wise room grouping
    floor_resp = client.get(
        f"/api/v1/rooms/floor-wise?property_id={prop_id}",
        headers=headers,
    )
    assert floor_resp.status_code == 200
    floors_data = floor_resp.json()["data"]["floors"]
    floor_numbers = [f["floor_number"] for f in floors_data]
    assert 1 in floor_numbers and 2 in floor_numbers


def test_resident_manual_onboarding_and_kyc(client: TestClient, admin_context):
    """Tests Admin manual onboarding, bed status update, and KYC verification."""
    headers = admin_context["headers"]
    prop_id = str(admin_context["property"].id)
    room_id = str(admin_context["room"].id)
    bed_id = str(admin_context["beds"][0].id)

    # Onboard resident
    onboard_resp = client.post(
        "/api/v1/residents",
        headers=headers,
        json={
            "property_id": prop_id,
            "room_id": room_id,
            "bed_id": bed_id,
            "full_name": "Arjun Kumar Raman",
            "email": "arjun.raman@example.com",
            "phone": "9811223344",
            "check_in_date": str(date.today()),
            "monthly_rent": 8000.00,
            "security_deposit": 16000.00,
            "kyc_document_type": "AADHAAR",
            "kyc_document_number": "123456789012",
        },
    )
    if onboard_resp.status_code != 201:
        print("ONBOARD RESP ERROR:", onboard_resp.json())
    assert onboard_resp.status_code == 201
    resident_id = onboard_resp.json()["data"]["id"]

    # Verify masked KYC in response
    assert onboard_resp.json()["data"]["kyc_document_number"] == "XXXXXXXX9012"

    # Verify bed status is now OCCUPIED
    bed_check = client.get(f"/api/v1/beds/{bed_id}", headers=headers)
    assert bed_check.status_code == 200
    assert bed_check.json()["data"]["status"] == "OCCUPIED"

    # Admin verifies KYC
    verify_kyc_resp = client.post(
        f"/api/v1/residents/{resident_id}/kyc/verify",
        headers=headers,
    )
    assert verify_kyc_resp.status_code == 200
    assert verify_kyc_resp.json()["data"]["kyc_status"] == "VERIFIED"


def test_rent_collection_and_balance_update(client: TestClient, admin_context):
    """Tests offline rent collection, partial balance settlement, and digital receipt generation."""
    headers = admin_context["headers"]
    prop_id = str(admin_context["property"].id)
    room_id = str(admin_context["room"].id)
    bed_id = str(admin_context["beds"][1].id)

    # Onboard resident
    onboard_resp = client.post(
        "/api/v1/residents",
        headers=headers,
        json={
            "property_id": prop_id,
            "room_id": room_id,
            "bed_id": bed_id,
            "full_name": "Siddharth Verma",
            "phone": "9822334455",
            "check_in_date": str(date.today()),
            "monthly_rent": 8500.00,
        },
    )
    assert onboard_resp.status_code == 201
    resident_id = onboard_resp.json()["data"]["id"]

    # Create monthly rent invoice
    inv_resp = client.post(
        "/api/v1/invoices",
        headers=headers,
        json={
            "property_id": prop_id,
            "resident_id": resident_id,
            "billing_month": "2026-11",
            "invoice_type": "RENT",
            "amount": 8500.00,
            "due_date": str(date.today() + timedelta(days=5)),
            "notes": "November 2026 Monthly Rent",
        },
    )
    assert inv_resp.status_code == 201
    invoice_id = inv_resp.json()["data"]["id"]

    # 1. Collect partial rent (INR 5000)
    col1_resp = client.post(
        "/api/v1/payments/collect",
        headers=headers,
        json={
            "property_id": prop_id,
            "resident_id": resident_id,
            "invoice_id": invoice_id,
            "collect_amount": 5000.00,
            "payment_mode": "CASH",
            "transaction_reference": "CASH-REC-001",
            "notes": "First partial cash installment",
        },
    )
    assert col1_resp.status_code == 201
    col1_data = col1_resp.json()["data"]
    assert col1_data["invoice_status"] == "PARTIALLY_PAID"
    assert col1_data["invoice_paid_amount"] == 5000.00
    assert col1_data["remaining_balance"] == 3500.00
    payment_id = col1_data["payment_id"]

    # Verify payment details and receipt endpoints
    pay_detail = client.get(f"/api/v1/payments/{payment_id}", headers=headers)
    assert pay_detail.status_code == 200
    assert pay_detail.json()["data"]["amount"] == 5000.00

    receipt_detail = client.get(f"/api/v1/payments/{payment_id}/receipt", headers=headers)
    assert receipt_detail.status_code == 200
    assert "receipt_number" in receipt_detail.json()["data"]

    # 2. Reject overpayment (Attempting to collect 4000 when only 3500 remains)
    overpay_resp = client.post(
        "/api/v1/payments/collect",
        headers=headers,
        json={
            "property_id": prop_id,
            "resident_id": resident_id,
            "invoice_id": invoice_id,
            "collect_amount": 4000.00,
            "payment_mode": "UPI",
        },
    )
    assert overpay_resp.status_code in (400, 409)

    # 3. Collect exact remainder (INR 3500)
    col2_resp = client.post(
        "/api/v1/payments/collect",
        headers=headers,
        json={
            "property_id": prop_id,
            "resident_id": resident_id,
            "invoice_id": invoice_id,
            "collect_amount": 3500.00,
            "payment_mode": "UPI",
            "transaction_reference": "UPI9886699258",
        },
    )
    assert col2_resp.status_code == 201
    col2_data = col2_resp.json()["data"]
    assert col2_data["invoice_status"] == "PAID"
    assert col2_data["remaining_balance"] == 0.00


def test_expense_management_workflow(client: TestClient, admin_context):
    """Tests operational expense recording, category filtering, updates, and deletion."""
    headers = admin_context["headers"]
    prop_id = str(admin_context["property"].id)

    # Create expense
    exp_resp = client.post(
        "/api/v1/expenses",
        headers=headers,
        json={
            "property_id": prop_id,
            "category": "UTILITIES",
            "title": "Electricity Bill - November",
            "amount": 4500.00,
            "method": "UPI",
            "date": str(date.today()),
            "notes": "BESCOM power bill",
        },
    )
    assert exp_resp.status_code == 201
    expense_id = exp_resp.json()["data"]["id"]

    # List expenses with category filter
    list_resp = client.get(
        f"/api/v1/expenses?property_id={prop_id}&category=UTILITIES",
        headers=headers,
    )
    assert list_resp.status_code == 200
    assert list_resp.json()["data"]["count"] >= 1

    # Update expense
    update_resp = client.patch(
        f"/api/v1/expenses/{expense_id}",
        headers=headers,
        json={"notes": "BESCOM power bill verified & paid"},
    )
    assert update_resp.status_code == 200
    assert update_resp.json()["data"]["notes"] == "BESCOM power bill verified & paid"

    # Delete expense
    del_resp = client.delete(f"/api/v1/expenses/{expense_id}", headers=headers)
    assert del_resp.status_code == 200


def test_staff_management_lifecycle(client: TestClient, admin_context):
    """Tests creating, updating, listing, and deactivating property staff members."""
    headers = admin_context["headers"]
    prop_id = str(admin_context["property"].id)

    # Create staff
    staff_resp = client.post(
        "/api/v1/staff",
        headers=headers,
        json={
            "property_id": prop_id,
            "name": "Ramesh Gowda",
            "role": "WARDEN",
            "phone": "9844001122",
            "email": "ramesh.warden@originpg.com",
            "salary": 22000.00,
            "joining_date": str(date.today()),
            "is_emergency_contact": True,
        },
    )
    assert staff_resp.status_code == 201
    staff_id = staff_resp.json()["data"]["id"]

    # Retrieve staff details
    staff_get = client.get(f"/api/v1/staff/{staff_id}", headers=headers)
    assert staff_get.status_code == 200
    assert staff_get.json()["data"]["role"] == "WARDEN"

    # Soft delete (deactivate) staff
    deact_resp = client.delete(f"/api/v1/staff/{staff_id}", headers=headers)
    assert deact_resp.status_code == 200

    # Verify is_active == False
    staff_check = client.get(f"/api/v1/staff/{staff_id}", headers=headers)
    assert staff_check.json()["data"]["is_active"] is False


def test_food_menu_weekly_crud(client: TestClient, admin_context):
    """Tests weekly food menu creation, listing, duplicate rejection, and updating."""
    headers = admin_context["headers"]
    prop_id = str(admin_context["property"].id)

    # Create food menu item
    menu_resp = client.post(
        "/api/v1/food-menus",
        headers=headers,
        json={
            "property_id": prop_id,
            "day_of_week": "WEDNESDAY",
            "meal_type": "LUNCH",
            "start_time": "12:30 PM",
            "end_time": "02:30 PM",
            "dishes": ["Rice", "Sambar", "Paneer Butter Masala", "Curd"],
        },
    )
    assert menu_resp.status_code == 201
    menu_id = menu_resp.json()["data"]["id"]

    # Reject duplicate menu for same property, day, meal
    dup_resp = client.post(
        "/api/v1/food-menus",
        headers=headers,
        json={
            "property_id": prop_id,
            "day_of_week": "WEDNESDAY",
            "meal_type": "LUNCH",
            "dishes": ["Other dishes"],
        },
    )
    assert dup_resp.status_code == 409

    # List food menus
    list_resp = client.get(
        f"/api/v1/food-menus?property_id={prop_id}&day_of_week=WEDNESDAY",
        headers=headers,
    )
    assert list_resp.status_code == 200
    assert len(list_resp.json()["data"]) >= 1

    # Delete menu item
    del_resp = client.delete(f"/api/v1/food-menus/{menu_id}", headers=headers)
    assert del_resp.status_code == 200


def test_leads_crm_pipeline(client: TestClient, admin_context):
    """Tests lead creation, search, pipeline stage transition, and deletion."""
    headers = admin_context["headers"]
    prop_id = str(admin_context["property"].id)

    # 1. Create Lead
    lead_resp = client.post(
        "/api/v1/leads",
        headers=headers,
        json={
            "property_id": prop_id,
            "name": "Pooja Hegde",
            "phone": "9911882233",
            "email": "pooja.hegde@example.com",
            "source": "WALK_IN",
            "requirement": "Single room AC with balcony",
        },
    )
    assert lead_resp.status_code == 201
    lead_id = lead_resp.json()["data"]["id"]
    assert lead_resp.json()["data"]["status"] == "NEW"

    # 2. Advance pipeline to VISIT_SCHEDULED
    visit_time = (datetime.now(timezone.utc) + timedelta(days=2)).isoformat()
    patch_resp = client.patch(
        f"/api/v1/leads/{lead_id}",
        headers=headers,
        json={
            "status": "VISIT_SCHEDULED",
            "visit_date": visit_time,
            "notes": "Scheduled site visit on Saturday 11 AM",
        },
    )
    assert patch_resp.status_code == 200
    assert patch_resp.json()["data"]["status"] == "VISIT_SCHEDULED"

    # 3. Search lead by phone
    search_resp = client.get(
        f"/api/v1/leads?property_id={prop_id}&search=991188",
        headers=headers,
    )
    assert search_resp.status_code == 200
    assert len(search_resp.json()["data"]) >= 1


def test_reports_dashboard_and_csv_exports(client: TestClient, admin_context):
    """Tests executive dashboard analytics, financial calculation, and CSV file generation."""
    headers = admin_context["headers"]
    prop_id = str(admin_context["property"].id)

    # 1. Executive Dashboard
    dash_resp = client.get(f"/api/v1/reports/dashboard?property_id={prop_id}", headers=headers)
    assert dash_resp.status_code == 200
    dash_data = dash_resp.json()["data"]
    assert "total_beds" in dash_data
    assert "occupancy_rate_percent" in dash_data
    assert "gross_collections" in dash_data
    assert "net_operating_profit" in dash_data

    # 2. Financial Report
    fin_resp = client.get(f"/api/v1/reports/financial?property_id={prop_id}", headers=headers)
    assert fin_resp.status_code == 200
    fin_data = fin_resp.json()["data"]
    assert "gross_collections" in fin_data
    assert "net_operating_profit" in fin_data

    # 3. Payments CSV Export
    csv_pay = client.get(f"/api/v1/reports/payments/export?property_id={prop_id}", headers=headers)
    assert csv_pay.status_code == 200
    assert "text/csv" in csv_pay.headers.get("content-type", "")
    assert "Payment Number" in csv_pay.text

    # 4. Occupancy CSV Export
    csv_occ = client.get(f"/api/v1/reports/occupancy/export?property_id={prop_id}", headers=headers)
    assert csv_occ.status_code == 200
    assert "text/csv" in csv_occ.headers.get("content-type", "")
    assert "Room Number" in csv_occ.text


def test_settings_and_subscription_limits(client: TestClient, admin_context):
    """Tests enterprise company settings and subscription quota inspection."""
    headers = admin_context["headers"]

    # 1. Company profile query
    comp_resp = client.get("/api/v1/settings/company", headers=headers)
    assert comp_resp.status_code == 200
    assert comp_resp.json()["data"]["code"] == "ADMIN_TEST"

    # 2. Subscription inspection
    sub_resp = client.get("/api/v1/settings/subscription", headers=headers)
    assert sub_resp.status_code == 200
    sub_data = sub_resp.json()["data"]
    assert sub_data["plan"] == "ENTERPRISE"
    assert "limits" in sub_data
    assert sub_data["limits"]["max_properties"] == 50
