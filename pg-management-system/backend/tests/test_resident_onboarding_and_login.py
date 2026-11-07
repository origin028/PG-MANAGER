import io
import uuid
from datetime import date, datetime, timedelta, timezone
from unittest.mock import patch
import pytest
import sqlalchemy as sa
from fastapi.testclient import TestClient

from app.core.exceptions import InternalServerError
from app.integrations.email import DevMockEmailProvider
from app.main import app
from app.models.otp_verification import OTPVerification
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
def seed_data(client: TestClient):
    """Seeds Company, Property, and Roles in the test database."""
    session_factory = client.app.state.testing_session
    db = session_factory()
    try:
        company = Company(name="Origin Stays Co", code="ORIGIN_ONBOARD")
        db.add(company)
        db.flush()

        super_admin_role = Role(name="SUPER_ADMIN", display_name="Super Admin")
        pm_role = Role(name="PROPERTY_MANAGER", display_name="Property Manager")
        resident_role = Role(name="RESIDENT", display_name="Resident")
        db.add_all([super_admin_role, pm_role, resident_role])
        db.flush()

        prop = Property(
            company_id=company.id,
            name="Origin Luxury PG",
            code="ORIGIN_LUX",
            address_line1="42 MG Road",
            pincode="560001",
            is_active=True,
        )
        db.add(prop)
        db.commit()

        return {
            "company_id": company.id,
            "property_id": prop.id,
            "resident_role_id": resident_role.id,
        }
    finally:
        db.close()


def test_01_successful_resident_registration_otp_request(client: TestClient, seed_data):
    """Scenario 1: Successful resident registration OTP request with Aadhaar + PAN."""
    prop_id = str(seed_data["property_id"])
    email = "rahul.sharma@example.com"
    phone = "9876543210"

    form_data = {
        "full_name": "Rahul Sharma",
        "date_of_birth": "1998-05-15",
        "gender": "Male",
        "occupation": "Software Engineer",
        "primary_phone": phone,
        "email": email,
        "emergency_contact": "Father - Ramesh Sharma - 9876543211",
        "house_flat_no": "Flat 302",
        "street": "12th Cross, Indiranagar",
        "landmark": "Near Metro Station",
        "city": "Bengaluru",
        "state": "Karnataka",
        "pincode": "560038",
        "property_id": prop_id,
        "verification_method": "Aadhaar + PAN",
    }
    files = {
        "aadhaar_front_file": ("aadhaar_f.jpg", io.BytesIO(b"dummy aadhaar front content"), "image/jpeg"),
        "aadhaar_back_file": ("aadhaar_b.jpg", io.BytesIO(b"dummy aadhaar back content"), "image/jpeg"),
        "pan_card_file": ("pan.jpg", io.BytesIO(b"dummy pan card content"), "image/jpeg"),
        "resident_selfie_file": ("selfie.jpg", io.BytesIO(b"dummy resident selfie content"), "image/jpeg"),
    }

    response = client.post("/api/v1/auth/resident/register/otp/request", data=form_data, files=files)
    assert response.status_code == 200, response.text
    data = response.json()
    assert data["success"] is True
    assert data["data"]["phone"] == "9876543210"
    assert "email_masked" in data["data"]
    assert data["data"]["expires_in_seconds"] == 600

    # Verify OTP was dispatched via mock email provider
    sent_otp = DevMockEmailProvider.get_last_otp(email)
    assert sent_otp is not None
    assert len(sent_otp) == 6
    assert sent_otp.isdigit()

    # Verify pending registration was staged in database
    session_factory = client.app.state.testing_session
    db = session_factory()
    try:
        pending = db.scalar(
            sa.select(PendingResidentRegistration).where(PendingResidentRegistration.phone == phone)
        )
        assert pending is not None
        assert pending.email == email
        assert pending.registration_data["full_name"] == "Rahul Sharma"
        assert pending.registration_data["verification_method"] == "AADHAAR_PAN"
        assert "uploads/kyc/" in pending.registration_data["aadhaar_front_path"]
        assert "uploads/kyc/" in pending.registration_data["resident_selfie_path"]
    finally:
        db.close()


