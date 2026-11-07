import io
import os
from pathlib import Path
import uuid
from datetime import date, datetime, timedelta, timezone
from unittest.mock import patch
import pytest
import sqlalchemy as sa
from fastapi.testclient import TestClient

from app.core.config import settings
from app.core.security import create_access_token, get_password_hash
from app.models.bed import Bed
from app.models.otp_verification import OTPVerification
from app.models.pending_registration import PendingResidentRegistration
from app.models.property import Company, Property
from app.models.resident import Resident
from app.models.role import Role
from app.models.room import Room
from app.models.user import User, UserPropertyAccess
from app.services.email_service import EmailService
from app.services.notification_service import NotificationService
from app.services.otp_service import OTPService, hash_otp, normalize_phone


def get_error_code(res):
    data = res.json()
    if "error" in data and isinstance(data["error"], dict):
        return data["error"].get("code", "")
    return ""


def get_error_message(res):
    data = res.json()
    if "error" in data and isinstance(data["error"], dict):
        return data["error"].get("message", "")
    return str(data.get("detail", ""))


@pytest.fixture
def security_test_env(client):
    """
    Sets up multi-tenant environment for security audit tests:
    - Company A (Alpha PG Corp) with Property A, Admin A (PROPERTY_MANAGER), Staff A (STAFF)
    - Company B (Beta PG Corp) with Property B, Admin B (PROPERTY_MANAGER)
    - Super Admin for Company A
    - Pending Resident and Approved Resident in Company A
    - Dummy KYC file on disk in backend/uploads/kyc
    """
    from app.dependencies import get_db
    from app.main import app

    override = app.dependency_overrides.get(get_db)
    gen = override()
    db = next(gen)

    try:
        # Create companies
        comp_a = Company(name="Alpha Security Corp", code="ALPHA_SEC")
        comp_b = Company(name="Beta Security Corp", code="BETA_SEC")
        db.add_all([comp_a, comp_b])
        db.flush()

        # Roles
        super_admin_role = Role(name="SUPER_ADMIN", display_name="Super Admin")
        pm_role = Role(name="PROPERTY_MANAGER", display_name="Property Manager")
        staff_role = Role(name="STAFF", display_name="Staff")
        resident_role = Role(name="RESIDENT", display_name="Resident")
        db.add_all([super_admin_role, pm_role, staff_role, resident_role])
        db.flush()

        # Properties
        prop_a = Property(
            company_id=comp_a.id,
            name="Alpha Heights",
            code="ALPHA_HGT",
            address_line1="100 Security Way",
            pincode="560100",
            is_active=True,
        )
        prop_b = Property(
            company_id=comp_b.id,
            name="Beta Heights",
            code="BETA_HGT",
            address_line1="200 External Way",
            pincode="560101",
            is_active=True,
        )
        db.add_all([prop_a, prop_b])
        db.flush()

        # Super Admin A
        super_admin_a = User(
            company_id=comp_a.id,
            role_id=super_admin_role.id,
            email="superadmin@alpha.com",
            phone="9876500001",
            full_name="Super Admin Alpha",
            password_hash=get_password_hash("password123"),
            is_active=True,
            approval_status="APPROVED",
        )
        # Property Manager A
        admin_a = User(
            company_id=comp_a.id,
            role_id=pm_role.id,
            email="manager@alpha.com",
            phone="9876500002",
            full_name="Manager Alpha",
            password_hash=get_password_hash("password123"),
            is_active=True,
            approval_status="APPROVED",
        )
        # Staff A
        staff_a = User(
            company_id=comp_a.id,
            role_id=staff_role.id,
            email="staff@alpha.com",
            phone="9876500003",
            full_name="Staff Alpha",
            password_hash=get_password_hash("password123"),
            is_active=True,
            approval_status="APPROVED",
        )
        # Property Manager B (Cross-Company)
        admin_b = User(
            company_id=comp_b.id,
            role_id=pm_role.id,
            email="manager@beta.com",
            phone="9876500004",
            full_name="Manager Beta",
            password_hash=get_password_hash("password123"),
            is_active=True,
            approval_status="APPROVED",
        )
        db.add_all([super_admin_a, admin_a, staff_a, admin_b])
        db.flush()

        db.add(UserPropertyAccess(user_id=admin_a.id, property_id=prop_a.id, access_level="MANAGER"))
        db.add(UserPropertyAccess(user_id=staff_a.id, property_id=prop_a.id, access_level="STAFF"))
        db.add(UserPropertyAccess(user_id=admin_b.id, property_id=prop_b.id, access_level="MANAGER"))

        # Create physical dummy KYC file in uploads/kyc
        backend_root = Path(__file__).resolve().parent.parent
        kyc_dir = backend_root / "uploads" / "kyc"
        kyc_dir.mkdir(parents=True, exist_ok=True)
        dummy_filename = f"test_sec_{uuid.uuid4().hex}_aadhaar_front.jpg"
        dummy_file_path = kyc_dir / dummy_filename
        dummy_file_path.write_bytes(b"\xFF\xD8\xFF\xE0\x00\x10JFIF\x00\x01\x01\x01\x00`\x00`\x00\x00\xFF\xDB\x00C\x00" + b"TEST_IMAGE_DATA")

        # Resident User & Profile in Company A
        res_user_a = User(
            company_id=comp_a.id,
            role_id=resident_role.id,
            email="resident.a@alpha.com",
            phone="9876500005",
            full_name="Resident Alpha",
            password_hash="!NO_PASSWORD",
            is_active=True,
            approval_status="APPROVED",
        )
        db.add(res_user_a)
        db.flush()

        resident_a = Resident(
            user_id=res_user_a.id,
            property_id=prop_a.id,
            date_of_birth=date(2000, 1, 1),
            gender="Male",
            occupation="Software Engineer",
            emergency_contact="Father - 9876500099",
            house_flat_no="101",
            street="Main Street",
            city="Bengaluru",
            state="Karnataka",
            pincode="560100",
            verification_method="Aadhaar + PAN",
            aadhaar_front_path=f"uploads/kyc/{dummy_filename}",
            aadhaar_back_path=f"uploads/kyc/{dummy_filename}",
            pan_card_path=f"uploads/kyc/{dummy_filename}",
            resident_selfie_path=f"uploads/kyc/{dummy_filename}",
            check_in_date=date.today(),
            monthly_rent=8500.0,
            security_deposit=17000.0,
            status="ACTIVE",
            kyc_status="VERIFIED",
        )
        db.add(resident_a)

        # Rooms & Beds for Property A
        room_a = Room(property_id=prop_a.id, room_number="R101", floor_number=1, room_type="DOUBLE_SHARING", max_occupancy=2)
        db.add(room_a)
        db.flush()
        bed_a = Bed(room_id=room_a.id, bed_number="B1", status="AVAILABLE")
        db.add(bed_a)

        db.commit()

        # Generate tokens
        super_admin_token = create_access_token(
            subject=str(super_admin_a.id),
            claims={"role": "SUPER_ADMIN", "company_id": str(comp_a.id), "allowed_properties": ["*"]}
        )
        admin_a_token = create_access_token(
            subject=str(admin_a.id),
            claims={"role": "PROPERTY_MANAGER", "company_id": str(comp_a.id), "allowed_properties": [str(prop_a.id)]}
        )
        staff_a_token = create_access_token(
            subject=str(staff_a.id),
            claims={"role": "STAFF", "company_id": str(comp_a.id), "allowed_properties": [str(prop_a.id)]}
        )
        admin_b_token = create_access_token(
            subject=str(admin_b.id),
            claims={"role": "PROPERTY_MANAGER", "company_id": str(comp_b.id), "allowed_properties": [str(prop_b.id)]}
        )
        resident_a_token = create_access_token(
            subject=str(res_user_a.id),
            claims={"role": "RESIDENT", "company_id": str(comp_a.id), "allowed_properties": [str(prop_a.id)], "client_type": "resident_mobile"}
        )

        yield {
            "db": db,
            "comp_a": comp_a,
            "comp_b": comp_b,
            "prop_a": prop_a,
            "prop_b": prop_b,
            "room_a": room_a,
            "bed_a": bed_a,
            "resident_a": resident_a,
            "res_user_a": res_user_a,
            "super_admin_token": super_admin_token,
            "admin_a_token": admin_a_token,
            "staff_a_token": staff_a_token,
            "admin_b_token": admin_b_token,
            "resident_a_token": resident_a_token,
            "dummy_file_path": dummy_file_path,
            "dummy_filename": dummy_filename,
        }
    finally:
        # Cleanup dummy file
        if dummy_file_path.exists():
            try:
                dummy_file_path.unlink()
            except Exception:
                pass
        try:
            next(gen)
        except StopIteration:
            pass


