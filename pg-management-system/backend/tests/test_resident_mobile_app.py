import io
import uuid
from datetime import date, datetime, timedelta, timezone
import pytest
from fastapi.testclient import TestClient

from app.core.security import create_access_token, create_refresh_token, get_password_hash
from app.models.bed import Bed
from app.models.complaint import Complaint
from app.models.food_menu import FoodMenu
from app.models.invoice import Invoice
from app.models.notice import Notice
from app.models.payment import Payment
from app.models.property import Company, Property
from app.models.receipt import Receipt
from app.models.resident import Resident
from app.models.role import Role
from app.models.room import Room
from app.models.staff import Staff
from app.models.user import User, RefreshToken


@pytest.fixture
def resident_test_context(client: TestClient):
    """
    Sets up a complete realistic test fixture with:
    - Company, Roles (SUPER_ADMIN, RESIDENT, PROPERTY_MANAGER)
    - 2 Properties
    - Rooms & Beds
    - 2 Approved Active Residents (Resident A in Prop 1, Resident B in Prop 2)
    - 1 Pending Resident (Pending Approval)
    - 1 Inactive Resident
    - Invoices, Payments, Receipts
    - Food Menus (active & inactive)
    - Staff Members (Manager, Caretaker, Security)
    - Notices
    """
    session_factory = client.app.state.testing_session
    db = session_factory()
    try:
        # Company
        company = Company(name="Smart Group Stays", code="SMART_CO")
        db.add(company)
        db.flush()

        # Roles
        admin_role = Role(name="SUPER_ADMIN", display_name="Super Admin")
        resident_role = Role(name="RESIDENT", display_name="Resident")
        pm_role = Role(name="PROPERTY_MANAGER", display_name="Property Manager")
        db.add_all([admin_role, resident_role, pm_role])
        db.flush()

        # Property 1 & Property 2
        prop_1 = Property(
            company_id=company.id,
            name="Smart Grand PG - Koramangala",
            code="SMART_KORA",
            property_type="CO_LIVING",
            address_line1="45, 80 Feet Road, 4th Block",
            city="Bangalore",
            state="Karnataka",
            pincode="560034",
            contact_phone="9886699258",
            contact_email="kora@smartgrouppg.com",
            total_floors=4,
            is_active=True,
            amenities=["High-Speed Wi-Fi", "Daily Housekeeping", "RO Drinking Water"],
            rules=["Gate closes at 10:30 PM", "No smoking"],
        )
        prop_2 = Property(
            company_id=company.id,
            name="Smart Elite PG - HSR Layout",
            code="SMART_HSR",
            property_type="MENS_PG",
            address_line1="12, 27th Main Road, Sector 1",
            city="Bangalore",
            state="Karnataka",
            pincode="560102",
            contact_phone="9886699259",
            contact_email="hsr@smartgrouppg.com",
            total_floors=3,
            is_active=True,
        )
        db.add_all([prop_1, prop_2])
        db.flush()

        # Rooms & Beds for Prop 1
        room_101 = Room(
            property_id=prop_1.id,
            room_number="101",
            floor_number=1,
            room_type="DOUBLE_SHARING",
            max_occupancy=2,
            base_rent=8500.00,
            amenities={"wifi": True, "ac": True, "attached_washroom": True},
            is_active=True,
        )
        db.add(room_101)
        db.flush()

        bed_101_a = Bed(
            room_id=room_101.id,
            bed_number="101-A",
            monthly_rent=8500.00,
            status="OCCUPIED",
        )
        db.add(bed_101_a)
        db.flush()

        # 1. Resident A (Approved, Active in Prop 1)
        user_a = User(
            company_id=company.id,
            role_id=resident_role.id,
            email="resident_a@originpg.com",
            phone="9876543210",
            full_name="Aarav Sharma",
            password_hash="!NO_PASSWORD_a",
            is_active=True,
            is_verified=True,
            approval_status="APPROVED",
        )
        db.add(user_a)
        db.flush()

        resident_a = Resident(
            property_id=prop_1.id,
            room_id=room_101.id,
            bed_id=bed_101_a.id,
            user_id=user_a.id,
            check_in_date=date(2026, 10, 1),
            monthly_rent=8500.00,
            security_deposit=15000.00,
            status="ACTIVE",
            kyc_status="VERIFIED",
            id_proof_type="AADHAAR",
            id_proof_number_masked="XXXX-XXXX-8921",
            verification_method="AADHAAR_PAN",
            aadhaar_front_path="/uploads/kyc/aadhaar_front_a.jpg",
            aadhaar_back_path="/uploads/kyc/aadhaar_back_a.jpg",
            pan_card_path="/uploads/kyc/pan_card_a.jpg",
            resident_selfie_path="/uploads/kyc/selfie_a.jpg",
            house_flat_no="Flat 302, Green Heights",
            city="Pune",
            state="Maharashtra",
            pincode="411001",
            emergency_contact_name="Sunil Sharma",
            emergency_contact_phone="9876500001",
        )
        db.add(resident_a)
        db.flush()

        # 2. Resident B (Approved, Active in Prop 2)
        user_b = User(
            company_id=company.id,
            role_id=resident_role.id,
            email="resident_b@originpg.com",
            phone="9876543211",
            full_name="Bhavin Patel",
            password_hash="!NO_PASSWORD_b",
            is_active=True,
            is_verified=True,
            approval_status="APPROVED",
        )
        db.add(user_b)
        db.flush()

        resident_b = Resident(
            property_id=prop_2.id,
            user_id=user_b.id,
            check_in_date=date(2026, 10, 15),
            monthly_rent=9000.00,
            security_deposit=18000.00,
            status="ACTIVE",
            kyc_status="VERIFIED",
        )
        db.add(resident_b)
        db.flush()

        # 3. Pending Resident C (Unapproved)
        user_c = User(
            company_id=company.id,
            role_id=resident_role.id,
            email="resident_c@originpg.com",
            phone="9876543212",
            full_name="Chetan Kumar",
            password_hash="!NO_PASSWORD_c",
            is_active=True,
            is_verified=True,
            approval_status="PENDING_APPROVAL",
        )
        db.add(user_c)
        db.flush()

        resident_c = Resident(
            property_id=prop_1.id,
            user_id=user_c.id,
            check_in_date=date(2026, 11, 1),
            monthly_rent=8500.00,
            security_deposit=15000.00,
            status="PENDING_APPROVAL",
        )
        db.add(resident_c)
        db.flush()

        # 4. Inactive Resident D
        user_d = User(
            company_id=company.id,
            role_id=resident_role.id,
            email="resident_d@originpg.com",
            phone="9876543213",
            full_name="Dinesh Inactive",
            password_hash="!NO_PASSWORD_d",
            is_active=False,
            is_verified=True,
            approval_status="APPROVED",
        )
        db.add(user_d)
        db.flush()

        resident_d = Resident(
            property_id=prop_1.id,
            user_id=user_d.id,
            check_in_date=date(2026, 9, 1),
            monthly_rent=8500.00,
            security_deposit=15000.00,
            status="ACTIVE",
        )
        db.add(resident_d)
        db.flush()

        # 5. Admin User
        user_admin = User(
            company_id=company.id,
            role_id=admin_role.id,
            email="admin@smartgrouppg.com",
            phone="9800000001",
            full_name="Admin Boss",
            password_hash=get_password_hash("AdminPass123!"),
            is_active=True,
            is_verified=True,
            approval_status="APPROVED",
        )
        db.add(user_admin)
        db.flush()

        # Invoices for Resident A
        inv_a = Invoice(
            property_id=prop_1.id,
            resident_id=resident_a.id,
            invoice_number="INV-202611-0001",
            billing_month="2026-11",
            invoice_type="RENT",
            amount=8500.00,
            paid_amount=0.00,
            due_date=date.today() + timedelta(days=4),
            status="PENDING",
            notes="November Rent",
        )
        db.add(inv_a)
        db.flush()

        # Payment for Resident A (Past month)
        pay_a = Payment(
            property_id=prop_1.id,
            invoice_id=inv_a.id,
            resident_id=resident_a.id,
            payment_number="PAY-202610-0001",
            amount=8500.00,
            payment_mode="UPI",
            status="SUCCESS",
            paid_at=datetime.now(timezone.utc) - timedelta(days=30),
        )
        db.add(pay_a)
        db.flush()

        # Receipt for Resident A
        rcpt_a = Receipt(
            payment_id=pay_a.id,
            invoice_id=inv_a.id,
            receipt_number="RCP-202610-0001",
            amount=8500.00,
        )
        db.add(rcpt_a)

        # Invoice for Resident B
        inv_b = Invoice(
            property_id=prop_2.id,
            resident_id=resident_b.id,
            invoice_number="INV-202611-0002",
            billing_month="2026-11",
            invoice_type="RENT",
            amount=9000.00,
            paid_amount=9000.00,
            due_date=date.today() + timedelta(days=5),
            status="PAID",
        )
        db.add(inv_b)

        # Notices for Prop 1
        notice_1 = Notice(
            property_id=prop_1.id,
            created_by_user_id=user_admin.id,
            title="Diwali Celebration & Sweets",
            content="Join us in the cafeteria this Saturday at 7 PM for celebrations!",
            is_pinned=True,
        )
        db.add(notice_1)

        # Food Menu for Prop 1 (Active & Inactive)
        menu_mon_bf = FoodMenu(
            property_id=prop_1.id,
            day_of_week="MONDAY",
            meal_type="BREAKFAST",
            start_time="07:30 AM",
            end_time="09:30 AM",
            dishes=["Masala Dosa", "Sambar", "Coconut Chutney", "Filter Coffee"],
            is_active=True,
        )
        menu_mon_dn = FoodMenu(
            property_id=prop_1.id,
            day_of_week="MONDAY",
            meal_type="DINNER",
            start_time="08:00 PM",
            end_time="10:00 PM",
            dishes=["Paneer Butter Masala", "Roti", "Jeera Rice", "Gulab Jamun"],
            is_active=True,
        )
        menu_inactive = FoodMenu(
            property_id=prop_1.id,
            day_of_week="TUESDAY",
            meal_type="BREAKFAST",
            start_time="07:30 AM",
            end_time="09:30 AM",
            dishes=["Archived Dish Item"],
            is_active=False,
        )
        db.add_all([menu_mon_bf, menu_mon_dn, menu_inactive])

        # Staff for Prop 1
        manager_staff = Staff(
            company_id=company.id,
            property_id=prop_1.id,
            name="Ramesh Reddy",
            role="PROPERTY_MANAGER",
            phone="9886611223",
            salary=35000.00,
            is_active=True,
            availability_hours="9:00 AM - 7:00 PM",
            is_emergency_contact=True,
        )
        caretaker_staff = Staff(
            company_id=company.id,
            property_id=prop_1.id,
            name="Suresh Caretaker",
            role="NIGHT_CARETAKER",
            phone="9886611224",
            salary=20000.00,
            is_active=True,
            availability_hours="8:00 PM - 8:00 AM",
            is_emergency_contact=True,
        )
        # Staff for Prop 2 (Prop 2 staff should NOT leak to Prop 1 resident)
        hsr_manager = Staff(
            company_id=company.id,
            property_id=prop_2.id,
            name="HSR Manager Vikram",
            role="PROPERTY_MANAGER",
            phone="9886699999",
            salary=35000.00,
            is_active=True,
        )
        db.add_all([manager_staff, caretaker_staff, hsr_manager])

        # Refresh token for resident A (to test logout)
        refresh_token_a = create_refresh_token(str(user_a.id))
        raw_token_a = refresh_token_a
        import hashlib
        token_hash = hashlib.sha256(raw_token_a.encode()).hexdigest()
        db_token = RefreshToken(
            user_id=user_a.id,
            token_hash=token_hash,
            client_type="resident_mobile",
            expires_at=datetime.now(timezone.utc) + timedelta(days=30),
            is_revoked=False,
        )
        db.add(db_token)

        db.commit()

        # Generate tokens
        token_a = create_access_token(str(user_a.id))
        token_b = create_access_token(str(user_b.id))
        token_c = create_access_token(str(user_c.id))
        token_d = create_access_token(str(user_d.id))
        token_admin = create_access_token(str(user_admin.id))

        return {
            "token_a": token_a,
            "token_b": token_b,
            "token_c": token_c,
            "token_d": token_d,
            "token_admin": token_admin,
            "refresh_token_a": raw_token_a,
            "user_a_id": user_a.id,
            "resident_a_id": resident_a.id,
            "prop_1_id": prop_1.id,
            "prop_2_id": prop_2.id,
            "inv_a_id": inv_a.id,
            "inv_b_id": inv_b.id,
        }
    finally:
        db.close()


