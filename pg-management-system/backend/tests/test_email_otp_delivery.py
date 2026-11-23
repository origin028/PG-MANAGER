import io
import logging
import re
import smtplib
from datetime import date, datetime, timedelta, timezone
from unittest.mock import MagicMock, patch
import pytest
from fastapi.testclient import TestClient
import sqlalchemy as sa

from app.core.config import settings
from app.core.exceptions import InternalServerError
from app.integrations.email import DevMockEmailProvider, SMTPEmailProvider, mask_email
from app.models.otp_verification import OTPVerification
from app.models.property import Company, Property
from app.models.resident import Resident
from app.models.role import Role
from app.models.user import User
from app.services.email_service import EmailService


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
        company = Company(name="Smart Group Stays", code="SMART_TEST_CO")
        db.add(company)
        db.flush()

        super_admin_role = Role(name="SUPER_ADMIN", display_name="Super Admin")
        pm_role = Role(name="PROPERTY_MANAGER", display_name="Property Manager")
        resident_role = Role(name="RESIDENT", display_name="Resident")
        db.add_all([super_admin_role, pm_role, resident_role])
        db.flush()

        prop = Property(
            company_id=company.id,
            name="Smart Luxury PG",
            code="SMART_LUX_01",
            address_line1="100 Indiranagar 100ft Road",
            pincode="560038",
            is_active=True,
        )
        db.add(prop)
        db.commit()

        return {
            "company_id": company.id,
            "property_id": prop.id,
            "super_admin_role_id": super_admin_role.id,
            "pm_role_id": pm_role.id,
            "resident_role_id": resident_role.id,
        }
    finally:
        db.close()


def make_registration_payload(seed_data, phone: str, email: str, full_name: str = "Test Resident"):
    """Generates valid JSON registration form payload."""
    return {
        "full_name": full_name,
        "date_of_birth": "1998-05-15",
        "gender": "Male",
        "occupation": "Software Engineer",
        "primary_phone": phone,
        "email": email,
        "emergency_contact": "Father - 9876543211",
        "house_flat_no": "Flat 302",
        "street": "12th Cross, Indiranagar",
        "landmark": "Near Metro Station",
        "city": "Bengaluru",
        "state": "Karnataka",
        "pincode": "560038",
        "property_id": str(seed_data["property_id"]),
        "verification_method": "Aadhaar + PAN",
        "aadhaar_front_path": "/uploads/aadhaar_front.jpg",
        "aadhaar_back_path": "/uploads/aadhaar_back.jpg",
        "pan_card_path": "/uploads/pan.jpg",
        "resident_selfie_path": "/uploads/selfie.jpg",
    }


# =============================================================================
# 1. SMTP Provider Unit Tests (Port 587 STARTTLS & Port 465 SSL)
# =============================================================================

def test_smtp_provider_starttls_port_587():
    """Verifies standard SMTP delivery with STARTTLS on port 587."""
    provider = SMTPEmailProvider(
        host="smtp.gmail.com",
        port=587,
        username="smartpg.system@gmail.com",
        password="app-specific-pwd",
        from_email="noreply@smartgrouppg.com",
        from_name="SMART GROUP PG'S",
        use_tls=True,
    )

    mock_server = MagicMock()
    mock_server.__enter__.return_value = mock_server

    with patch("smtplib.SMTP", return_value=mock_server) as mock_smtp_cls:
        sent = provider.send_email(
            to_email="resident.test@example.com",
            subject="Test Subject",
            body_text="Test plain text body with OTP 123456",
            body_html="<p>Test HTML body</p>",
        )

        assert sent is True
        mock_smtp_cls.assert_called_once_with("smtp.gmail.com", 587, timeout=15)
        mock_server.starttls.assert_called_once()
        mock_server.login.assert_called_once_with("smartpg.system@gmail.com", "app-specific-pwd")
        mock_server.send_message.assert_called_once()

        # Verify sent email message details
        msg = mock_server.send_message.call_args[0][0]
        assert msg["To"] == "resident.test@example.com"
        assert "SMART GROUP PG'S" in msg["From"]
        assert "noreply@smartgrouppg.com" in msg["From"]
        assert msg["Subject"] == "Test Subject"


def test_smtp_provider_direct_ssl_port_465():
    """Verifies direct SSL (SMTPS) delivery on port 465."""
    provider = SMTPEmailProvider(
        host="smtp.gmail.com",
        port=465,
        username="smartpg.system@gmail.com",
        password="app-specific-pwd",
        from_email="noreply@smartgrouppg.com",
        from_name="SMART GROUP PG'S",
        use_tls=True,
    )

    mock_ssl_server = MagicMock()
    mock_ssl_server.__enter__.return_value = mock_ssl_server

    with patch("smtplib.SMTP_SSL", return_value=mock_ssl_server) as mock_ssl_cls:
        sent = provider.send_email(
            to_email="resident.test@example.com",
            subject="SSL Test Subject",
            body_text="Test plain text with OTP 654321",
        )

        assert sent is True
        mock_ssl_cls.assert_called_once()
        assert mock_ssl_cls.call_args[0][0] == "smtp.gmail.com"
        assert mock_ssl_cls.call_args[0][1] == 465
        mock_ssl_server.login.assert_called_once_with("smartpg.system@gmail.com", "app-specific-pwd")
        mock_ssl_server.send_message.assert_called_once()


