import uuid
import pytest
from fastapi.testclient import TestClient
import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.core.permissions import RoleEnum, SYSTEM_ROLES_DATA
from app.integrations.email import DevMockEmailProvider
from app.models.property import Company, Property
from app.models.role import Role
from app.models.user import User
from app.models.resident import Resident
from app.models.pending_registration import PendingResidentRegistration
from app.services.role_service import ensure_system_roles_exist, get_or_create_system_role
from app.services.otp_service import OTPService


@pytest.fixture(autouse=True)
def clean_mock_email():
    DevMockEmailProvider.clear()
    yield
    DevMockEmailProvider.clear()


def test_system_roles_idempotency(client: TestClient):
    """Verify ensure_system_roles_exist can be called repeatedly without duplicating roles."""
    db_session_factory = client.app.state.testing_session
    with db_session_factory() as db:
        # First call seeds roles
        roles_first = ensure_system_roles_exist(db)
        assert len(roles_first) == 5  # SUPER_ADMIN, PROPERTY_MANAGER, STAFF, KITCHEN, RESIDENT
        assert "RESIDENT" in roles_first
        assert "PROPERTY_MANAGER" in roles_first
        assert "STAFF" in roles_first
        assert "SUPER_ADMIN" in roles_first

        first_resident_id = roles_first["RESIDENT"].id

        # Second call must be idempotent and return identical IDs
        roles_second = ensure_system_roles_exist(db)
        assert len(roles_second) == 5
        assert roles_second["RESIDENT"].id == first_resident_id

        # Total count in DB must remain 4
        all_roles = db.query(Role).all()
        assert len(all_roles) == 5


def test_get_or_create_system_role_all_roles(client: TestClient):
    """Verify get_or_create_system_role retrieves or initializes all canonical roles."""
    db_session_factory = client.app.state.testing_session
    with db_session_factory() as db:
        resident_role = get_or_create_system_role(db, RoleEnum.RESIDENT)
        assert resident_role is not None
        assert resident_role.name == "RESIDENT"
        assert resident_role.display_name == "Resident"
        assert resident_role.is_system_role is True
        assert "profile:self" in resident_role.permissions

        manager_role = get_or_create_system_role(db, RoleEnum.PROPERTY_MANAGER)
        assert manager_role is not None
        assert manager_role.name == "PROPERTY_MANAGER"

        staff_role = get_or_create_system_role(db, RoleEnum.STAFF)
        assert staff_role is not None
        assert staff_role.name == "STAFF"

        admin_role = get_or_create_system_role(db, RoleEnum.SUPER_ADMIN)
        assert admin_role is not None
        assert admin_role.name == "SUPER_ADMIN"


def make_valid_payload(prop_id: str, phone: str, email: str, name: str = "Test Resident"):
    return {
        "full_name": name,
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
        "property_id": prop_id,
        "verification_method": "Aadhaar + PAN",
        "aadhaar_front_path": "/uploads/aadhaar_front.jpg",
        "aadhaar_back_path": "/uploads/aadhaar_back.jpg",
        "pan_card_path": "/uploads/pan.jpg",
        "resident_selfie_path": "/uploads/selfie.jpg",
    }


def test_resident_registration_and_otp_verification_self_healing_role(client: TestClient):
    """
    CRITICAL BUG TEST:
    Even if the 'RESIDENT' role is missing or deleted from the database,
    when the resident enters their OTP and clicks Verify,
    the backend automatically self-heals and creates the 'RESIDENT' role
    instead of failing with: 'System role RESIDENT is not configured.'
    """
    db_session_factory = client.app.state.testing_session
    with db_session_factory() as db:
        company = Company(
            name="Origin Living Test",
            code="ORIGIN_TEST",
            is_active=True,
        )
        db.add(company)
        db.flush()

        prop = Property(
            company_id=company.id,
            name="Origin Test PG",
            code="ORIGIN_PG_01",
            address_line1="123 Silicon Valley Road",
            city="Bengaluru",
            state="Karnataka",
            pincode="560100",
            total_floors=3,
            is_active=True,
        )
        db.add(prop)
        db.commit()
        prop_id_str = str(prop.id)

    phone = "9876500001"
    email = "test.resident.selfheal@example.com"
    reg_payload = make_valid_payload(prop_id_str, phone, email, "Self Healing Resident")

    # 1. Request resident registration OTP
    res_reg = client.post("/api/v1/auth/resident/register/otp/request", json=reg_payload)
    assert res_reg.status_code == 200, res_reg.text
    reg_resp = res_reg.json()
    assert reg_resp["success"] is True

    # 2. Simulate RESIDENT role being absent/missing from the database
    with db_session_factory() as db:
        db.query(Role).filter_by(name="RESIDENT").delete()
        db.commit()
        assert db.query(Role).filter_by(name="RESIDENT").first() is None

    # Get OTP from mock email provider
    otp_code = DevMockEmailProvider.get_last_otp(email)
    assert otp_code is not None
    assert len(otp_code) == 6

    # 3. Verify OTP - MUST SUCCEED with 201 without throwing 404 "System role 'RESIDENT' is not configured"
    verify_payload = {
        "phone": phone,
        "otp": otp_code,
    }
    res_verify = client.post("/api/v1/auth/resident/register/otp/verify", json=verify_payload)
    assert res_verify.status_code == 201, f"Expected 201 Created but got {res_verify.status_code}: {res_verify.text}"

    data = res_verify.json()["data"]
    assert data["phone"] == phone
    assert data["approval_status"] == "PENDING_APPROVAL"

    # 4. Verify database state
    with db_session_factory() as db:
        user = db.query(User).filter_by(phone=phone).first()
        assert user is not None
        assert user.approval_status == "PENDING_APPROVAL"
        assert user.is_active is True
        assert user.is_verified is True

        # Check role was dynamically initialized
        resident_role = db.get(Role, user.role_id)
        assert resident_role is not None
        assert resident_role.name == "RESIDENT"
        assert resident_role.is_system_role is True

        # Check resident profile
        resident = db.query(Resident).filter_by(user_id=user.id).first()
        assert resident is not None
        assert resident.property_id == uuid.UUID(prop_id_str)
        assert resident.kyc_status == "PENDING"


def test_resident_otp_verification_wrong_otp(client: TestClient):
    """Verify invalid OTP returns 400 Bad Request."""
    db_session_factory = client.app.state.testing_session
    with db_session_factory() as db:
        company = Company(name="Origin Test Co", code="CO_WRONG_OTP", is_active=True)
        db.add(company)
        db.flush()
        prop = Property(
            company_id=company.id, name="Test PG", code="PG_WRONG_OTP",
            address_line1="Addr", city="Bengaluru", state="Karnataka", pincode="560100",
            total_floors=2, is_active=True
        )
        db.add(prop)
        db.commit()
        prop_id_str = str(prop.id)

    phone = "9876500003"
    email = "wrong.otp@example.com"
    payload = make_valid_payload(prop_id_str, phone, email, "Wrong OTP Resident")

    req_res = client.post("/api/v1/auth/resident/register/otp/request", json=payload)
    assert req_res.status_code == 200

    # Wrong OTP
    res = client.post("/api/v1/auth/resident/register/otp/verify", json={
        "phone": phone,
        "otp": "000000",
    })
    assert res.status_code == 400
    assert "Invalid verification code" in res.text or "remaining" in res.text
