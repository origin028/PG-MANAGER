import uuid
from datetime import date, datetime, timedelta, timezone
from unittest.mock import MagicMock, patch
import pytest
from fastapi.testclient import TestClient
import sqlalchemy as sa

from app.core.security import create_access_token, get_password_hash
from app.integrations.email import DevMockEmailProvider, mask_email
from app.models.audit_log import AuditLog
from app.models.pending_registration import PendingResidentRegistration
from app.models.property import Company, Property
from app.models.resident import Resident
from app.models.role import Role
from app.models.user import User


@pytest.fixture(autouse=True)
def setup_email_mock():
    DevMockEmailProvider.clear()
    yield
    DevMockEmailProvider.clear()


@pytest.fixture
def seed_test_context(client: TestClient):
    """Seeds Company, Roles, Properties, Super Admin, PM, and Residents in test database."""
    session_factory = client.app.state.testing_session
    db = session_factory()
    try:
        # Company A
        company_a = Company(name="Smart Group Stays A", code="SMART_CO_A")
        # Company B (for tenant isolation test)
        company_b = Company(name="Other Stays B", code="OTHER_CO_B")
        db.add_all([company_a, company_b])
        db.flush()

        super_admin_role = Role(name="SUPER_ADMIN", display_name="Super Admin")
        pm_role = Role(name="PROPERTY_MANAGER", display_name="Property Manager")
        resident_role = Role(name="RESIDENT", display_name="Resident")
        db.add_all([super_admin_role, pm_role, resident_role])
        db.flush()

        prop_a = Property(
            company_id=company_a.id,
            name="Smart PG Koramangala",
            code="SMART_KORA",
            address_line1="100 80ft Road",
            pincode="560034",
            is_active=True,
        )
        db.add(prop_a)
        db.flush()

        # 1. Super Admin (Company A)
        super_admin = User(
            company_id=company_a.id,
            role_id=super_admin_role.id,
            email="superadmin@smartgrouppg.com",
            phone="9800000001",
            full_name="Chief Administrator",
            password_hash=get_password_hash("AdminPass123!"),
            is_active=True,
            is_verified=True,
            approval_status="APPROVED",
        )

        # 2. Property Manager (Company A)
        pm_user = User(
            company_id=company_a.id,
            role_id=pm_role.id,
            email="manager@smartgrouppg.com",
            phone="9800000002",
            full_name="Property Manager Bob",
            password_hash=get_password_hash("ManagerPass123!"),
            is_active=True,
            is_verified=True,
            approval_status="APPROVED",
        )

        # 3. Target Resident (Company A)
        resident_user = User(
            company_id=company_a.id,
            role_id=resident_role.id,
            email="resident_old@originpg.com",
            phone="9867634364",
            full_name="Demo Test Resident",
            password_hash="!RESIDENT_NO_PASSWORD_demo",
            is_active=True,
            is_verified=True,
            approval_status="APPROVED",
        )

        # 4. Another User (Company A - for duplicate collision tests)
        other_user = User(
            company_id=company_a.id,
            role_id=resident_role.id,
            email="existing_occupied@example.com",
            phone="9800000004",
            full_name="Existing Occupant",
            password_hash="!RESIDENT_NO_PASSWORD_other",
            is_active=True,
            is_verified=True,
            approval_status="APPROVED",
        )

        # 5. User from Company B (for tenant isolation test)
        foreign_user = User(
            company_id=company_b.id,
            role_id=resident_role.id,
            email="foreign.resident@other.com",
            phone="9800000005",
            full_name="Foreign Resident",
            password_hash="!RESIDENT_NO_PASSWORD_foreign",
            is_active=True,
            is_verified=True,
            approval_status="APPROVED",
        )

        db.add_all([super_admin, pm_user, resident_user, other_user, foreign_user])
        db.flush()

        # Add Resident profile for resident_user
        res_profile = Resident(
            user_id=resident_user.id,
            property_id=prop_a.id,
            check_in_date=date.today(),
            status="ACTIVE",
            kyc_status="VERIFIED",
        )
        db.add(res_profile)
        db.commit()

        # Create JWT access tokens
        admin_token = create_access_token(str(super_admin.id), {"role": "SUPER_ADMIN"})
        pm_token = create_access_token(str(pm_user.id), {"role": "PROPERTY_MANAGER"})
        resident_token = create_access_token(str(resident_user.id), {"role": "RESIDENT"})

        return {
            "super_admin_id": super_admin.id,
            "super_admin_email": super_admin.email,
            "pm_user_id": pm_user.id,
            "resident_id": resident_user.id,
            "resident_email": resident_user.email,
            "resident_phone": resident_user.phone,
            "resident_full_name": resident_user.full_name,
            "other_user_id": other_user.id,
            "other_user_email": other_user.email,
            "foreign_user_id": foreign_user.id,
            "property_id": prop_a.id,
            "admin_token": admin_token,
            "pm_token": pm_token,
            "resident_token": resident_token,
        }
    finally:
        db.close()