# ---------------------------------------------------------------------------
# MODULE 1: Resident Home Dashboard
# ---------------------------------------------------------------------------
def test_resident_dashboard_complete(client: TestClient, resident_test_context):
    headers = {"Authorization": f"Bearer {resident_test_context['token_a']}"}
    resp = client.get("/api/v1/resident/dashboard", headers=headers)
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["success"] is True

    data = body["data"]
    # 1. Resident info
    assert data["resident_info"]["full_name"] == "Aarav Sharma"
    assert data["resident_info"]["status"] == "ACTIVE"

    # 2. Stay details & Living Since
    stay = data["stay_details"]
    assert stay["property_name"] == "Smart Grand PG - Koramangala"
    assert stay["room_number"] == "101"
    assert stay["floor_number"] == 1
    assert stay["bed_number"] == "101-A"
    assert stay["living_since"] == "2026-10-01"
    assert stay["monthly_rent"] == 8500.0

    # 3. Rent summary & Pay Now
    rent = data["rent_summary"]
    assert rent["current_rent_amount"] == 8500.0
    assert rent["outstanding_dues"] == 8500.0
    assert rent["rent_payment_status"] == "DUE"
    assert rent["pay_now"] is not None
    assert rent["pay_now"]["can_pay"] is True
    assert rent["pay_now"]["amount_due"] == 8500.0
    assert "UPI" in rent["pay_now"]["payment_methods"]
    assert len(rent["rent_reminders"]) >= 1

    # 4. Recent notices
    assert len(data["recent_notices"]) >= 1
    assert data["recent_notices"][0]["title"] == "Diwali Celebration & Sweets"

    # 5. Last three payments (max 3)
    payments = data["recent_payments"]
    assert len(payments) <= 3
    assert payments[0]["amount"] == 8500.0
    assert payments[0]["payment_mode"] == "UPI"
    assert payments[0]["receipt_available"] is True


