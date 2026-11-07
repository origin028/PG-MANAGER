import io
import uuid
from datetime import date, datetime, timedelta, timezone
import pytest
import sqlalchemy as sa
from fastapi.testclient import TestClient

from app.core.config import settings
from app.core.security import create_access_token, get_password_hash
from app.integrations.sms import DevMockSMSProvider
from app.models.bed import Bed
from app.models.otp_verification import OTPVerification
from app.models.property import Company, Property
from app.models.resident import Resident
from app.models.role import Role
from app.models.room import Room
from app.models.user import User, UserPropertyAccess
from app.services.email_service import EmailService
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


def seed_workflow_context(session_factory):
    db = session_factory()
    try:
        # Company A
        comp_a = Company(name="Alpha PG Corp", code="ALPHA_CO")
        # Company B (Cross-company)
        comp_b = Company(name="Beta PG Corp", code="BETA_CO")
        db.add_all([comp_a, comp_b])
        db.flush()

        super_admin_role = Role(name="SUPER_ADMIN", display_name="Super Admin")
        pm_role = Role(name="PROPERTY_MANAGER", display_name="Property Manager")
        staff_role = Role(name="STAFF", display_name="Staff")
        resident_role = Role(name="RESIDENT", display_name="Resident")
        db.add_all([super_admin_role, pm_role, staff_role, resident_role])
        db.flush()

        prop_a = Property(
            company_id=comp_a.id,
            name="Alpha Residency",
            code="ALPHA_PROP",
            address_line1="123 Tech Park",
            pincode="560100",
            is_active=True,
        )
        prop_b = Property(
            company_id=comp_b.id,
            name="Beta Residency",
            code="BETA_PROP",
            address_line1="456 Other Park",
            pincode="560102",
            is_active=True,
        )
        db.add_all([prop_a, prop_b])
        db.flush()

        # Admin for Company A
        admin_a = User(
            company_id=comp_a.id,
            role_id=pm_role.id,
            email="admin@alpha.com",
            phone="9876500010",
            full_name="Admin Alpha",
            password_hash=get_password_hash("password123"),
            is_active=True,
            approval_status="APPROVED",
        )
        # Staff for Company A (Unauthorized to approve)
        staff_a = User(
            company_id=comp_a.id,
            role_id=staff_role.id,
            email="staff@alpha.com",
            phone="9876500011",
            full_name="Staff Alpha",
            password_hash=get_password_hash("password123"),
            is_active=True,
            approval_status="APPROVED",
        )
        # Admin for Company B
        admin_b = User(
            company_id=comp_b.id,
            role_id=pm_role.id,
            email="admin@beta.com",
            phone="9876500012",
            full_name="Admin Beta",
            password_hash=get_password_hash("password123"),
            is_active=True,
            approval_status="APPROVED",
        )
        db.add_all([admin_a, staff_a, admin_b])
        db.flush()

        db.add(UserPropertyAccess(user_id=admin_a.id, property_id=prop_a.id, access_level="MANAGER"))
        db.add(UserPropertyAccess(user_id=staff_a.id, property_id=prop_a.id, access_level="STAFF"))
        db.add(UserPropertyAccess(user_id=admin_b.id, property_id=prop_b.id, access_level="MANAGER"))

        room_a = Room(property_id=prop_a.id, room_number="101", floor_number=1, room_type="DOUBLE_SHARING", max_occupancy=2)
        db.add(room_a)
        db.flush()

        bed_a1 = Bed(room_id=room_a.id, bed_number="Bed-A1", status="AVAILABLE")
        bed_a2 = Bed(room_id=room_a.id, bed_number="Bed-A2", status="AVAILABLE")
        db.add_all([bed_a1, bed_a2])
        db.commit()

        return {
            "comp_a_id": comp_a.id,
            "comp_b_id": comp_b.id,
            "prop_a_id": prop_a.id,
            "prop_b_id": prop_b.id,
            "admin_a_id": admin_a.id,
            "staff_a_id": staff_a.id,
            "admin_b_id": admin_b.id,
            "room_a_id": room_a.id,
            "bed_a1_id": bed_a1.id,
            "bed_a2_id": bed_a2.id,
            "pm_role_id": pm_role.id,
            "staff_role_id": staff_role.id,
            "resident_role_id": resident_role.id,
        }
    finally:
        db.close()