def test_02_invalid_registration_fields(client: TestClient, seed_data):
    """Scenario 2: Validation failure on missing fields or invalid phone format."""
    prop_id = str(seed_data["property_id"])

    # Invalid phone number (too short)
    payload = {
        "full_name": "Test User",
        "date_of_birth": "1999-01-01",
        "gender": "Female",
        "occupation": "Analyst",
        "primary_phone": "12345",  # Invalid!
        "email": "test@example.com",
        "emergency_contact": "Mother - 9876543210",
        "house_flat_no": "101",
        "street": "MG Road",
        "city": "Bengaluru",
        "state": "Karnataka",
        "pincode": "560001",
        "property_id": prop_id,
        "verification_method": "Passport Only",
        "passport_path": "uploads/kyc/dummy.jpg",
        "resident_selfie_path": "uploads/kyc/selfie.jpg",
    }
    response = client.post("/api/v1/auth/resident/register/otp/request", json=payload)
    assert response.status_code == 400
    assert "Invalid mobile number format" in response.text

    # Missing mandatory field (full_name missing)
    payload["primary_phone"] = "9876500001"
    del payload["full_name"]
    response = client.post("/api/v1/auth/resident/register/otp/request", json=payload)
    assert response.status_code == 400
    assert "Missing required registration fields" in response.text


def test_03_missing_required_kyc_documents(client: TestClient, seed_data):
    """Scenario 3: Missing required KYC documents rejected."""
    prop_id = str(seed_data["property_id"])

    # Aadhaar + PAN method selected, but pan_card_file is omitted
    form_data = {
        "full_name": "Pooja Patel",
        "date_of_birth": "2001-03-20",
        "gender": "Female",
        "occupation": "Designer",
        "primary_phone": "9876500002",
        "email": "pooja@example.com",
        "emergency_contact": "Brother - 9876543212",
        "house_flat_no": "A-12",
        "street": "Koramangala",
        "city": "Bengaluru",
        "state": "Karnataka",
        "pincode": "560034",
        "property_id": prop_id,
        "verification_method": "Aadhaar + PAN",
    }
    files = {
        "aadhaar_front_file": ("aadhaar_f.jpg", io.BytesIO(b"content"), "image/jpeg"),
        "aadhaar_back_file": ("aadhaar_b.jpg", io.BytesIO(b"content"), "image/jpeg"),
        # pan_card_file is missing!
        "resident_selfie_file": ("selfie.jpg", io.BytesIO(b"content"), "image/jpeg"),
    }
    response = client.post("/api/v1/auth/resident/register/otp/request", data=form_data, files=files)
    assert response.status_code == 400
    assert "pan_card_file" in response.text


def test_04_invalid_kyc_method(client: TestClient, seed_data):
    """Scenario 4: Invalid KYC method or illegal document combination rejected."""
    prop_id = str(seed_data["property_id"])

    # Method name is completely invalid
    form_data = {
        "full_name": "Amit Kumar",
        "date_of_birth": "1995-12-10",
        "gender": "Male",
        "occupation": "Doctor",
        "primary_phone": "9876500003",
        "email": "amit@example.com",
        "emergency_contact": "Spouse - 9876543213",
        "house_flat_no": "B-4",
        "street": "HSR Layout",
        "city": "Bengaluru",
        "state": "Karnataka",
        "pincode": "560102",
        "property_id": prop_id,
        "verification_method": "Driving License Only",  # Not allowed!
    }
    files = {
        "resident_selfie_file": ("selfie.jpg", io.BytesIO(b"content"), "image/jpeg"),
    }
    response = client.post("/api/v1/auth/resident/register/otp/request", data=form_data, files=files)
    assert response.status_code == 400
    assert "Invalid verification method" in response.text

    # Passport Only selected, but Aadhaar file also uploaded
    form_data["verification_method"] = "Passport Only"
    files = {
        "passport_file": ("passport.pdf", io.BytesIO(b"content"), "application/pdf"),
        "aadhaar_front_file": ("aadhaar.jpg", io.BytesIO(b"content"), "image/jpeg"),  # Forbidden!
        "resident_selfie_file": ("selfie.jpg", io.BytesIO(b"content"), "image/jpeg"),
    }
    response = client.post("/api/v1/auth/resident/register/otp/request", data=form_data, files=files)
    assert response.status_code == 400
    assert "cannot be submitted when 'Passport Only' method is chosen" in response.text