# ---------------------------------------------------------------------------
# MODULE 2: Weekly Food Menu
# ---------------------------------------------------------------------------
def test_resident_food_menu_complete(client: TestClient, resident_test_context):
    headers = {"Authorization": f"Bearer {resident_test_context['token_a']}"}
    resp = client.get("/api/v1/resident/food-menu", headers=headers)
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["success"] is True

    data = body["data"]
    assert data["property_name"] == "Smart Grand PG - Koramangala"
    assert "MONDAY" in data["menu_by_day"]
    assert "TUESDAY" in data["menu_by_day"]

    # Monday meals
    mon_meals = data["menu_by_day"]["MONDAY"]
    assert len(mon_meals) == 2
    # Verify sorted: Breakfast before Dinner
    assert mon_meals[0]["meal_type"] == "BREAKFAST"
    assert mon_meals[1]["meal_type"] == "DINNER"
    assert "Masala Dosa" in mon_meals[0]["dishes"]

    # Tuesday had an inactive menu item -> must be filtered out
    tue_meals = data["menu_by_day"]["TUESDAY"]
    assert len(tue_meals) == 0


def test_resident_food_menu_property_isolation(client: TestClient, resident_test_context):
    """Resident B in Prop 2 should receive Prop 2's menu, not Prop 1's."""
    headers = {"Authorization": f"Bearer {resident_test_context['token_b']}"}
    resp = client.get("/api/v1/resident/food-menu", headers=headers)
    assert resp.status_code == 200
    data = resp.json()["data"]
    assert data["property_name"] == "Smart Elite PG - HSR Layout"
    # Prop 2 has 0 food menus seeded
    for day, meals in data["menu_by_day"].items():
        assert len(meals) == 0