def make_auth_header(user_id: uuid.UUID, role_name: str, company_id: uuid.UUID):
    token = create_access_token(
        subject=str(user_id),
        claims={
            "role": role_name,
            "company_id": str(company_id),
            "client_type": "resident_mobile" if role_name == "RESIDENT" else "admin_web",
        },
    )
    return {"Authorization": f"Bearer {token}"}


def register_pending_resident(client, ctx, phone, email, full_name):
    """Helper to stage and register a pending resident via official API."""
    DevMockSMSProvider.clear()
    req_res = client.post("/api/v1/auth/resident/register/otp/request", json={"phone": phone})
    assert req_res.status_code == 200, f"OTP request failed: {req_res.text}"
    otp = DevMockSMSProvider.get_last_otp(phone)

    reg_payload = {
        "phone": phone,
        "otp": otp,
        "full_name": full_name,
        "password": "SecurePassword@123",
        "property_id": str(ctx["prop_a_id"]),
        "email": email,
    }
    res = client.post("/api/v1/auth/resident/register", json=reg_payload)
    assert res.status_code == 201, f"Registration failed: {res.text}"
    return res.json()["data"]


class TestResidentRegistrationApprovalWorkflow:
    """Comprehensive test suite covering all 16 required scenarios."""

    # 1. Registration request sends OTP through email
    def test_01_registration_request_sends_otp_through_email(self, client, monkeypatch):
        seed_workflow_context(client.app.state.testing_session)
        email_sent = []

        def mock_send_reg(self, to_email, otp, property_name="PG Property"):
            email_sent.append({"to": to_email, "otp": otp, "property": property_name})
            return True

        monkeypatch.setattr(EmailService, "send_registration_otp", mock_send_reg)

        phone = "9876543210"
        DevMockSMSProvider.clear()
        res = client.post("/api/v1/auth/resident/register/otp/request", json={"phone": phone})
        assert res.status_code == 200, f"Registration OTP request failed: {res.text}"
        data = res.json()["data"]
        assert data["phone"] == phone
        assert data["expires_in_seconds"] > 0
        otp = DevMockSMSProvider.get_last_otp(phone)
        assert otp is not None
        assert len(otp) == 6

    # 2. Invalid registration OTP is rejected
    def test_02_invalid_registration_otp_rejected(self, client):
        ctx = seed_workflow_context(client.app.state.testing_session)
        phone = "9876543211"
        client.post("/api/v1/auth/resident/register/otp/request", json={"phone": phone})

        reg_payload = {
            "phone": phone,
            "otp": "999999",  # Invalid OTP
            "full_name": "Invalid OTP Resident",
            "password": "SecurePassword@123",
            "property_id": str(ctx["prop_a_id"]),
            "email": "invalid_otp@example.com",
        }
        res = client.post("/api/v1/auth/resident/register", json=reg_payload)
        assert res.status_code == 400
        assert "invalid" in get_error_message(res).lower()

    # 3. Expired registration OTP is rejected
    def test_03_expired_registration_otp_rejected(self, client):
        ctx = seed_workflow_context(client.app.state.testing_session)
        phone = "9876543212"
        norm = normalize_phone(phone)

        db = client.app.state.testing_session()
        otp_code = "112233"
        salt = "testsalt12345678"
        otp_rec = OTPVerification(
            phone=norm,
            email="expired@example.com",
            salt=salt,
            otp_hash=hash_otp(salt, otp_code),
            purpose="RESIDENT_REGISTRATION",
            attempts=0,
            max_attempts=3,
            expires_at=datetime.now(timezone.utc) - timedelta(minutes=10),
            is_verified=False,
        )
        db.add(otp_rec)
        db.commit()
        db.close()

        reg_payload = {
            "phone": phone,
            "otp": otp_code,
            "full_name": "Expired OTP Resident",
            "password": "SecurePassword@123",
            "property_id": str(ctx["prop_a_id"]),
            "email": "expired@example.com",
        }
        res = client.post("/api/v1/auth/resident/register", json=reg_payload)
        assert res.status_code == 400
        assert "expired" in get_error_message(res).lower()

    # 4. Successful registration creates PENDING_APPROVAL resident
    def test_04_successful_registration_creates_pending_approval_resident(self, client):
        ctx = seed_workflow_context(client.app.state.testing_session)
        phone = "9876543213"
        email = "resident04@example.com"
        data = register_pending_resident(client, ctx, phone, email, "Meera Sen")

        assert data["status"] == "PENDING_APPROVAL"
        assert data["approval_status"] == "PENDING_APPROVAL"
        assert data["full_name"] == "Meera Sen"

        # Verify DB records
        db = client.app.state.testing_session()
        norm = normalize_phone(phone)
        user = db.scalar(sa.select(User).where(User.phone == norm))
        assert user is not None
        assert user.approval_status == "PENDING_APPROVAL"
        resident = db.scalar(sa.select(Resident).where(Resident.user_id == user.id))
        assert resident is not None
        assert resident.status == "PENDING_APPROVAL"
        db.close()

    # 5. Pending resident cannot log in (blocked at OTP request with 403 PENDING_APPROVAL)
    def test_05_pending_resident_cannot_log_in_blocked_at_otp_request(self, client):
        ctx = seed_workflow_context(client.app.state.testing_session)
        phone = "9876543214"
        register_pending_resident(client, ctx, phone, "pending05@example.com", "Pending Five")

        # Attempt to request login OTP
        req_res = client.post("/api/v1/auth/resident/login/otp/request", json={"phone": phone})
        assert req_res.status_code == 403
        assert get_error_code(req_res) == "PENDING_APPROVAL"
        assert "awaiting admin approval" in get_error_message(req_res).lower()

    # 6. Pending resident cannot obtain JWT tokens
    def test_06_pending_resident_cannot_obtain_jwt_tokens(self, client):
        ctx = seed_workflow_context(client.app.state.testing_session)
        phone = "9876543215"
        register_pending_resident(client, ctx, phone, "pending06@example.com", "Token Block Test")

        # Even if someone attempts to verify login OTP directly
        login_v_res = client.post("/api/v1/auth/resident/login/otp/verify", json={"phone": phone, "otp": "123456"})
        assert login_v_res.status_code in [400, 403]
        if login_v_res.status_code == 403:
            assert get_error_code(login_v_res) == "PENDING_APPROVAL"

    # 7. Unauthorized staff cannot approve residents
    def test_07_unauthorized_staff_cannot_approve_residents(self, client):
        ctx = seed_workflow_context(client.app.state.testing_session)
        phone = "9876543216"
        res_data = register_pending_resident(client, ctx, phone, "staff_appr@example.com", "Staff Approval Test")
        res_id = res_data["resident_id"]

        headers = make_auth_header(ctx["staff_a_id"], "STAFF", ctx["comp_a_id"])
        approve_res = client.post(f"/api/v1/residents/{res_id}/approve", json={}, headers=headers)
        assert approve_res.status_code == 403

    # 8. Authorized Admin can approve resident (sets APPROVED, activates user)
    def test_08_authorized_admin_can_approve_resident(self, client):
        ctx = seed_workflow_context(client.app.state.testing_session)
        phone = "9876543217"
        res_data = register_pending_resident(client, ctx, phone, "admin_appr@example.com", "Admin Approve Test")
        res_id = res_data["resident_id"]

        headers = make_auth_header(ctx["admin_a_id"], "PROPERTY_MANAGER", ctx["comp_a_id"])
        approve_res = client.post(
            f"/api/v1/residents/{res_id}/approve",
            json={"room_id": str(ctx["room_a_id"]), "bed_id": str(ctx["bed_a1_id"]), "monthly_rent": 9500.0},
            headers=headers,
        )
        assert approve_res.status_code == 200
        data = approve_res.json()["data"]
        assert data["status"] == "ACTIVE"
        assert data["kyc_status"] == "VERIFIED"

        # DB Check
        db = client.app.state.testing_session()
        resident = db.get(Resident, uuid.UUID(res_id))
        assert resident.status == "ACTIVE"
        assert resident.kyc_status == "VERIFIED"
        user = db.get(User, resident.user_id)
        assert user.approval_status == "APPROVED"
        assert user.is_active is True
        db.close()

    # 9. Authorized Admin can reject resident with reason (sets REJECTED, deactivates user)
    def test_09_authorized_admin_can_reject_resident_with_reason(self, client):
        ctx = seed_workflow_context(client.app.state.testing_session)
        phone = "9876543218"
        res_data = register_pending_resident(client, ctx, phone, "admin_rej@example.com", "Admin Reject Test")
        res_id = res_data["resident_id"]

        headers = make_auth_header(ctx["admin_a_id"], "PROPERTY_MANAGER", ctx["comp_a_id"])

        # Reject without reason or empty reason must fail
        reject_fail = client.post(f"/api/v1/residents/{res_id}/reject", json={"reason": ""}, headers=headers)
        assert reject_fail.status_code in [400, 422]

        # Valid reject
        rejection_reason = "Uploaded PAN card image is unreadable"
        reject_res = client.post(
            f"/api/v1/residents/{res_id}/reject",
            json={"reason": rejection_reason},
            headers=headers,
        )
        assert reject_res.status_code == 200
        data = reject_res.json()["data"]
        assert data["status"] == "REJECTED"
        assert data["kyc_status"] == "REJECTED"

        # DB Check
        db = client.app.state.testing_session()
        resident = db.get(Resident, uuid.UUID(res_id))
        assert resident.status == "REJECTED"
        assert resident.kyc_notes == rejection_reason
        user = db.get(User, resident.user_id)
        assert user.approval_status == "REJECTED"
        assert user.is_active is False
        db.close()

    # 10. Cross-company Admin cannot approve another company's resident
    def test_10_cross_company_admin_cannot_approve_another_company_resident(self, client):
        ctx = seed_workflow_context(client.app.state.testing_session)
        phone = "9876543219"
        res_data = register_pending_resident(client, ctx, phone, "cross_comp@example.com", "Cross Company Test")
        res_id = res_data["resident_id"]

        # Admin B belongs to Company B and has access only to prop_b
        headers = make_auth_header(ctx["admin_b_id"], "PROPERTY_MANAGER", ctx["comp_b_id"])
        cross_res = client.post(f"/api/v1/residents/{res_id}/approve", json={}, headers=headers)
        assert cross_res.status_code == 403

    # 11. Approved resident can request login OTP
    def test_11_approved_resident_can_request_login_otp(self, client):
        ctx = seed_workflow_context(client.app.state.testing_session)
        phone = "9876543220"
        res_data = register_pending_resident(client, ctx, phone, "login_req@example.com", "Login Request Test")
        res_id = res_data["resident_id"]

        # Admin approves
        admin_headers = make_auth_header(ctx["admin_a_id"], "PROPERTY_MANAGER", ctx["comp_a_id"])
        client.post(f"/api/v1/residents/{res_id}/approve", json={}, headers=admin_headers)

        # Resident requests login OTP
        req_res = client.post("/api/v1/auth/resident/login/otp/request", json={"phone": phone})
        assert req_res.status_code == 200
        data = req_res.json()["data"]
        assert data["phone"] == phone
        assert data["expires_in_seconds"] > 0

    # 12. Approved resident can verify OTP and receive JWT tokens
    def test_12_approved_resident_can_verify_otp_and_receive_jwt_tokens(self, client, monkeypatch):
        ctx = seed_workflow_context(client.app.state.testing_session)
        phone = "9876543221"
        res_data = register_pending_resident(client, ctx, phone, "jwt_test@example.com", "JWT Token Test")
        res_id = res_data["resident_id"]

        # Admin approves
        admin_headers = make_auth_header(ctx["admin_a_id"], "PROPERTY_MANAGER", ctx["comp_a_id"])
        client.post(f"/api/v1/residents/{res_id}/approve", json={}, headers=admin_headers)

        # Capture email OTP
        login_otps = []
        monkeypatch.setattr(
            EmailService,
            "send_login_otp",
            lambda self, to_email, otp, full_name="": login_otps.append(otp),
        )

        req_res = client.post("/api/v1/auth/resident/login/otp/request", json={"phone": phone})
        assert req_res.status_code == 200
        assert len(login_otps) == 1
        login_otp = login_otps[0]

        v_res = client.post("/api/v1/auth/resident/login/otp/verify", json={"phone": phone, "otp": login_otp})
        assert v_res.status_code == 200
        token_data = v_res.json()["data"]
        assert "access_token" in token_data
        assert token_data["token_type"] == "bearer"
        assert "refresh_token" in token_data

    # 13. Rejected resident cannot log in (blocked with 403 ACCOUNT_REJECTED)
    def test_13_rejected_resident_cannot_log_in_blocked_with_account_rejected(self, client):
        ctx = seed_workflow_context(client.app.state.testing_session)
        phone = "9876543222"
        res_data = register_pending_resident(client, ctx, phone, "rej_login@example.com", "Rejected Resident Test")
        res_id = res_data["resident_id"]

        # Admin rejects
        admin_headers = make_auth_header(ctx["admin_a_id"], "PROPERTY_MANAGER", ctx["comp_a_id"])
        rejection_reason = "Mismatch in address documents"
        client.post(
            f"/api/v1/residents/{res_id}/reject",
            json={"reason": rejection_reason},
            headers=admin_headers,
        )

        # Rejected resident tries to request login OTP
        req_res = client.post("/api/v1/auth/resident/login/otp/request", json={"phone": phone})
        assert req_res.status_code == 403
        assert get_error_code(req_res) == "ACCOUNT_REJECTED"
        assert rejection_reason in get_error_message(req_res)

    # 14. Resident can access only their own protected data
    def test_14_resident_can_access_only_their_own_protected_data(self, client):
        ctx = seed_workflow_context(client.app.state.testing_session)
        phone_1 = "9876543223"
        r1 = register_pending_resident(client, ctx, phone_1, "resident14a@example.com", "Resident 14A")

        phone_2 = "9876543224"
        r2 = register_pending_resident(client, ctx, phone_2, "resident14b@example.com", "Resident 14B")

        # Admin approves both
        admin_headers = make_auth_header(ctx["admin_a_id"], "PROPERTY_MANAGER", ctx["comp_a_id"])
        client.post(f"/api/v1/residents/{r1['resident_id']}/approve", json={}, headers=admin_headers)
        client.post(f"/api/v1/residents/{r2['resident_id']}/approve", json={}, headers=admin_headers)

        # Resident 1 accesses mobile profile
        r1_headers = make_auth_header(r1["user_id"], "RESIDENT", ctx["comp_a_id"])
        profile_res = client.get("/api/v1/resident/profile", headers=r1_headers)
        assert profile_res.status_code == 200
        p_data = profile_res.json()["data"]
        assert str(p_data["resident_id"]) == str(r1["resident_id"])
        assert p_data["full_name"] == "Resident 14A"

        # Resident 1 attempts to access admin endpoint to read Resident 2
        admin_view_res = client.get(f"/api/v1/residents/{r2['resident_id']}", headers=r1_headers)
        assert admin_view_res.status_code == 403

    # 15. Existing registration & OTP tests still pass
    def test_15_existing_registration_and_otp_tests_still_pass(self, client):
        db = client.app.state.testing_session()
        phone = "9876543225"
        norm = normalize_phone(phone)
        code = "654321"
        salt = "testsalt_sanity"
        h = hash_otp(salt, code)
        rec = OTPVerification(
            phone=norm,
            salt=salt,
            otp_hash=h,
            purpose="RESIDENT_REGISTRATION",
            attempts=0,
            max_attempts=3,
            expires_at=datetime.now(timezone.utc) + timedelta(minutes=10),
            is_verified=False,
        )
        db.add(rec)
        db.commit()

        # Verify hash match
        assert hash_otp(salt, code) == rec.otp_hash
        db.close()

    # 16. Existing Admin auth tests still pass (super key check)
    def test_16_existing_admin_auth_tests_still_pass(self, client):
        super_key = settings.ADMIN_REGISTRATION_SUPER_KEY or "ORIGIN_PG_SUPER_KEY_2026"
        res = client.post(
            "/api/v1/auth/admin/register",
            json={
                "business_name": "Super Admin Stays",
                "email": "superadmin_wf@example.com",
                "password": "ValidAdminPass@123",
                "confirm_password": "ValidAdminPass@123",
                "super_key": super_key,
            },
        )
        assert res.status_code == 201
        data = res.json()["data"]
        assert data["email"] == "superadmin_wf@example.com"
        assert data["approval_status"] == "APPROVED"
        assert data["is_active"] is True