def test_05_successful_registration_otp_verification(client: TestClient, seed_data):
    """Scenario 5: Successful registration OTP verification creates resident in PENDING_APPROVAL status."""
    prop_id = str(seed_data["property_id"])
    email = "deepak.verma@example.com"
    phone = "9876500004"

    # Step 1 & 2: Submit registration
    payload = {
        "full_name": "Deepak Verma",
        "date_of_birth": "1997-08-25",
        "gender": "Male",
        "occupation": "Banker",
        "primary_phone": phone,
        "email": email,
        "emergency_contact": "Father - Mohan Verma - 9876543214",
        "house_flat_no": "204 Green Woods",
        "street": "Outer Ring Road",
        "landmark": "Near EcoSpace",
        "city": "Bengaluru",
        "state": "Karnataka",
        "pincode": "560103",
        "property_id": prop_id,
        "verification_method": "Passport Only",
        "passport_path": "uploads/kyc/dummy_passport.pdf",
        "resident_selfie_path": "uploads/kyc/dummy_selfie.jpg",
    }
    resp1 = client.post("/api/v1/auth/resident/register/otp/request", json=payload)
    assert resp1.status_code == 200

    otp = DevMockEmailProvider.get_last_otp(email)
    assert otp is not None

    # Step 3: Verify OTP
    verify_payload = {"phone": phone, "otp": otp}
    resp2 = client.post("/api/v1/auth/resident/register/otp/verify", json=verify_payload)
    assert resp2.status_code == 201, resp2.text
    data = resp2.json()["data"]

    assert data["full_name"] == "Deepak Verma"
    assert data["phone"] == phone
    assert data["email"] == email
    assert data["status"] == "PENDING_APPROVAL"
    assert data["approval_status"] == "PENDING_APPROVAL"

    # Verify database state
    session_factory = client.app.state.testing_session
    db = session_factory()
    try:
        user = db.scalar(sa.select(User).where(User.phone == phone))
        assert user is not None
        assert user.approval_status == "PENDING_APPROVAL"
        assert user.is_verified is True
        assert user.is_active is True
        assert user.password_hash.startswith("!RESIDENT_NO_PASSWORD_")

        resident = db.scalar(sa.select(Resident).where(Resident.user_id == user.id))
        assert resident is not None
        assert resident.status == "PENDING_APPROVAL"
        assert resident.emergency_contact == "Father - Mohan Verma - 9876543214"
        assert resident.verification_method == "PASSPORT"
        assert resident.passport_path == "uploads/kyc/dummy_passport.pdf"

        # Staged pending record must be deleted
        pending = db.scalar(sa.select(PendingResidentRegistration).where(PendingResidentRegistration.phone == phone))
        assert pending is None
    finally:
        db.close()


def test_06_incorrect_otp(client: TestClient, seed_data):
    """Scenario 6: Incorrect OTP rejected with remaining attempts counter."""
    prop_id = str(seed_data["property_id"])
    email = "wrong.otp@example.com"
    phone = "9876500005"

    payload = {
        "full_name": "Test Resident",
        "date_of_birth": "1999-01-01",
        "gender": "Male",
        "occupation": "Engineer",
        "primary_phone": phone,
        "email": email,
        "emergency_contact": "Father - 9876543210",
        "house_flat_no": "1",
        "street": "Road",
        "city": "Bengaluru",
        "state": "Karnataka",
        "pincode": "560001",
        "property_id": prop_id,
        "verification_method": "Passport Only",
        "passport_path": "uploads/kyc/p.jpg",
        "resident_selfie_path": "uploads/kyc/s.jpg",
    }
    client.post("/api/v1/auth/resident/register/otp/request", json=payload)

    # Submit wrong OTP
    resp = client.post("/api/v1/auth/resident/register/otp/verify", json={"phone": phone, "otp": "000000"})
    assert resp.status_code == 400
    assert "Invalid verification code" in resp.text
    assert "attempt(s) remaining" in resp.text