# ---------------------------------------------------------------------------
# MODULE 3: Rent, Invoices & Payments (with Strict Anti-IDOR Tests)
# ---------------------------------------------------------------------------
def test_resident_invoices_list(client: TestClient, resident_test_context):
    headers = {"Authorization": f"Bearer {resident_test_context['token_a']}"}
    resp = client.get("/api/v1/resident/invoices", headers=headers)
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["success"] is True
    assert len(body["data"]) == 1
    inv = body["data"][0]
    assert inv["invoice_number"] == "INV-202611-0001"
    assert inv["amount"] == 8500.0
    assert inv["outstanding_balance"] == 8500.0
    assert inv["can_pay"] is True


def test_resident_invoice_detail_and_anti_idor(client: TestClient, resident_test_context):
    inv_a_id = str(resident_test_context["inv_a_id"])
    headers_a = {"Authorization": f"Bearer {resident_test_context['token_a']}"}
    headers_b = {"Authorization": f"Bearer {resident_test_context['token_b']}"}

    # Resident A accesses own invoice -> 200
    resp_a = client.get(f"/api/v1/resident/invoices/{inv_a_id}", headers=headers_a)
    assert resp_a.status_code == 200
    assert resp_a.json()["data"]["id"] == inv_a_id
    assert resp_a.json()["data"]["pay_now"]["can_pay"] is True

    # Resident B attempts to access Resident A's invoice -> 404 Not Found (Anti-IDOR)
    resp_b = client.get(f"/api/v1/resident/invoices/{inv_a_id}", headers=headers_b)
    assert resp_b.status_code == 404