# =============================================================================
# 1. Authorization Tests
# =============================================================================

def test_unauthenticated_request_rejected(client: TestClient, seed_test_context):
    """Unauthenticated request without Bearer token must return 401."""
    resident_id = seed_test_context["resident_id"]
    resp = client.patch(
        f"/api/v1/users/{resident_id}/email",
        json={"new_email": "new.email@example.com"},
    )
    assert resp.status_code == 401
    assert "Authorization" in resp.text or "token" in resp.text.lower()


def test_resident_role_cannot_update_email(client: TestClient, seed_test_context):
    """Residents cannot access admin email update endpoint (403 Forbidden)."""
    resident_id = seed_test_context["resident_id"]
    headers = {"Authorization": f"Bearer {seed_test_context['resident_token']}"}
    resp = client.patch(
        f"/api/v1/users/{resident_id}/email",
        json={"new_email": "rogue.email@example.com"},
        headers=headers,
    )
    assert resp.status_code == 403
    assert "not authorized" in resp.text.lower()


def test_property_manager_cannot_update_email(client: TestClient, seed_test_context):
    """Property Managers cannot access Super Admin endpoint (403 Forbidden)."""
    resident_id = seed_test_context["resident_id"]
    headers = {"Authorization": f"Bearer {seed_test_context['pm_token']}"}
    resp = client.patch(
        f"/api/v1/users/{resident_id}/email",
        json={"new_email": "pm.attempt@example.com"},
        headers=headers,
    )
    assert resp.status_code == 403
    assert "not authorized" in resp.text.lower()


def test_super_admin_from_different_company_blocked(client: TestClient, seed_test_context):
    """Super Admin cannot update a user belonging to a different company (tenant boundary)."""
    foreign_user_id = seed_test_context["foreign_user_id"]
    headers = {"Authorization": f"Bearer {seed_test_context['admin_token']}"}
    resp = client.patch(
        f"/api/v1/users/{foreign_user_id}/email",
        json={"new_email": "hacked@example.com"},
        headers=headers,
    )
    assert resp.status_code == 403
    assert "outside your company" in resp.text.lower()


# =============================================================================
# 2. Validation & Duplicate Checking Tests
# =============================================================================

def test_invalid_email_format_rejected(client: TestClient, seed_test_context):
    """Submitting malformed email returns 422 Unprocessable Content."""
    resident_id = seed_test_context["resident_id"]
    headers = {"Authorization": f"Bearer {seed_test_context['admin_token']}"}

    for bad_email in ["notanemail", "missing-at.com", "@nodomain", "spaces in@email.com"]:
        resp = client.patch(
            f"/api/v1/users/{resident_id}/email",
            json={"new_email": bad_email},
            headers=headers,
        )
        assert resp.status_code == 422


def test_empty_request_body_rejected(client: TestClient, seed_test_context):
    """Empty JSON or missing email field returns 422."""
    resident_id = seed_test_context["resident_id"]
    headers = {"Authorization": f"Bearer {seed_test_context['admin_token']}"}
    resp = client.patch(
        f"/api/v1/users/{resident_id}/email",
        json={},
        headers=headers,
    )
    assert resp.status_code == 422


def test_identical_email_rejected(client: TestClient, seed_test_context):
    """Submitting the user's current email returns 400 Bad Request."""
    resident_id = seed_test_context["resident_id"]
    current_email = seed_test_context["resident_email"]
    headers = {"Authorization": f"Bearer {seed_test_context['admin_token']}"}
    resp = client.patch(
        f"/api/v1/users/{resident_id}/email",
        json={"new_email": current_email},
        headers=headers,
    )
    assert resp.status_code == 400
    assert "already has email address" in resp.text