def test_smtp_provider_failure_raises_internal_server_error():
    """Verifies SMTP network/authentication failures raise clean InternalServerError."""
    provider = SMTPEmailProvider(
        host="smtp.gmail.com",
        port=587,
        username="smartpg.system@gmail.com",
        password="bad-password",
        from_email="noreply@smartgrouppg.com",
        from_name="SMART GROUP PG'S",
        use_tls=True,
    )

    with patch("smtplib.SMTP", side_effect=smtplib.SMTPAuthenticationError(535, b"Authentication failed")):
        with pytest.raises(InternalServerError) as exc_info:
            provider.send_email(
                to_email="resident.test@example.com",
                subject="Test Subject",
                body_text="OTP 112233",
            )
        assert "Failed to send verification email" in str(exc_info.value)


# =============================================================================
# 2. Email Template Content & Branding Tests
# =============================================================================

def test_registration_email_template_contains_required_elements():
    """Verifies registration email contains branding, OTP, 10-minute expiry, and security warning."""
    captured_messages = []

    class CapturingProvider:
        def send_email(self, to_email, subject, body_text, body_html=None):
            captured_messages.append({
                "to_email": to_email,
                "subject": subject,
                "body_text": body_text,
                "body_html": body_html,
            })
            return True

    service = EmailService(provider=CapturingProvider())
    service.send_registration_otp(
        to_email="new.resident@example.com",
        otp="849201",
        full_name="Rajesh Kumar",
    )

    assert len(captured_messages) == 1
    msg = captured_messages[0]

    assert msg["to_email"] == "new.resident@example.com"
    assert "SMART GROUP PG'S" in msg["subject"]
    assert "Resident Registration" in msg["subject"]

    # Check Plain Text Version
    text = msg["body_text"]
    assert "SMART GROUP PG'S" in text
    assert "849201" in text
    assert "Rajesh Kumar" in text
    assert "10 minutes" in text
    assert "Never share this OTP" in text
    assert "Registration" in text

    # Check HTML Version
    html = msg["body_html"]
    assert "SMART GROUP PG'S" in html
    assert "Smart Living &amp; Residence Management" in html
    assert "849201" in html
    assert "Rajesh Kumar" in html
    assert "⏱ Valid for 10 minutes only" in html
    assert "⚠️ Security Warning:" in html
    assert "Never share this OTP" in html


def test_login_email_template_contains_required_elements():
    """Verifies login email contains branding, OTP, 10-minute expiry, and security warning."""
    captured_messages = []

    class CapturingProvider:
        def send_email(self, to_email, subject, body_text, body_html=None):
            captured_messages.append({
                "to_email": to_email,
                "subject": subject,
                "body_text": body_text,
                "body_html": body_html,
            })
            return True

    service = EmailService(provider=CapturingProvider())
    service.send_login_otp(
        to_email="existing.resident@example.com",
        otp="512398",
        full_name="Priya Sharma",
    )

    assert len(captured_messages) == 1
    msg = captured_messages[0]

    assert msg["to_email"] == "existing.resident@example.com"
    assert "SMART GROUP PG'S" in msg["subject"]
    assert "Resident Login" in msg["subject"]

    # Check Plain Text Version
    text = msg["body_text"]
    assert "SMART GROUP PG'S" in text
    assert "512398" in text
    assert "Priya Sharma" in text
    assert "10 minutes" in text
    assert "Never share this OTP" in text
    assert "login" in text.lower()

    # Check HTML Version
    html = msg["body_html"]
    assert "SMART GROUP PG'S" in html
    assert "512398" in html
    assert "Priya Sharma" in html
    assert "⏱ Valid for 10 minutes only" in html
    assert "⚠️ Security Warning:" in html
    assert "Never share this OTP" in html


# =============================================================================
# 3. End-to-End Registration & Login OTP Delivery via SMTP
# =============================================================================

def test_resident_registration_otp_request_and_verify_with_smtp(client: TestClient, seed_data):
    """Tests registration OTP request dispatch via SMTP and successful verification."""
    phone = "9876599001"
    email = "applicant.smtp@example.com"
    full_name = "Amit Verma"
    payload = make_registration_payload(seed_data, phone=phone, email=email, full_name=full_name)

    mock_server = MagicMock()
    mock_server.__enter__.return_value = mock_server

    with patch("smtplib.SMTP", return_value=mock_server), \
         patch.object(settings, "EMAIL_PROVIDER", "SMTP"), \
         patch.object(settings, "SMTP_HOST", "smtp.gmail.com"):

        # 1. Request registration OTP via JSON
        resp = client.post(
            "/api/v1/auth/resident/register/otp/request",
            json=payload,
        )
        assert resp.status_code == 200, resp.text
        data = resp.json()["data"]
        assert data["phone"] == phone
        assert data["email_masked"] == mask_email(email)

        # Verify SMTP server was called and sent email to applicant's address
        mock_server.send_message.assert_called_once()
        sent_msg = mock_server.send_message.call_args[0][0]
        assert sent_msg["To"] == email
        assert "SMART GROUP PG'S" in sent_msg["Subject"]

        # Extract 6-digit OTP from message text
        msg_text = sent_msg.get_body(preferencelist=("plain",)).get_content()
        match = re.search(r"YOUR VERIFICATION CODE:\s+(\d{6})", msg_text)
        assert match is not None
        otp_code = match.group(1)

        # 2. Verify registration OTP with extracted code
        verify_resp = client.post(
            "/api/v1/auth/resident/register/otp/verify",
            json={
                "phone": phone,
                "otp": otp_code,
            },
        )
        assert verify_resp.status_code == 201, verify_resp.text
        verify_data = verify_resp.json()["data"]
        assert verify_data["approval_status"] == "PENDING_APPROVAL"
        assert verify_data["phone"] == phone
        assert verify_data["email"] == email