def test_resident_payments_history(client: TestClient, resident_test_context):
    headers = {"Authorization": f"Bearer {resident_test_context['token_a']}"}
    resp = client.get("/api/v1/resident/payments", headers=headers)
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["success"] is True
    assert len(body["data"]) == 1
    pay = body["data"][0]
    assert pay["amount"] == 8500.0
    assert pay["payment_mode"] == "UPI"
    assert pay["status"] == "SUCCESS"
    assert pay["receipt_available"] is True
    assert pay["receipt_number"] == "RCP-202610-0001"


# ---------------------------------------------------------------------------
# MODULE 4: My Profile & KYC Data Masking
# ---------------------------------------------------------------------------
def test_resident_profile_data_masking(client: TestClient, resident_test_context):
    headers = {"Authorization": f"Bearer {resident_test_context['token_a']}"}
    resp = client.get("/api/v1/resident/profile", headers=headers)
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["success"] is True

    data = body["data"]
    assert data["full_name"] == "Aarav Sharma"
    assert data["phone"] == "9876543210"
    assert data["living_since"] == "2026-10-01"
    assert data["permanent_address"]["city"] == "Pune"

    # KYC masking & security flags
    kyc = data["kyc_details"]
    assert kyc["kyc_status"] == "VERIFIED"
    assert kyc["id_proof_number_masked"] == "XXXX-XXXX-8921"
    assert kyc["has_aadhaar_front"] is True
    assert kyc["has_pan_card"] is True
    assert kyc["has_passport"] is False

    # Ensure internal file paths are NOT exposed
    assert "aadhaar_front_path" not in kyc
    assert "pan_card_path" not in kyc