# =============================================================================
# 1. PUBLIC KYC URL ACCESS BLOCKED
# =============================================================================

def test_public_kyc_url_access_blocked(client, security_test_env):
    """
    Verifies that public access to files in /uploads/kyc/... is blocked.
    The unauthenticated StaticFiles mount on /uploads has been removed.
    Direct GET requests without auth must return 404 (or 403).
    """
    filename = security_test_env["dummy_filename"]
    res = client.get(f"/uploads/kyc/{filename}")
    assert res.status_code in (404, 403), f"Public access was not blocked! Status: {res.status_code}"


# =============================================================================
# 2. UNAUTHORIZED KYC ACCESS (ANONYMOUS, STAFF, RESIDENT)
# =============================================================================

def test_unauthorized_kyc_access_anonymous(client, security_test_env):
    """Verifies that an unauthenticated user cannot access resident KYC documents."""
    res_id = security_test_env["resident_a"].id
    res = client.get(f"/api/v1/residents/{res_id}/kyc-document/aadhaar_front")
    assert res.status_code == 401, f"Expected 401 Unauthorized, got: {res.status_code}"


def test_unauthorized_kyc_access_staff_role_blocked(client, security_test_env):
    """
    Verifies that STAFF role is strictly forbidden from accessing KYC documents.
    Only SUPER_ADMIN and PROPERTY_MANAGER are permitted.
    """
    res_id = security_test_env["resident_a"].id
    headers = {"Authorization": f"Bearer {security_test_env['staff_a_token']}"}
    res = client.get(f"/api/v1/residents/{res_id}/kyc-document/aadhaar_front", headers=headers)
    assert res.status_code == 403, f"Expected 403 Forbidden for STAFF, got: {res.status_code}"
    assert "STAFF" in get_error_message(res) or "forbidden" in get_error_message(res).lower() or res.status_code == 403