def test_resident_login_otp_request_and_verify_with_smtp(client: TestClient, seed_data):
    """Tests login OTP request sends OTP to the registered resident's verified email address."""
    session_factory = client.app.state.testing_session
    db = session_factory()
    phone = "9876599002"
    email = "registered.resident@example.com"

    try:
        user = User(
            company_id=seed_data["company_id"],
            role_id=seed_data["resident_role_id"],
            phone=phone,
            email=email,
            full_name="Registered Resident",
            password_hash="!RESIDENT_NO_PASSWORD_hash",
            is_active=True,
            is_verified=True,
            approval_status="APPROVED",
        )
        db.add(user)
        db.commit()
    finally:
        db.close()

    mock_server = MagicMock()
    mock_server.__enter__.return_value = mock_server

    with patch("smtplib.SMTP", return_value=mock_server), \
         patch.object(settings, "EMAIL_PROVIDER", "SMTP"), \
         patch.object(settings, "SMTP_HOST", "smtp.gmail.com"):

        # 1. Resident requests login OTP using phone number
        resp = client.post(
            "/api/v1/auth/resident/login/otp/request",
            json={"phone": phone},
        )
        assert resp.status_code == 200, resp.text
        data = resp.json()["data"]
        assert data["phone"] == phone
        assert data["email_masked"] == mask_email(email)

        # Verify email was dispatched strictly to user's registered email
        mock_server.send_message.assert_called_once()
        sent_msg = mock_server.send_message.call_args[0][0]
        assert sent_msg["To"] == email
        assert "SMART GROUP PG'S — Resident Login" in sent_msg["Subject"]

        # Extract OTP
        msg_text = sent_msg.get_body(preferencelist=("plain",)).get_content()
        match = re.search(r"YOUR VERIFICATION CODE:\s+(\d{6})", msg_text)
        assert match is not None
        otp_code = match.group(1)

        # 2. Verify login OTP and receive JWT tokens
        login_resp = client.post(
            "/api/v1/auth/resident/login/otp/verify",
            json={"phone": phone, "otp": otp_code},
        )
        assert login_resp.status_code == 200, login_resp.text
        token_data = login_resp.json()["data"]
        assert "access_token" in token_data
        assert token_data["token_type"] == "bearer"
        assert token_data["user"]["phone"] == phone


# =============================================================================
# 4. SMTP Failure Handling & Database Rollback (No Dead OTP Records)
# =============================================================================

def test_smtp_failure_rolls_back_and_leaves_no_unusable_otp_record(client: TestClient, seed_data):
    """
    CRITICAL SAFETY REQUIREMENT:
    If SMTP fails during OTP request:
    1. Returns clean HTTP 500.
    2. No OTP record is created in the database.
    3. Cooldown is NOT burned, so the resident can immediately retry once SMTP is resolved.
    """
    session_factory = client.app.state.testing_session
    phone = "9876599003"
    email = "smtp.fail@example.com"
    payload = make_registration_payload(seed_data, phone=phone, email=email)

    with patch("smtplib.SMTP", side_effect=smtplib.SMTPConnectError(421, b"Connection refused")), \
         patch.object(settings, "EMAIL_PROVIDER", "SMTP"), \
         patch.object(settings, "SMTP_HOST", "smtp.gmail.com"):

        resp = client.post(
            "/api/v1/auth/resident/register/otp/request",
            json=payload,
        )
        assert resp.status_code == 500

    # Verify NO OTP record exists in DB for this phone
    db = session_factory()
    try:
        otp_record = db.scalar(
            sa.select(OTPVerification).where(OTPVerification.phone == phone)
        )
        assert otp_record is None, "An unusable OTP record was left in the database after email dispatch failure!"
    finally:
        db.close()

    # Verify resident is NOT blocked by cooldown on immediate retry after SMTP is healthy
    mock_server = MagicMock()
    mock_server.__enter__.return_value = mock_server

    with patch("smtplib.SMTP", return_value=mock_server), \
         patch.object(settings, "EMAIL_PROVIDER", "SMTP"), \
         patch.object(settings, "SMTP_HOST", "smtp.gmail.com"):

        retry_resp = client.post(
            "/api/v1/auth/resident/register/otp/request",
            json=payload,
        )
        # MUST succeed with 200, not 429 Too Many Requests
        assert retry_resp.status_code == 200, f"Expected 200 on retry, got {retry_resp.status_code}: {retry_resp.text}"