def test_duplicate_email_in_use_rejected(client: TestClient, seed_test_context):
    """Submitting an email already used by another user returns 409 Conflict."""
    resident_id = seed_test_context["resident_id"]
    other_email = seed_test_context["other_user_email"]
    headers = {"Authorization": f"Bearer {seed_test_context['admin_token']}"}

    resp = client.patch(
        f"/api/v1/users/{resident_id}/email",
        json={"new_email": other_email.upper()},  # Test case-insensitivity
        headers=headers,
    )
    assert resp.status_code == 409
    assert "already in use" in resp.text.lower()


def test_nonexistent_user_id_returns_404(client: TestClient, seed_test_context):
    """Non-existent user UUID returns 404 Not Found."""
    random_id = uuid.uuid4()
    headers = {"Authorization": f"Bearer {seed_test_context['admin_token']}"}
    resp = client.patch(
        f"/api/v1/users/{random_id}/email",
        json={"new_email": "ghost@example.com"},
        headers=headers,
    )
    assert resp.status_code == 404
    assert "not found" in resp.text.lower()


# =============================================================================
# 3. Successful Update & Audit Log Verification
# =============================================================================

def test_successful_email_update_and_audit_log(client: TestClient, seed_test_context):
    """
    Verifies that Super Admin can update the resident's email:
    1. Returns 200 OK with UserEmailUpdateResponse.
    2. Email is normalized and updated in database.
    3. An immutable AuditLog entry is recorded with actor admin and old/new email.
    """
    resident_id = seed_test_context["resident_id"]
    admin_id = seed_test_context["super_admin_id"]
    admin_email = seed_test_context["super_admin_email"]
    old_email = seed_test_context["resident_email"]
    new_email = "  UPDATED.Resident@GMAIL.COM  "
    expected_norm_email = "updated.resident@gmail.com"

    headers = {"Authorization": f"Bearer {seed_test_context['admin_token']}"}
    resp = client.patch(
        f"/api/v1/users/{resident_id}/email",
        json={
            "new_email": new_email,
            "reason": "Resident changed personal email address",
        },
        headers=headers,
    )
    assert resp.status_code == 200, resp.text
    data = resp.json()["data"]

    assert data["user_id"] == str(resident_id)
    assert data["old_email"] == old_email
    assert data["new_email"] == expected_norm_email
    assert data["full_name"] == seed_test_context["resident_full_name"]
    assert data["phone"] == seed_test_context["resident_phone"]
    assert data["role_name"] == "RESIDENT"
    assert data["approval_status"] == "APPROVED"

    # Verify database state
    session_factory = client.app.state.testing_session
    db = session_factory()
    try:
        updated_user = db.get(User, resident_id)
        assert updated_user.email == expected_norm_email
        # Verify phone, password, approval_status untouched
        assert updated_user.phone == "9867634364"
        assert updated_user.password_hash == "!RESIDENT_NO_PASSWORD_demo"
        assert updated_user.approval_status == "APPROVED"

        # Verify Audit Log
        log = db.scalar(
            sa.select(AuditLog)
            .where(
                AuditLog.action == "USER_EMAIL_UPDATE",
                AuditLog.resource_id == str(resident_id),
            )
            .order_by(AuditLog.created_at.desc())
        )
        assert log is not None
        assert log.user_id == admin_id
        assert log.user_email == admin_email
        assert log.user_role == "SUPER_ADMIN"
        assert log.resource_type == "user"
        assert log.details["old_email"] == old_email
        assert log.details["new_email"] == expected_norm_email
        assert log.details["reason"] == "Resident changed personal email address"
    finally:
        db.close()


def test_email_alias_compatibility_in_request_payload(client: TestClient, seed_test_context):
    """Verifies that passing {"email": "..."} instead of {"new_email": "..."} works identically."""
    resident_id = seed_test_context["resident_id"]
    headers = {"Authorization": f"Bearer {seed_test_context['admin_token']}"}

    resp = client.patch(
        f"/api/v1/users/{resident_id}/email",
        json={"email": "alias.support@example.com"},
        headers=headers,
    )
    assert resp.status_code == 200
    assert resp.json()["data"]["new_email"] == "alias.support@example.com"


# =============================================================================
# 4. Synchronization with Pending Registration
# =============================================================================