def test_07_expired_otp(client: TestClient, seed_data):
    """Scenario 7: Expired OTP rejected."""
    prop_id = str(seed_data["property_id"])
    email = "expired.otp@example.com"
    phone = "9876500006"

    payload = {
        "full_name": "Expired Test",
        "date_of_birth": "1999-01-01",
        "gender": "Male",
        "occupation": "Engineer",
        "primary_phone": phone,
        "email": email,
        "emergency_contact": "Father - 9876543210",
        "house_flat_no": "1",
        "street": "Road",
        "city": "Bengaluru",
        "state": "Karnataka",
        "pincode": "560001",
        "property_id": prop_id,
        "verification_method": "Passport Only",
        "passport_path": "uploads/kyc/p.jpg",
        "resident_selfie_path": "uploads/kyc/s.jpg",
    }
    client.post("/api/v1/auth/resident/register/otp/request", json=payload)
    otp = DevMockEmailProvider.get_last_otp(email)

    # Manually expire the OTP in DB
    session_factory = client.app.state.testing_session
    db = session_factory()
    try:
        db.execute(
            sa.update(OTPVerification)
            .where(OTPVerification.phone == phone)
            .values(expires_at=datetime.now(timezone.utc) - timedelta(minutes=1))
        )
        db.commit()
    finally:
        db.close()

    resp = client.post("/api/v1/auth/resident/register/otp/verify", json={"phone": phone, "otp": otp})
    assert resp.status_code == 400
    assert "OTP has expired" in resp.text


def test_08_maximum_otp_attempts(client: TestClient, seed_data):
    """Scenario 8: Maximum OTP attempts enforced; OTP invalidated."""
    prop_id = str(seed_data["property_id"])
    email = "max.attempts@example.com"
    phone = "9876500007"

    payload = {
        "full_name": "Attempt Test",
        "date_of_birth": "1999-01-01",
        "gender": "Male",
        "occupation": "Engineer",
        "primary_phone": phone,
        "email": email,
        "emergency_contact": "Father - 9876543210",
        "house_flat_no": "1",
        "street": "Road",
        "city": "Bengaluru",
        "state": "Karnataka",
        "pincode": "560001",
        "property_id": prop_id,
        "verification_method": "Passport Only",
        "passport_path": "uploads/kyc/p.jpg",
        "resident_selfie_path": "uploads/kyc/s.jpg",
    }
    client.post("/api/v1/auth/resident/register/otp/request", json=payload)
    real_otp = DevMockEmailProvider.get_last_otp(email)

    # Attempt 1 (wrong)
    r1 = client.post("/api/v1/auth/resident/register/otp/verify", json={"phone": phone, "otp": "111111"})
    assert r1.status_code == 400
    # Attempt 2 (wrong)
    r2 = client.post("/api/v1/auth/resident/register/otp/verify", json={"phone": phone, "otp": "222222"})
    assert r2.status_code == 400
    # Attempt 3 (wrong) -> threshold reached
    r3 = client.post("/api/v1/auth/resident/register/otp/verify", json={"phone": phone, "otp": "333333"})
    assert r3.status_code == 400
    assert "Maximum verification attempts exceeded" in r3.text

    # Attempt 4 (even with real OTP) -> blocked
    r4 = client.post("/api/v1/auth/resident/register/otp/verify", json={"phone": phone, "otp": real_otp})
    assert r4.status_code == 400
    assert "Maximum verification attempts exceeded" in r4.text