def test_unauthorized_kyc_access_resident_role_blocked(client, security_test_env):
    """
    Verifies that RESIDENT role is strictly forbidden from accessing KYC document endpoints.
    """
    res_id = security_test_env["resident_a"].id
    headers = {"Authorization": f"Bearer {security_test_env['resident_a_token']}"}
    res = client.get(f"/api/v1/residents/{res_id}/kyc-document/aadhaar_front", headers=headers)
    assert res.status_code == 403, f"Expected 403 Forbidden for RESIDENT, got: {res.status_code}"


# =============================================================================
# 3. CROSS-COMPANY KYC ACCESS BLOCKED
# =============================================================================

def test_cross_company_kyc_access_blocked(client, security_test_env):
    """
    Verifies that an Admin/Property Manager of Company B cannot access KYC documents
    of a resident belonging to Company A.
    """
    res_id = security_test_env["resident_a"].id
    # admin_b belongs to Beta Corp, while resident_a belongs to Alpha Corp
    headers = {"Authorization": f"Bearer {security_test_env['admin_b_token']}"}
    res = client.get(f"/api/v1/residents/{res_id}/kyc-document/aadhaar_front", headers=headers)
    assert res.status_code == 403, f"Expected 403 Forbidden for Cross-Company access, got: {res.status_code}"


# =============================================================================
# 4. AUTHORIZED KYC ACCESS & PRIVACY HEADERS
# =============================================================================

def test_authorized_kyc_access_by_property_manager(client, security_test_env):
    """
    Verifies that an authorized PROPERTY_MANAGER belonging to the resident's property
    can preview/download the KYC document with strict anti-caching privacy headers.
    """
    res_id = security_test_env["resident_a"].id
    headers = {"Authorization": f"Bearer {security_test_env['admin_a_token']}"}
    res = client.get(f"/api/v1/residents/{res_id}/kyc-document/aadhaar_front", headers=headers)
    assert res.status_code == 200, f"Expected 200 OK, got: {res.status_code}: {res.text}"
    assert "image/jpeg" in res.headers.get("content-type", "")
    assert "no-store" in res.headers.get("cache-control", "")
    assert res.headers.get("x-content-type-options") == "nosniff"


def test_authorized_kyc_access_by_super_admin(client, security_test_env):
    """
    Verifies that SUPER_ADMIN of the resident's company can access KYC documents.
    """
    res_id = security_test_env["resident_a"].id
    headers = {"Authorization": f"Bearer {security_test_env['super_admin_token']}"}
    res = client.get(f"/api/v1/residents/{res_id}/kyc-document/pan_card", headers=headers)
    assert res.status_code == 200, f"Expected 200 OK, got: {res.status_code}"


# =============================================================================
# 5. NO PRIVATE PATH EXPOSURE IN PUBLIC API RESPONSES
# =============================================================================