def test_synchronization_with_staged_pending_registration(client: TestClient, seed_test_context):
    """If resident has a staged PendingResidentRegistration record, it is synchronized too."""
    session_factory = client.app.state.testing_session
    db = session_factory()
    resident_id = seed_test_context["resident_id"]
    resident_phone = seed_test_context["resident_phone"]
    resident_email = seed_test_context["resident_email"]
    resident_full_name = seed_test_context["resident_full_name"]

    try:
        pending = PendingResidentRegistration(
            phone=resident_phone,
            email=resident_email,
            registration_data={"full_name": resident_full_name, "email": resident_email},
            expires_at=datetime.now(timezone.utc) + timedelta(minutes=30),
        )
        db.add(pending)
        db.commit()
    finally:
        db.close()

    headers = {"Authorization": f"Bearer {seed_test_context['admin_token']}"}
    new_email = "synced.registration@example.com"

    resp = client.patch(
        f"/api/v1/users/{resident_id}/email",
        json={"new_email": new_email},
        headers=headers,
    )
    assert resp.status_code == 200

    db = session_factory()
    try:
        updated_pending = db.scalar(
            sa.select(PendingResidentRegistration).where(PendingResidentRegistration.phone == resident_phone)
        )
        assert updated_pending is not None
        assert updated_pending.email == new_email
        assert updated_pending.registration_data["email"] == new_email
    finally:
        db.close()


# =============================================================================
# 5. Atomic Transaction Rollback Test
# =============================================================================

def test_atomic_transaction_rollback_on_failure(client: TestClient, seed_test_context):
    """
    Verifies that if an error occurs during the operation (e.g. audit log failure),
    the User.email change is completely rolled back and NOT persisted in the database.
    """
    resident_id = seed_test_context["resident_id"]
    original_email = seed_test_context["resident_email"]
    headers = {"Authorization": f"Bearer {seed_test_context['admin_token']}"}

    # Simulate an unexpected database failure during record_audit_log
    with patch("app.services.user_service.record_audit_log", side_effect=RuntimeError("Simulated DB audit crash")):
        with pytest.raises(RuntimeError):
            client.patch(
                f"/api/v1/users/{resident_id}/email",
                json={"new_email": "should_fail@example.com"},
                headers=headers,
            )

    # Verify that in database, resident.email remains original_email
    session_factory = client.app.state.testing_session
    db = session_factory()
    try:
        check_user = db.get(User, resident_id)
        assert check_user.email == original_email, "User.email was modified despite transaction rollback!"
    finally:
        db.close()


# =============================================================================
# 6. E2E OTP Email Lookup Verification
# =============================================================================

def test_resident_login_otp_dispatches_to_new_email_after_update(client: TestClient, seed_test_context):
    """
    CORE BUSINESS REQUIREMENT:
    1. Resident has old email (e.g. resident_old@originpg.com).
    2. Super admin updates email to new.destination@example.com.
    3. Resident calls POST /api/v1/auth/resident/login/otp/request with their mobile number.
    4. Backend sends the OTP strictly to the NEW email address!
    5. Resident verifies OTP and receives authenticated JWT token.
    """
    resident_id = seed_test_context["resident_id"]
    phone = seed_test_context["resident_phone"]
    new_verified_email = "new.destination@gmail.com"
    headers = {"Authorization": f"Bearer {seed_test_context['admin_token']}"}

    # 1. Update resident's email via Super Admin endpoint
    update_resp = client.patch(
        f"/api/v1/users/{resident_id}/email",
        json={"new_email": new_verified_email, "reason": "Gmail 550 user does not exist correction"},
        headers=headers,
    )
    assert update_resp.status_code == 200

    # 2. Resident requests login OTP using their phone number
    otp_resp = client.post(
        "/api/v1/auth/resident/login/otp/request",
        json={"phone": phone},
    )
    assert otp_resp.status_code == 200, otp_resp.text
    otp_data = otp_resp.json()["data"]

    # Verify masked email in response reflects the NEW email
    assert otp_data["email_masked"] == mask_email(new_verified_email)

    # Verify DevMockEmailProvider received email at new_verified_email
    last_email = DevMockEmailProvider.get_last_email(new_verified_email)
    assert last_email is not None, f"No email was dispatched to {new_verified_email}!"
    assert last_email["to"] == new_verified_email
    assert "Resident Login" in last_email["subject"]

    # Verify OTP extraction and login completion
    raw_otp = DevMockEmailProvider.get_last_otp(new_verified_email)
    assert raw_otp is not None and len(raw_otp) == 6

    verify_resp = client.post(
        "/api/v1/auth/resident/login/otp/verify",
        json={"phone": phone, "otp": raw_otp},
    )
    assert verify_resp.status_code == 200, verify_resp.text
    token_data = verify_resp.json()["data"]
    assert "access_token" in token_data
    assert token_data["user"]["email"] == new_verified_email