def test_smtp_login_failure_rolls_back_and_leaves_no_unusable_otp_record(client: TestClient, seed_data):
    """
    Verifies same safe rollback behavior for resident login OTP request when SMTP fails.
    """
    session_factory = client.app.state.testing_session
    db = session_factory()
    phone = "9876599004"
    email = "login.smtp.fail@example.com"

    try:
        user = User(
            company_id=seed_data["company_id"],
            role_id=seed_data["resident_role_id"],
            phone=phone,
            email=email,
            full_name="Login Fail Test",
            password_hash="!RESIDENT_NO_PASSWORD_hash",
            is_active=True,
            is_verified=True,
            approval_status="APPROVED",
        )
        db.add(user)
        db.commit()
    finally:
        db.close()

    with patch("smtplib.SMTP", side_effect=smtplib.SMTPServerDisconnected("Connection unexpectedly closed")), \
         patch.object(settings, "EMAIL_PROVIDER", "SMTP"), \
         patch.object(settings, "SMTP_HOST", "smtp.gmail.com"):

        resp = client.post(
            "/api/v1/auth/resident/login/otp/request",
            json={"phone": phone},
        )
        assert resp.status_code == 500

    # Verify no dead OTP record
    db = session_factory()
    try:
        otp_record = db.scalar(
            sa.select(OTPVerification).where(OTPVerification.phone == phone)
        )
        assert otp_record is None
    finally:
        db.close()

    # Retry with working SMTP
    mock_server = MagicMock()
    mock_server.__enter__.return_value = mock_server

    with patch("smtplib.SMTP", return_value=mock_server), \
         patch.object(settings, "EMAIL_PROVIDER", "SMTP"), \
         patch.object(settings, "SMTP_HOST", "smtp.gmail.com"):

        retry_resp = client.post(
            "/api/v1/auth/resident/login/otp/request",
            json={"phone": phone},
        )
        assert retry_resp.status_code == 200


# =============================================================================
# 5. Security: Salted Hash, Expiry, Single-Use, No Leakage
# =============================================================================

def test_otp_is_cryptographically_salted_and_hashed_in_database(client: TestClient, seed_data):
    """Ensures raw OTP is never stored in plain text in the database."""
    session_factory = client.app.state.testing_session
    phone = "9876599005"
    email = "crypto.resident@example.com"
    payload = make_registration_payload(seed_data, phone=phone, email=email)

    resp = client.post(
        "/api/v1/auth/resident/register/otp/request",
        json=payload,
    )
    assert resp.status_code == 200

    db = session_factory()
    try:
        otp_record = db.scalar(
            sa.select(OTPVerification).where(OTPVerification.phone == phone)
        )
        assert otp_record is not None
        # Plain OTP is 6 digits; hash is 64 hex characters (SHA256)
        assert len(otp_record.otp_hash) == 64
        assert len(otp_record.salt) == 32
        # Salted hash does NOT equal raw OTP
        raw_otp = DevMockEmailProvider.get_last_otp(email)
        assert raw_otp not in otp_record.otp_hash
    finally:
        db.close()


def test_production_mode_never_logs_otp(caplog):
    """Verifies that in production mode or when DEBUG=False, OTP codes are NEVER logged."""
    caplog.set_level(logging.INFO)

    provider = DevMockEmailProvider()
    with patch.object(settings, "ENVIRONMENT", "production"), \
         patch.object(settings, "DEBUG", False):

        provider.send_email(
            to_email="confidential@example.com",
            subject="Verification Code",
            body_text="Your OTP is 773399",
        )

        for record in caplog.records:
            assert "773399" not in record.message
            assert "c************l@example.com" in record.message or "c*l@example.com" in record.message or "****" in record.message


def test_smtp_otp_expiry_enforcement(client: TestClient, seed_data):
    """Enforces 10-minute expiry: expired OTP cannot be verified."""
    session_factory = client.app.state.testing_session
    phone = "9876599006"
    email = "expired.smtp@example.com"
    payload = make_registration_payload(seed_data, phone=phone, email=email)

    mock_server = MagicMock()
    mock_server.__enter__.return_value = mock_server

    with patch("smtplib.SMTP", return_value=mock_server), \
         patch.object(settings, "EMAIL_PROVIDER", "SMTP"), \
         patch.object(settings, "SMTP_HOST", "smtp.gmail.com"):

        resp = client.post("/api/v1/auth/resident/register/otp/request", json=payload)
        assert resp.status_code == 200

        sent_msg = mock_server.send_message.call_args[0][0]
        msg_text = sent_msg.get_body(preferencelist=("plain",)).get_content()
        otp_code = re.search(r"YOUR VERIFICATION CODE:\s+(\d{6})", msg_text).group(1)

    # Fast forward OTP expiration in DB
    db = session_factory()
    try:
        db.execute(
            sa.update(OTPVerification)
            .where(OTPVerification.phone == phone)
            .values(expires_at=datetime.now(timezone.utc) - timedelta(seconds=10))
        )
        db.commit()
    finally:
        db.close()

    # Attempt verification with expired OTP
    verify_resp = client.post(
        "/api/v1/auth/resident/register/otp/verify",
        json={"phone": phone, "otp": otp_code},
    )
    assert verify_resp.status_code == 400
    assert "expired" in verify_resp.text.lower()