def test_pending_approvals_does_not_expose_raw_disk_paths(client, security_test_env):
    """
    Verifies that GET /api/v1/residents/pending-approvals does NOT expose raw disk paths
    (e.g., uploads/kyc/...). Instead, it exposes secure authenticated API endpoints.
    """
    db = security_test_env["db"]
    prop_a = security_test_env["prop_a"]
    comp_a = security_test_env["comp_a"]
    role = db.scalar(sa.select(Role).where(Role.name == "RESIDENT"))

    # Create pending resident
    user_pend = User(
        company_id=comp_a.id,
        role_id=role.id,
        email="pending.kyc@alpha.com",
        phone="9876500055",
        full_name="Pending Resident",
        password_hash="!NO_PASSWORD",
        is_active=True,
        approval_status="PENDING_APPROVAL",
    )
    db.add(user_pend)
    db.flush()

    res_pend = Resident(
        user_id=user_pend.id,
        property_id=prop_a.id,
        date_of_birth=date(1999, 5, 5),
        gender="Female",
        occupation="Designer",
        emergency_contact="Mother - 9876500098",
        house_flat_no="12",
        street="Oak Street",
        city="Bengaluru",
        state="Karnataka",
        pincode="560100",
        verification_method="Aadhaar + PAN",
        aadhaar_front_path=f"uploads/kyc/{security_test_env['dummy_filename']}",
        aadhaar_back_path=f"uploads/kyc/{security_test_env['dummy_filename']}",
        pan_card_path=f"uploads/kyc/{security_test_env['dummy_filename']}",
        resident_selfie_path=f"uploads/kyc/{security_test_env['dummy_filename']}",
        check_in_date=date.today(),
        status="PENDING_APPROVAL",
        kyc_status="PENDING",
    )
    db.add(res_pend)
    db.commit()

    headers = {"Authorization": f"Bearer {security_test_env['admin_a_token']}"}
    res = client.get("/api/v1/residents/pending-approvals", headers=headers)
    assert res.status_code == 200
    items = res.json()["data"]["items"]
    target = next((i for i in items if i["email"] == "pending.kyc@alpha.com"), None)
    assert target is not None

    # Crucial security assertion: No raw disk paths exposed!
    assert "uploads/kyc" not in (target.get("aadhaar_front_path") or "")
    assert target.get("aadhaar_front_path").startswith(f"/api/v1/residents/{res_pend.id}/kyc-document/aadhaar_front")


# =============================================================================
# 6. NOTIFICATION FAILURE DOES NOT ROLL BACK APPROVAL
# =============================================================================

def test_notification_failure_does_not_rollback_approval(client, security_test_env):
    """
    Verifies that when an admin approves a resident registration, failure of
    in-app notification or email delivery does NOT abort or roll back the approval transaction.
    The resident account is still approved and room/bed allocated.
    """
    db = security_test_env["db"]
    prop_a = security_test_env["prop_a"]
    comp_a = security_test_env["comp_a"]
    role = db.scalar(sa.select(Role).where(Role.name == "RESIDENT"))

    pend_user = User(
        company_id=comp_a.id,
        role_id=role.id,
        email="notify.fail@alpha.com",
        phone="9876500066",
        full_name="Notify Fail Resident",
        password_hash="!NO_PASSWORD",
        is_active=True,
        approval_status="PENDING_APPROVAL",
    )
    db.add(pend_user)
    db.flush()

    pend_res = Resident(
        user_id=pend_user.id,
        property_id=prop_a.id,
        date_of_birth=date(1998, 3, 3),
        gender="Male",
        occupation="Engineer",
        emergency_contact="Guardian - 9876500097",
        house_flat_no="50B",
        street="Cedar Ave",
        city="Bengaluru",
        state="Karnataka",
        pincode="560100",
        verification_method="Passport Only",
        passport_path=f"uploads/kyc/{security_test_env['dummy_filename']}",
        resident_selfie_path=f"uploads/kyc/{security_test_env['dummy_filename']}",
        check_in_date=date.today(),
        status="PENDING_APPROVAL",
        kyc_status="PENDING",
    )
    db.add(pend_res)
    db.commit()

    headers = {"Authorization": f"Bearer {security_test_env['admin_a_token']}"}
    room_id = security_test_env["room_a"].id
    bed_id = security_test_env["bed_a"].id

    payload = {
        "room_id": str(room_id),
        "bed_id": str(bed_id),
        "monthly_rent": 9500.0,
        "security_deposit": 19000.0,
    }

    # Simulate catastrophic failure in both NotificationService and EmailService
    with patch.object(NotificationService, "dispatch", side_effect=RuntimeError("Push broker failure")):
        with patch.object(EmailService, "send_resident_approval_notification", side_effect=RuntimeError("SMTP down")):
            res = client.post(f"/api/v1/residents/{pend_res.id}/approve", json=payload, headers=headers)

    assert res.status_code == 200, f"Approval should succeed even if notifications fail! Got {res.status_code}: {res.text}"

    # Verify resident is approved and activated in DB
    db.refresh(pend_res)
    db.refresh(pend_user)
    assert pend_res.status == "ACTIVE"
    assert pend_res.kyc_status == "VERIFIED"
    assert pend_user.approval_status == "APPROVED"
    assert pend_res.room_id == room_id
    assert pend_res.bed_id == bed_id