def test_09_successful_resident_login_otp_request(client: TestClient, seed_data):
    """Scenario 9: Successful resident login OTP request dispatched to registered email."""
    session_factory = client.app.state.testing_session
    db = session_factory()
    phone = "9876500008"
    email = "existing.resident@example.com"

    try:
        # Seed an existing resident user
        user = User(
            company_id=seed_data["company_id"],
            role_id=seed_data["resident_role_id"],
            phone=phone,
            email=email,
            full_name="Existing Resident",
            password_hash="!RESIDENT_NO_PASSWORD_abc123",
            is_active=True,
            is_verified=True,
            approval_status="APPROVED",
        )
        db.add(user)
        db.flush()
        resident = Resident(
            user_id=user.id,
            property_id=seed_data["property_id"],
            check_in_date=date.today(),
            status="ACTIVE",
        )
        db.add(resident)
        db.commit()
    finally:
        db.close()

    resp = client.post("/api/v1/auth/resident/login/otp/request", json={"phone": phone})
    assert resp.status_code == 200, resp.text
    data = resp.json()["data"]
    assert data["phone"] == phone
    assert "email_masked" in data
    assert data["expires_in_seconds"] == 600

    sent_otp = DevMockEmailProvider.get_last_otp(email)
    assert sent_otp is not None
    assert len(sent_otp) == 6


def test_10_unknown_mobile_number_login(client: TestClient, seed_data):
    """Scenario 10: Login request for unknown mobile number returns 404."""
    resp = client.post("/api/v1/auth/resident/login/otp/request", json={"phone": "9999999999"})
    assert resp.status_code == 404
    assert "No registered resident found" in resp.text


def test_11_successful_resident_login_otp_verification(client: TestClient, seed_data):
    """Scenario 11: Successful resident login OTP verification returns JWT TokenResponse (no password!)."""
    session_factory = client.app.state.testing_session
    db = session_factory()
    phone = "9876500009"
    email = "active.resident@example.com"

    try:
        user = User(
            company_id=seed_data["company_id"],
            role_id=seed_data["resident_role_id"],
            phone=phone,
            email=email,
            full_name="Active Resident",
            password_hash="!RESIDENT_NO_PASSWORD_xyz456",
            is_active=True,
            is_verified=True,
            approval_status="APPROVED",
        )
        db.add(user)
        db.flush()
        resident = Resident(
            user_id=user.id,
            property_id=seed_data["property_id"],
            check_in_date=date.today(),
            status="ACTIVE",
        )
        db.add(resident)
        db.commit()
    finally:
        db.close()

    # Step 1: Request Login OTP
    r1 = client.post("/api/v1/auth/resident/login/otp/request", json={"phone": phone})
    assert r1.status_code == 200
    otp = DevMockEmailProvider.get_last_otp(email)

    # Step 2: Verify Login OTP
    r2 = client.post("/api/v1/auth/resident/login/otp/verify", json={"phone": phone, "otp": otp})
    assert r2.status_code == 200, r2.text
    token_data = r2.json()["data"]

    assert "access_token" in token_data
    assert "refresh_token" in token_data
    assert token_data["token_type"] == "bearer"
    assert token_data["user"]["phone"] == phone
    assert token_data["user"]["role"]["name"] == "RESIDENT"


def test_12_invalid_login_otp(client: TestClient, seed_data):
    """Scenario 12: Invalid login OTP rejected."""
    session_factory = client.app.state.testing_session
    db = session_factory()
    phone = "9876500010"
    email = "resident.fail@example.com"

    try:
        user = User(
            company_id=seed_data["company_id"],
            role_id=seed_data["resident_role_id"],
            phone=phone,
            email=email,
            full_name="Fail Test",
            password_hash="!RESIDENT_NO_PASSWORD_123",
            is_active=True,
            is_verified=True,
            approval_status="APPROVED",
        )
        db.add(user)
        db.commit()
    finally:
        db.close()

    client.post("/api/v1/auth/resident/login/otp/request", json={"phone": phone})
    resp = client.post("/api/v1/auth/resident/login/otp/verify", json={"phone": phone, "otp": "999999"})
    assert resp.status_code == 400
    assert "Invalid verification code" in resp.text