def test_smtp_otp_max_attempts_enforcement(client: TestClient, seed_data):
    """Enforces 3 maximum attempts: 3 consecutive wrong attempts lock the OTP."""
    phone = "9876599007"
    email = "attempts.smtp@example.com"
    payload = make_registration_payload(seed_data, phone=phone, email=email)

    mock_server = MagicMock()
    mock_server.__enter__.return_value = mock_server

    with patch("smtplib.SMTP", return_value=mock_server), \
         patch.object(settings, "EMAIL_PROVIDER", "SMTP"), \
         patch.object(settings, "SMTP_HOST", "smtp.gmail.com"):

        resp = client.post("/api/v1/auth/resident/register/otp/request", json=payload)
        assert resp.status_code == 200

        sent_msg = mock_server.send_message.call_args[0][0]
        msg_text = sent_msg.get_body(preferencelist=("plain",)).get_content()
        otp_code = re.search(r"YOUR VERIFICATION CODE:\s+(\d{6})", msg_text).group(1)

    # 1st wrong attempt
    resp1 = client.post("/api/v1/auth/resident/register/otp/verify", json={"phone": phone, "otp": "000001"})
    assert resp1.status_code == 400
    assert "2 attempt(s) remaining" in resp1.text

    # 2nd wrong attempt
    resp2 = client.post("/api/v1/auth/resident/register/otp/verify", json={"phone": phone, "otp": "000002"})
    assert resp2.status_code == 400
    assert "1 attempt(s) remaining" in resp2.text

    # 3rd wrong attempt (exceeds threshold)
    resp3 = client.post("/api/v1/auth/resident/register/otp/verify", json={"phone": phone, "otp": "000003"})
    assert resp3.status_code == 400
    assert "exceeded" in resp3.text.lower()

    # Even with correct OTP afterwards, it remains locked
    resp_correct = client.post("/api/v1/auth/resident/register/otp/verify", json={"phone": phone, "otp": otp_code})
    assert resp_correct.status_code == 400
    assert "exceeded" in resp_correct.text.lower() or "expired" in resp_correct.text.lower() or "invalid" in resp_correct.text.lower()


def test_smtp_otp_single_use_prevention(client: TestClient, seed_data):
    """Enforces single-use: verified OTP cannot be reused."""
    phone = "9876599008"
    email = "singleuse.smtp@example.com"
    payload = make_registration_payload(seed_data, phone=phone, email=email)

    mock_server = MagicMock()
    mock_server.__enter__.return_value = mock_server

    with patch("smtplib.SMTP", return_value=mock_server), \
         patch.object(settings, "EMAIL_PROVIDER", "SMTP"), \
         patch.object(settings, "SMTP_HOST", "smtp.gmail.com"):

        resp = client.post("/api/v1/auth/resident/register/otp/request", json=payload)
        assert resp.status_code == 200

        sent_msg = mock_server.send_message.call_args[0][0]
        msg_text = sent_msg.get_body(preferencelist=("plain",)).get_content()
        otp_code = re.search(r"YOUR VERIFICATION CODE:\s+(\d{6})", msg_text).group(1)

    # 1st verification succeeds
    v1 = client.post("/api/v1/auth/resident/register/otp/verify", json={"phone": phone, "otp": otp_code})
    assert v1.status_code == 201

    # 2nd verification with same OTP must fail
    v2 = client.post("/api/v1/auth/resident/register/otp/verify", json={"phone": phone, "otp": otp_code})
    assert v2.status_code in (400, 401, 409)


def test_unauthenticated_user_cannot_specify_arbitrary_email_for_login(client: TestClient, seed_data):
    """
    SECURITY REQUIREMENT:
    Resident login request requires only the resident's mobile number.
    Any attempt to pass a rogue recipient email in the payload is ignored;
    the backend strictly dispatches the OTP to the verified registered email on file.
    """
    session_factory = client.app.state.testing_session
    db = session_factory()
    phone = "9876599009"
    legitimate_email = "victim.resident@example.com"

    try:
        user = User(
            company_id=seed_data["company_id"],
            role_id=seed_data["resident_role_id"],
            phone=phone,
            email=legitimate_email,
            full_name="Victim Resident",
            password_hash="!RESIDENT_NO_PASSWORD_hash",
            is_active=True,
            is_verified=True,
            approval_status="APPROVED",
        )
        db.add(user)
        db.commit()
    finally:
        db.close()

    mock_server = MagicMock()
    mock_server.__enter__.return_value = mock_server

    with patch("smtplib.SMTP", return_value=mock_server), \
         patch.object(settings, "EMAIL_PROVIDER", "SMTP"), \
         patch.object(settings, "SMTP_HOST", "smtp.gmail.com"):

        # Attacker attempts to provide a different attacker_email in the JSON body
        resp = client.post(
            "/api/v1/auth/resident/login/otp/request",
            json={
                "phone": phone,
                "email": "attacker@evil.com",  # Rogue unverified email
            },
        )
        assert resp.status_code == 200

        # Verify email was dispatched STRICTLY to legitimate_email, NOT attacker@evil.com
        mock_server.send_message.assert_called_once()
        sent_msg = mock_server.send_message.call_args[0][0]
        assert sent_msg["To"] == legitimate_email
        assert sent_msg["To"] != "attacker@evil.com"