# =============================================================================
# 7. DUPLICATE REGISTRATION / OTP VERIFICATION PREVENTED
# =============================================================================

def test_duplicate_registration_otp_verification_prevented(client, security_test_env):
    """
    Verifies that calling /resident/register/otp/verify with the same OTP or after
    already completing registration is strictly rejected and prevents duplicate accounts.
    """
    db = security_test_env["db"]
    phone = "9876500077"
    email = "duplicate.test@example.com"
    otp = "654321"

    # Stage a pending registration
    reg_data = {
        "full_name": "Duplicate Tester",
        "date_of_birth": "1997-07-07",
        "gender": "Male",
        "occupation": "Analyst",
        "primary_phone": phone,
        "email": email,
        "emergency_contact": "Brother - 9876500096",
        "house_flat_no": "202",
        "street": "Pine Lane",
        "city": "Bengaluru",
        "state": "Karnataka",
        "pincode": "560100",
        "property_id": str(security_test_env["prop_a"].id),
        "verification_method": "Passport Only",
        "passport_path": f"uploads/kyc/{security_test_env['dummy_filename']}",
        "resident_selfie_path": f"uploads/kyc/{security_test_env['dummy_filename']}",
    }

    pending = PendingResidentRegistration(
        phone=phone,
        email=email,
        registration_data=reg_data,
        expires_at=datetime.now(timezone.utc) + timedelta(minutes=30),
    )
    db.add(pending)

    # Insert active OTP
    salt = "testsalt12345678"
    record = OTPVerification(
        phone=phone,
        email=email,
        salt=salt,
        otp_hash=hash_otp(salt, otp),
        purpose="RESIDENT_REGISTRATION",
        attempts=0,
        max_attempts=3,
        is_verified=False,
        expires_at=datetime.now(timezone.utc) + timedelta(minutes=10),
    )
    db.add(record)
    db.commit()

    # First verification must succeed (201 Created)
    res1 = client.post("/api/v1/auth/resident/register/otp/verify", json={"phone": phone, "otp": otp})
    assert res1.status_code == 201, f"First verification failed: {res1.text}"

    # Second verification must fail because OTP is consumed and staged record deleted
    res2 = client.post("/api/v1/auth/resident/register/otp/verify", json={"phone": phone, "otp": otp})
    assert res2.status_code in (400, 409), f"Duplicate verification should fail! Status: {res2.status_code}"


# =============================================================================
# 8. PREVIOUSLY ISSUED JWT BLOCKED AFTER ACCOUNT REJECTION
# =============================================================================

def test_previously_issued_jwt_blocked_after_rejection(client, security_test_env):
    """
    Verifies that if a resident has a valid JWT, and their account is subsequently
    rejected or deactivated by an administrator, that JWT is immediately rejected
    by get_current_user on subsequent API requests.
    """
    db = security_test_env["db"]
    res_user = security_test_env["res_user_a"]
    resident = security_test_env["resident_a"]
    token = security_test_env["resident_a_token"]

    headers = {"Authorization": f"Bearer {token}"}

    # Step 1: Active resident can access their profile
    res_before = client.get("/api/v1/residents/me", headers=headers)
    assert res_before.status_code == 200, f"Active resident should have access, got {res_before.status_code}"

    # Step 2: Administrator rejects the resident
    res_user.approval_status = "REJECTED"
    res_user.is_active = False
    resident.status = "REJECTED"
    resident.kyc_status = "REJECTED"
    db.commit()

    # Step 3: Previously issued JWT must now be rejected
    res_after = client.get("/api/v1/residents/me", headers=headers)
    assert res_after.status_code in (401, 403), f"Rejected resident JWT should be blocked! Status: {res_after.status_code}"