# ---------------------------------------------------------------------------
# MODULE 5: Property Details
# ---------------------------------------------------------------------------
def test_resident_property_details(client: TestClient, resident_test_context):
    headers = {"Authorization": f"Bearer {resident_test_context['token_a']}"}
    resp = client.get("/api/v1/resident/property", headers=headers)
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["success"] is True

    data = body["data"]
    assert data["name"] == "Smart Grand PG - Koramangala"
    assert data["city"] == "Bangalore"
    assert data["assigned_room"]["room_number"] == "101"
    assert data["assigned_bed"]["bed_number"] == "101-A"
    assert len(data["amenities"]) >= 1
    assert len(data["inclusions"]) >= 1
    assert len(data["rules"]) >= 1


# ---------------------------------------------------------------------------
# MODULE 6: Raise Complaint, Photo Upload & Isolation
# ---------------------------------------------------------------------------
def test_resident_complaint_photo_upload_and_validation(client: TestClient, resident_test_context):
    headers = {"Authorization": f"Bearer {resident_test_context['token_a']}"}

    # 1. Valid photo upload (PNG)
    fake_png = io.BytesIO(b"\x89PNG\r\n\x1a\n" + b"\x00" * 100)
    files = {"photo": ("leakage.png", fake_png, "image/png")}
    resp_upload = client.post("/api/v1/resident/complaints/upload-photo", headers=headers, files=files)
    assert resp_upload.status_code == 200, resp_upload.text
    upload_data = resp_upload.json()["data"]
    assert "photo_path" in upload_data
    assert upload_data["photo_path"].startswith("uploads/kyc/")
    photo_path = upload_data["photo_path"]

    # 2. Invalid file extension rejected
    fake_exe = io.BytesIO(b"MZ\x90\x00" + b"\x00" * 50)
    files_bad = {"photo": ("malware.exe", fake_exe, "application/octet-stream")}
    resp_bad = client.post("/api/v1/resident/complaints/upload-photo", headers=headers, files=files_bad)
    assert resp_bad.status_code == 400

    # 3. Create complaint with uploaded photo
    payload = {
        "category": "PLUMBING",
        "title": "Water Leakage in Bathroom",
        "description": "Tap is leaking continuously under the sink.",
        "priority": "HIGH",
        "photo_path": photo_path,
    }
    resp_create = client.post("/api/v1/resident/complaints", json=payload, headers=headers)
    assert resp_create.status_code == 201, resp_create.text
    created = resp_create.json()["data"]
    assert created["category"] == "PLUMBING"
    assert created["photo_path"] == photo_path
    assert created["status"] == "PENDING"


def test_resident_complaint_invalid_category_rejected(client: TestClient, resident_test_context):
    headers = {"Authorization": f"Bearer {resident_test_context['token_a']}"}
    payload = {
        "category": "INVALID_CAT_XYZ",
        "title": "Some Issue",
        "description": "Details here",
    }
    resp = client.post("/api/v1/resident/complaints", json=payload, headers=headers)
    assert resp.status_code == 422


def test_resident_complaint_cross_resident_isolation(client: TestClient, resident_test_context):
    headers_a = {"Authorization": f"Bearer {resident_test_context['token_a']}"}
    headers_b = {"Authorization": f"Bearer {resident_test_context['token_b']}"}

    payload = {
        "category": "ELECTRICAL",
        "title": "Geyser Not Working",
        "description": "No hot water in room 101.",
        "priority": "MEDIUM",
    }
    resp_create = client.post("/api/v1/resident/complaints", json=payload, headers=headers_a)
    assert resp_create.status_code == 201
    complaint_id = resp_create.json()["data"]["id"]

    # Resident B cannot see Resident A's complaint
    resp_b = client.get("/api/v1/resident/complaints", headers=headers_b)
    assert resp_b.status_code == 200
    ids_b = [c["id"] for c in resp_b.json()["data"]]
    assert complaint_id not in ids_b