# =============================================================================
# 6. Regression: body_html Defined in All EmailService Methods & Mock Safety
# =============================================================================

def test_rejection_email_template_contains_body_html_without_name_error():
    """Verifies send_resident_rejection_notification defines and passes body_html."""
    captured = []

    class CapturingProvider:
        def send_email(self, to_email, subject, body_text, body_html=None):
            captured.append({
                "to_email": to_email,
                "subject": subject,
                "body_text": body_text,
                "body_html": body_html,
            })
            return True

    service = EmailService(provider=CapturingProvider())
    # This must NOT raise NameError: name 'body_html' is not defined
    result = service.send_resident_rejection_notification(
        to_email="rejected.applicant@example.com",
        resident_name="Sunil Patil",
        property_name="Origin Prime PG",
        reason="Incomplete Aadhaar documentation",
    )
    assert result is True
    assert len(captured) == 1
    assert captured[0]["body_html"] is not None
    assert "Sunil Patil" in captured[0]["body_html"]
    assert "Incomplete Aadhaar documentation" in captured[0]["body_text"]


def test_all_email_service_methods_generate_both_plain_and_html_bodies():
    """Verifies that every method on EmailService properly generates both body_text and body_html."""
    dispatches = []

    class DispatchTracker:
        def send_email(self, to_email, subject, body_text, body_html=None):
            assert body_text is not None and len(body_text) > 0, "body_text must be non-empty"
            assert body_html is not None and len(body_html) > 0, "body_html must be non-empty"
            dispatches.append((to_email, subject))
            return True

    service = EmailService(provider=DispatchTracker())

    service.send_registration_otp("test1@example.com", "123456", "User One")
    service.send_login_otp("test2@example.com", "654321", "User Two")
    service.send_admin_registration_super_key("test3@example.com", "998877", "Test PG Corp")
    service.send_admin_login_super_key("test4@example.com", "112233", "Admin User")
    service.send_resident_approval_notification("test5@example.com", "User Five", "Origin PG", "101", "A")
    service.send_resident_rejection_notification("test6@example.com", "User Six", "Origin PG", "Docs unclear")
    service.send_password_change_otp("test7@example.com", "554433", "Admin Seven")

    assert len(dispatches) == 7


def test_production_mode_mock_otp_request_raises_email_delivery_error(client: TestClient, seed_data):
    """
    CRITICAL SAFETY REQUIREMENT:
    In a production environment, if EMAIL_PROVIDER is set to MOCK or SMTP is unconfigured,
    the API MUST NOT return 200 and falsely claim an email was delivered.
    Instead, it must raise EmailDeliveryError (HTTP 500) and roll back.
    """
    payload = make_registration_payload(seed_data, phone="9876599020", email="fake.prod@example.com")

    with patch.object(settings, "ENVIRONMENT", "production"), \
         patch.object(settings, "EMAIL_PROVIDER", "MOCK"), \
         patch.object(settings, "SMTP_PASSWORD", ""), \
         patch.object(settings, "SMTP_USERNAME", ""), \
         patch.object(settings, "SMTP_USER", ""):

        resp = client.post(
            "/api/v1/auth/resident/register/otp/request",
            json=payload,
        )
        assert resp.status_code == 500
        assert "Email delivery service is not configured" in resp.text


def test_resend_email_provider_success():
    """Verifies that ResendEmailProvider sends via HTTPS API and returns True."""
    from app.integrations.email import ResendEmailProvider

    captured_requests = []

    class MockHTTPResponse:
        status = 200
        def __enter__(self):
            return self
        def __exit__(self, exc_type, exc_val, exc_tb):
            pass

    def mock_urlopen(req, timeout=15):
        captured_requests.append(req)
        return MockHTTPResponse()

    provider = ResendEmailProvider(
        api_key="re_test_key_12345",
        from_email="onboarding@resend.dev",
        from_name="Origin Living",
    )

    with patch("urllib.request.urlopen", side_effect=mock_urlopen):
        result = provider.send_email(
            to_email="resident@example.com",
            subject="Verification Code",
            body_text="Your OTP is 123456",
            body_html="<p>Your OTP is 123456</p>",
        )
        assert result is True
        assert len(captured_requests) == 1
        req = captured_requests[0]
        assert req.get_full_url() == "https://api.resend.com/emails"
        assert req.get_header("Authorization") == "Bearer re_test_key_12345"


def test_resend_email_provider_webmail_sanitization():
    """Verifies that ResendEmailProvider replaces public webmail domains (@gmail.com) with onboarding@resend.dev."""
    from app.integrations.email import ResendEmailProvider

    provider = ResendEmailProvider(
        api_key="re_test_key_12345",
        from_email="originpg@gmail.com",
        from_name="Origin Living",
    )
    assert provider.from_email == "onboarding@resend.dev"