def test_13_otp_reuse_prevention(client: TestClient, seed_data):
    """Scenario 13: OTP cannot be reused once verified."""
    session_factory = client.app.state.testing_session
    db = session_factory()
    phone = "9876500011"
    email = "reuse.test@example.com"

    try:
        user = User(
            company_id=seed_data["company_id"],
            role_id=seed_data["resident_role_id"],
            phone=phone,
            email=email,
            full_name="Reuse Test",
            password_hash="!RESIDENT_NO_PASSWORD_reuse",
            is_active=True,
            is_verified=True,
            approval_status="APPROVED",
        )
        db.add(user)
        db.commit()
    finally:
        db.close()

    client.post("/api/v1/auth/resident/login/otp/request", json={"phone": phone})
    otp = DevMockEmailProvider.get_last_otp(email)

    # First verification succeeds
    resp1 = client.post("/api/v1/auth/resident/login/otp/verify", json={"phone": phone, "otp": otp})
    assert resp1.status_code == 200

    # Second verification with exact same OTP fails
    resp2 = client.post("/api/v1/auth/resident/login/otp/verify", json={"phone": phone, "otp": otp})
    assert resp2.status_code == 400
    assert "OTP has expired or does not exist" in resp2.text


def test_14_email_delivery_failure(client: TestClient, seed_data):
    """Scenario 14: Email delivery failure handled gracefully with 500 error."""
    session_factory = client.app.state.testing_session
    db = session_factory()
    phone = "9876500012"
    email = "email.fail@example.com"

    try:
        user = User(
            company_id=seed_data["company_id"],
            role_id=seed_data["resident_role_id"],
            phone=phone,
            email=email,
            full_name="Email Fail Resident",
            password_hash="!RESIDENT_NO_PASSWORD_fail",
            is_active=True,
            is_verified=True,
            approval_status="APPROVED",
        )
        db.add(user)
        db.commit()
    finally:
        db.close()

    # Simulate email provider raising an internal delivery exception
    with patch("app.services.email_service.EmailService.send_login_otp", side_effect=InternalServerError("SMTP connection failed")):
        resp = client.post("/api/v1/auth/resident/login/otp/request", json={"phone": phone})
        assert resp.status_code == 500


def test_15_resident_jwt_authentication_after_successful_login(client: TestClient, seed_data):
    """Scenario 15: Resident authenticated with issued JWT can access /api/v1/auth/me."""
    session_factory = client.app.state.testing_session
    db = session_factory()
    phone = "9876500013"
    email = "jwt.resident@example.com"

    try:
        user = User(
            company_id=seed_data["company_id"],
            role_id=seed_data["resident_role_id"],
            phone=phone,
            email=email,
            full_name="JWT Verified Resident",
            password_hash="!RESIDENT_NO_PASSWORD_jwt",
            is_active=True,
            is_verified=True,
            approval_status="APPROVED",
        )
        db.add(user)
        db.flush()
        resident = Resident(
            user_id=user.id,
            property_id=seed_data["property_id"],
            check_in_date=date.today(),
            status="ACTIVE",
        )
        db.add(resident)
        db.commit()
    finally:
        db.close()

    # Login via OTP
    client.post("/api/v1/auth/resident/login/otp/request", json={"phone": phone})
    otp = DevMockEmailProvider.get_last_otp(email)
    login_resp = client.post("/api/v1/auth/resident/login/otp/verify", json={"phone": phone, "otp": otp})
    assert login_resp.status_code == 200
    token = login_resp.json()["data"]["access_token"]

    # Access protected profile endpoint with Bearer token
    headers = {"Authorization": f"Bearer {token}"}
    me_resp = client.get("/api/v1/auth/me", headers=headers)
    assert me_resp.status_code == 200, me_resp.text
    profile = me_resp.json()["data"]

    assert profile["full_name"] == "JWT Verified Resident"
    assert profile["phone"] == phone
    assert profile["email"] == email
    assert profile["role"]["name"] == "RESIDENT"
    assert profile["is_active"] is True
    assert profile["is_verified"] is True