# ---------------------------------------------------------------------------
# MODULE 7: Property Contacts & Cross-Property Isolation
# ---------------------------------------------------------------------------
def test_resident_property_contacts_and_isolation(client: TestClient, resident_test_context):
    headers_a = {"Authorization": f"Bearer {resident_test_context['token_a']}"}
    resp = client.get("/api/v1/resident/property-contacts", headers=headers_a)
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["success"] is True

    data = body["data"]
    assert data["property_name"] == "Smart Grand PG - Koramangala"
    assert data["property_manager"] is not None
    assert data["property_manager"]["name"] == "Ramesh Reddy"
    assert data["property_manager"]["phone"] == "9886611223"

    assert data["night_caretaker_security"] is not None
    assert data["night_caretaker_security"]["name"] == "Suresh Caretaker"

    # Ensure Prop 2 staff does not leak into Prop 1 resident contacts
    all_names = [data["property_manager"]["name"]] + [s["name"] for s in data["staff_contacts"]]
    assert "HSR Manager Vikram" not in all_names


# ---------------------------------------------------------------------------
# MODULE 8: Resident Settings & Logout
# ---------------------------------------------------------------------------
def test_resident_settings_lifecycle_and_validation(client: TestClient, resident_test_context):
    headers = {"Authorization": f"Bearer {resident_test_context['token_a']}"}

    # 1. Initial GET
    resp_get = client.get("/api/v1/resident/settings", headers=headers)
    assert resp_get.status_code == 200
    assert resp_get.json()["data"]["language"] == "en"

    # 2. Valid PATCH (Kannada 'kn')
    resp_patch = client.patch(
        "/api/v1/resident/settings",
        json={"dark_mode": True, "language": "kn", "rent_reminders_enabled": False},
        headers=headers,
    )
    assert resp_patch.status_code == 200
    assert resp_patch.json()["data"]["language"] == "kn"
    assert resp_patch.json()["data"]["dark_mode"] is True

    # 3. Invalid Language ('fr') rejected with 422
    resp_bad_lang = client.patch(
        "/api/v1/resident/settings",
        json={"language": "fr"},
        headers=headers,
    )
    assert resp_bad_lang.status_code == 422


def test_resident_logout(client: TestClient, resident_test_context):
    headers = {"Authorization": f"Bearer {resident_test_context['token_a']}"}
    logout_payload = {"refresh_token": resident_test_context["refresh_token_a"]}
    resp = client.post("/api/v1/auth/logout", json=logout_payload, headers=headers)
    assert resp.status_code == 200
    assert resp.json()["success"] is True


# ---------------------------------------------------------------------------
# SECURITY & RBAC GATING TESTS
# ---------------------------------------------------------------------------
def test_security_unauthenticated_request_rejected(client: TestClient):
    resp = client.get("/api/v1/resident/dashboard")
    assert resp.status_code == 401


def test_security_tampered_token_rejected(client: TestClient):
    headers = {"Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.invalid.signature"}
    resp = client.get("/api/v1/resident/dashboard", headers=headers)
    assert resp.status_code == 401


def test_security_non_resident_role_rejected(client: TestClient, resident_test_context):
    headers_admin = {"Authorization": f"Bearer {resident_test_context['token_admin']}"}
    resp = client.get("/api/v1/resident/dashboard", headers=headers_admin)
    assert resp.status_code == 403


def test_security_pending_approval_resident_rejected(client: TestClient, resident_test_context):
    headers_pending = {"Authorization": f"Bearer {resident_test_context['token_c']}"}
    resp = client.get("/api/v1/resident/dashboard", headers=headers_pending)
    assert resp.status_code == 403


def test_security_inactive_resident_rejected(client: TestClient, resident_test_context):
    headers_inactive = {"Authorization": f"Bearer {resident_test_context['token_d']}"}
    resp = client.get("/api/v1/resident/dashboard", headers=headers_inactive)
    assert resp.status_code == 401