def test_resend_email_provider_http_403_raises_clear_error():
    """Verifies that Resend HTTP 403 response extracts provider reason and raises EmailDeliveryError."""
    import urllib.error
    import io
    from app.integrations.email import ResendEmailProvider
    from app.core.exceptions import EmailDeliveryError

    err_json = b'{"statusCode": 403, "message": "You can only send testing emails to your own email address", "name": "validation_error"}'
    http_err = urllib.error.HTTPError(
        url="https://api.resend.com/emails",
        code=403,
        msg="Forbidden",
        hdrs={},
        fp=io.BytesIO(err_json),
    )

    provider = ResendEmailProvider(
        api_key="re_test_key_12345",
        from_email="onboarding@resend.dev",
        from_name="Origin Living",
    )

    with patch("urllib.request.urlopen", side_effect=http_err):
        with pytest.raises(EmailDeliveryError) as exc_info:
            provider.send_email(
                to_email="resident@example.com",
                subject="Verification Code",
                body_text="Your OTP is 123456",
            )
        assert "HTTP 403" in str(exc_info.value)
        assert "You can only send testing emails to your own email address" in str(exc_info.value)


def test_resilient_email_provider_fallback_from_resend_403_to_smtp():
    """Verifies that ResilientEmailProvider automatically catches Resend HTTP 403 and succeeds via SMTP."""
    import urllib.error
    import io
    from app.integrations.email import ResendEmailProvider, ResilientEmailProvider
    from app.core.exceptions import EmailDeliveryError

    err_json = b'{"statusCode": 403, "message": "Domain not verified", "name": "validation_error"}'
    http_err = urllib.error.HTTPError(
        url="https://api.resend.com/emails",
        code=403,
        msg="Forbidden",
        hdrs={},
        fp=io.BytesIO(err_json),
    )

    primary_resend = ResendEmailProvider(
        api_key="re_test_key_12345",
        from_email="onboarding@resend.dev",
    )

    fallback_smtp = MagicMock()
    fallback_smtp.send_email.return_value = True

    composite = ResilientEmailProvider(
        primary=primary_resend,
        fallback=fallback_smtp,
        primary_name="ResendEmailProvider",
        fallback_name="SMTPEmailProvider",
    )

    with patch("urllib.request.urlopen", side_effect=http_err):
        res = composite.send_email(
            to_email="resident@example.com",
            subject="Verification Code",
            body_text="Your OTP is 123456",
            body_html="<p>Your OTP is 123456</p>",
        )
        assert res is True
        fallback_smtp.send_email.assert_called_once_with(
            to_email="resident@example.com",
            subject="Verification Code",
            body_text="Your OTP is 123456",
            body_html="<p>Your OTP is 123456</p>",
        )


def test_resilient_email_provider_fallback_from_smtp_timeout_to_resend():
    """Verifies that ResilientEmailProvider catches SMTP timeout and succeeds via Resend HTTPS."""
    from app.integrations.email import ResilientEmailProvider
    from app.core.exceptions import EmailDeliveryError

    primary_smtp = MagicMock()
    primary_smtp.send_email.side_effect = EmailDeliveryError("SMTP connection timed out.")

    fallback_resend = MagicMock()
    fallback_resend.send_email.return_value = True

    composite = ResilientEmailProvider(
        primary=primary_smtp,
        fallback=fallback_resend,
        primary_name="SMTPEmailProvider",
        fallback_name="ResendEmailProvider",
    )

    res = composite.send_email(
        to_email="resident@example.com",
        subject="Verification Code",
        body_text="Your OTP is 123456",
    )
    assert res is True
    fallback_resend.send_email.assert_called_once()


def test_resilient_email_provider_both_fail_raises_email_delivery_error():
    """Verifies that if both primary and fallback fail, an informative EmailDeliveryError is raised."""
    from app.integrations.email import ResilientEmailProvider
    from app.core.exceptions import EmailDeliveryError

    primary = MagicMock()
    primary.send_email.side_effect = EmailDeliveryError("Primary failed (HTTP 403)")

    fallback = MagicMock()
    fallback.send_email.side_effect = EmailDeliveryError("Fallback failed (SMTP port blocked)")

    composite = ResilientEmailProvider(
        primary=primary,
        fallback=fallback,
        primary_name="PrimaryProvider",
        fallback_name="FallbackProvider",
    )

    with pytest.raises(EmailDeliveryError) as exc_info:
        composite.send_email(
            to_email="resident@example.com",
            subject="Verification Code",
            body_text="Your OTP is 123456",
        )
    assert "Email delivery failed across all providers" in str(exc_info.value)
    assert "PrimaryProvider" in str(exc_info.value)
    assert "FallbackProvider" in str(exc_info.value)


def test_get_email_provider_returns_resilient_when_both_configured():
    """Verifies factory constructs ResilientEmailProvider when both Resend and SMTP are configured."""
    from app.integrations.email import get_email_provider, ResilientEmailProvider

    with patch.object(settings, "ENVIRONMENT", "production"), \
         patch.object(settings, "EMAIL_PROVIDER", "RESEND"), \
         patch.object(settings, "BREVO_API_KEY", None), \
         patch.object(settings, "RESEND_API_KEY", "re_prod_test_key"), \
         patch.object(settings, "SMTP_HOST", "smtp.gmail.com"), \
         patch.object(settings, "SMTP_PASSWORD", "secret_pass"), \
         patch.object(settings, "SMTP_USERNAME", "tharadrataher@gmail.com"):

        provider = get_email_provider()
        assert isinstance(provider, ResilientEmailProvider)
        assert provider.primary_name == "ResendEmailProvider"
        assert provider.fallback_name == "SMTPEmailProvider"


def test_brevo_email_provider_success():
    """Verifies BrevoEmailProvider formats payload and sends via HTTPS REST API."""
    import json
    from app.integrations.email import BrevoEmailProvider

    captured = []

    class MockHTTPResponse:
        status = 201
        def __enter__(self):
            return self
        def __exit__(self, exc_type, exc_val, exc_tb):
            pass

    def mock_urlopen(req, timeout=15):
        captured.append(req)
        return MockHTTPResponse()

    provider = BrevoEmailProvider(
        api_key="xkeysib-test-12345",
        from_email="tharadrataher@gmail.com",
        from_name="Origin PG Living",
    )

    with patch("urllib.request.urlopen", side_effect=mock_urlopen):
        result = provider.send_email(
            to_email="external.resident@yahoo.com",
            subject="Verification Code",
            body_text="Your code is 654321",
            body_html="<p>Your code is 654321</p>",
        )
        assert result is True
        assert len(captured) == 1
        req = captured[0]
        assert req.get_full_url() == "https://api.brevo.com/v3/smtp/email"
        assert req.get_header("Api-key") == "xkeysib-test-12345"
        assert req.get_header("Content-type") == "application/json"
        body = json.loads(req.data.decode("utf-8"))
        assert body["sender"]["email"] == "tharadrataher@gmail.com"
        assert body["to"][0]["email"] == "external.resident@yahoo.com"
        assert body["textContent"] == "Your code is 654321"
        assert body["htmlContent"] == "<p>Your code is 654321</p>"


def test_brevo_email_provider_unverified_sender_error():
    """Verifies Brevo HTTP 403 error is cleanly parsed and reported."""
    import urllib.error
    import io
    from app.integrations.email import BrevoEmailProvider
    from app.core.exceptions import EmailDeliveryError

    err_json = b'{"code": "permission_denied", "message": "Sender is not verified in Brevo account"}'
    http_err = urllib.error.HTTPError(
        url="https://api.brevo.com/v3/smtp/email",
        code=403,
        msg="Forbidden",
        hdrs={},
        fp=io.BytesIO(err_json),
    )

    provider = BrevoEmailProvider(
        api_key="xkeysib-test-12345",
        from_email="unverified@gmail.com",
    )

    with patch("urllib.request.urlopen", side_effect=http_err):
        with pytest.raises(EmailDeliveryError) as exc_info:
            provider.send_email(
                to_email="resident@example.com",
                subject="Verification Code",
                body_text="Your code is 654321",
            )
        assert "HTTP 403" in str(exc_info.value)
        assert "Sender is not verified" in str(exc_info.value)


def test_sendgrid_email_provider_success():
    """Verifies SendGridEmailProvider formats payload and sends via HTTPS REST API."""
    import json
    from app.integrations.email import SendGridEmailProvider

    captured = []

    class MockHTTPResponse:
        status = 202
        def __enter__(self):
            return self
        def __exit__(self, exc_type, exc_val, exc_tb):
            pass

    def mock_urlopen(req, timeout=15):
        captured.append(req)
        return MockHTTPResponse()

    provider = SendGridEmailProvider(
        api_key="SG.test-key-12345",
        from_email="tharadrataher@gmail.com",
        from_name="Origin PG Living",
    )

    with patch("urllib.request.urlopen", side_effect=mock_urlopen):
        result = provider.send_email(
            to_email="external.resident@gmail.com",
            subject="Verification Code",
            body_text="Your code is 112233",
            body_html="<p>Your code is 112233</p>",
        )
        assert result is True
        assert len(captured) == 1
        req = captured[0]
        assert req.get_full_url() == "https://api.sendgrid.com/v3/mail/send"
        assert req.get_header("Authorization") == "Bearer SG.test-key-12345"


def test_get_email_provider_chooses_brevo_when_configured():
    """Verifies factory selects Brevo as primary provider when BREVO_API_KEY is configured."""
    from app.integrations.email import get_email_provider, BrevoEmailProvider, ResilientEmailProvider

    with patch.object(settings, "ENVIRONMENT", "production"), \
         patch.object(settings, "EMAIL_PROVIDER", "BREVO"), \
         patch.object(settings, "BREVO_API_KEY", "xkeysib-active-key"), \
         patch.object(settings, "RESEND_API_KEY", "re_backup_key"):

        provider = get_email_provider()
        assert isinstance(provider, ResilientEmailProvider)
        assert provider.primary_name == "BrevoEmailProvider"
        assert provider.fallback_name == "ResendEmailProvider"





