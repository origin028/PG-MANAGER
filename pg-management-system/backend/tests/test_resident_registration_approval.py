import hashlib
import logging
import uuid
from datetime import date, datetime, timedelta, timezone
import pytest
import sqlalchemy as sa

from app.core.config import settings
from app.core.exceptions import InternalServerError
from app.core.security import create_access_token, get_password_hash
from app.integrations.sms import DevMockSMSProvider, ProductionSMSProvider, SMSProvider, get_sms_provider
from app.models.bed import Bed
from app.models.invoice import Invoice
from app.models.property import Company, Property
from app.models.resident import Resident
from app.models.role import Role
from app.models.room import Room
from app.models.user import User, UserPropertyAccess
from app.services.otp_service import OTPService, hash_otp, normalize_phone


def get_error_message(response):
    data = response.json()
    if "error" in data and isinstance(data["error"], dict):
        return data["error"].get("message", "")
    return str(data.get("detail", ""))


def seed_approval_test_context(session_factory):
    db = session_factory()
    try:
        company = Company(name="Origin Stays Co", code="ORIGIN_APPV")
        db.add(company)
        db.flush()

        super_admin_role = Role(name="SUPER_ADMIN", display_name="Super Admin")
        pm_role = Role(name="PROPERTY_MANAGER", display_name="Property Manager")
        resident_role = Role(name="RESIDENT", display_name="Resident")
        db.add_all([super_admin_role, pm_role, resident_role])
        db.flush()

        prop_1 = Property(
            company_id=company.id,
            name="Origin Heights PG",
            code="ORIGIN_01",
            address_line1="100 Brigade Road",
            pincode="560025",
            is_active=True,
        )
        prop_2 = Property(
            company_id=company.id,
            name="Origin Residency PG",
            code="ORIGIN_02",
            address_line1="200 Indiranagar",
            pincode="560038",
            is_active=True,
        )
        db.add_all([prop_1, prop_2])
        db.flush()

        # Admin 1 has access to prop_1
        admin_user = User(
            company_id=company.id,
            role_id=pm_role.id,
            email="manager@origin.com",
            phone="9876500001",
            full_name="Manager Bob",
            password_hash=get_password_hash("password123"),
            is_active=True,
            approval_status="APPROVED",
        )
        # Admin 2 has access to prop_2
        admin_user_2 = User(
            company_id=company.id,
            role_id=pm_role.id,
            email="manager2@origin.com",
            phone="9876500002",
            full_name="Manager Charlie",
            password_hash=get_password_hash("password123"),
            is_active=True,
            approval_status="APPROVED",
        )
        db.add_all([admin_user, admin_user_2])
        db.flush()

        db.add(UserPropertyAccess(user_id=admin_user.id, property_id=prop_1.id, access_level="MANAGER"))
        db.add(UserPropertyAccess(user_id=admin_user_2.id, property_id=prop_2.id, access_level="MANAGER"))

        room = Room(property_id=prop_1.id, room_number="101", floor_number=1, room_type="DOUBLE_SHARING", max_occupancy=2)
        db.add(room)
        db.flush()

        bed_1 = Bed(room_id=room.id, bed_number="B1", status="AVAILABLE")
        bed_2 = Bed(room_id=room.id, bed_number="B2", status="AVAILABLE")
        db.add_all([bed_1, bed_2])
        db.commit()

        return {
            "company_id": company.id,
            "prop_1_id": prop_1.id,
            "prop_2_id": prop_2.id,
            "admin_user_id": admin_user.id,
            "admin_user_phone": admin_user.phone,
            "admin_user_2_id": admin_user_2.id,
            "admin_user_2_phone": admin_user_2.phone,
            "room_id": room.id,
            "bed_1_id": bed_1.id,
            "bed_2_id": bed_2.id,
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


class TestOTPFlow:
    def test_request_otp_success(self, client):
        DevMockSMSProvider.clear()
        phone = "9876543210"
        response = client.post("/api/v1/auth/resident/register/otp/request", json={"phone": phone})
        assert response.status_code == 200
        # Verify demo response explicitly notes demo mode and does not falsely claim cellular SMS delivery
        assert response.json()["message"] == "Verification code generated (Demo Mode: check console log)."
        data = response.json()["data"]
        assert data["phone"] == phone
        assert data["expires_in_seconds"] == 600

        # Verify OTP was dispatched through SMS provider abstraction
        sent_otp = DevMockSMSProvider.get_last_otp(phone)
        assert sent_otp is not None
        assert len(sent_otp) == 6
        assert sent_otp.isdigit()

    def test_demo_otp_logging_and_fail_closed_in_production(self, caplog, monkeypatch):
        provider = DevMockSMSProvider()
        phone = "9876543299"
        raw_otp = "852963"

        # 1. In development/demo, OTP is logged with phone masked (never full phone)
        monkeypatch.setattr(settings, "ENVIRONMENT", "development")
        with caplog.at_level(logging.INFO):
            caplog.clear()
            provider.send_otp(phone, raw_otp, "test message")
            assert raw_otp in caplog.text
            assert phone not in caplog.text  # Full 10-digit number must never be logged
            assert phone[-4:] in caplog.text

        # 2. In production, fail-closed: OTP must NEVER appear in logs
        monkeypatch.setattr(settings, "ENVIRONMENT", "production")
        with caplog.at_level(logging.INFO):
            caplog.clear()
            provider.send_otp(phone, raw_otp, "test message")
            assert raw_otp not in caplog.text
            assert phone not in caplog.text

        # 3. In unknown/missing environment, fail-closed: OTP must NEVER appear in logs
        monkeypatch.setattr(settings, "ENVIRONMENT", "unknown_env")
        with caplog.at_level(logging.INFO):
            caplog.clear()
            provider.send_otp(phone, raw_otp, "test message")
            assert raw_otp not in caplog.text

        monkeypatch.setattr(settings, "ENVIRONMENT", "")
        with caplog.at_level(logging.INFO):
            caplog.clear()
            provider.send_otp(phone, raw_otp, "test message")
            assert raw_otp not in caplog.text

    def test_production_provider_never_falls_back_to_mock(self, monkeypatch):
        # Even with missing SMS_GATEWAY_API_KEY, production environment must return ProductionSMSProvider
        monkeypatch.setattr(settings, "ENVIRONMENT", "production")
        monkeypatch.delenv("SMS_GATEWAY_API_KEY", raising=False)

        provider = get_sms_provider()
        assert isinstance(provider, ProductionSMSProvider)
        assert not isinstance(provider, DevMockSMSProvider)
        assert provider.is_mock is False

        # Attempting to send in production without API key safely fails with InternalServerError
        with pytest.raises(InternalServerError) as exc_info:
            provider.send_otp("9876543210", "123456", "test")
        assert "SMS service is currently unavailable" in str(exc_info.value)

    def test_real_sms_mode_response_message(self, client, monkeypatch):
        class RealSMSProviderStub(SMSProvider):
            is_mock = False

            def send_otp(self, phone: str, otp: str, message: str) -> bool:
                return True

        from app.services import otp_service
        monkeypatch.setattr(otp_service, "get_sms_provider", lambda: RealSMSProviderStub())

        phone = "9876543298"
        response = client.post("/api/v1/auth/resident/register/otp/request", json={"phone": phone})
        assert response.status_code == 200
        # In real SMS mode, response reflects cellular carrier dispatch
        assert response.json()["message"] == "Verification code sent to registered mobile number."

    def test_request_otp_cooldown_rate_limit(self, client):
        phone = "9876543211"
        res1 = client.post("/api/v1/auth/resident/register/otp/request", json={"phone": phone})
        assert res1.status_code == 200

        # Rapid repeated request must be rejected with 429
        res2 = client.post("/api/v1/auth/resident/register/otp/request", json={"phone": phone})
        assert res2.status_code == 429
        assert "Please wait" in get_error_message(res2)

    def test_request_otp_duplicate_phone_rejected(self, client):
        ctx = seed_approval_test_context(client.app.state.testing_session)
        # Attempt OTP request for already registered admin's phone
        res = client.post("/api/v1/auth/resident/register/otp/request", json={"phone": ctx["admin_user_phone"]})
        assert res.status_code == 409
        assert "already registered" in get_error_message(res)

    def test_verify_otp_max_attempts_exceeded(self, client):
        phone = "9876543212"
        client.post("/api/v1/auth/resident/register/otp/request", json={"phone": phone})

        # Submit 3 wrong attempts
        for attempt in range(1, 4):
            res = client.post(
                "/api/v1/auth/resident/register",
                json={
                    "phone": phone,
                    "otp": "000000",
                    "full_name": "Test Resident",
                    "password": "Password123",
                    "property_id": str(uuid.uuid4()),
                },
            )
            assert res.status_code == 400

        # 4th attempt must state exceeded/invalidated
        res_locked = client.post(
            "/api/v1/auth/resident/register",
            json={
                "phone": phone,
                "otp": "000000",
                "full_name": "Test Resident",
                "password": "Password123",
                "property_id": str(uuid.uuid4()),
            },
        )
        assert res_locked.status_code == 400
        assert "exceeded" in get_error_message(res_locked).lower()


class TestResidentRegistrationAndApproval:
    def test_registration_creates_pending_approval_account(self, client):
        ctx = seed_approval_test_context(client.app.state.testing_session)
        phone = "9876543220"
        client.post("/api/v1/auth/resident/register/otp/request", json={"phone": phone})
        otp = DevMockSMSProvider.get_last_otp(phone)

        # Register resident
        reg_payload = {
            "phone": phone,
            "otp": otp,
            "full_name": "Rahul Verma",
            "password": "SecurePassword@123",
            "property_id": str(ctx["prop_1_id"]),
            "email": "rahul@example.com",
        }
        res = client.post("/api/v1/auth/resident/register", json=reg_payload)
        assert res.status_code == 201
        data = res.json()["data"]

        assert data["status"] == "PENDING_APPROVAL"
        assert data["approval_status"] == "PENDING_APPROVAL"
        assert data["full_name"] == "Rahul Verma"

        # Verify DB records
        db = client.app.state.testing_session()
        user = db.scalar(sa.select(User).where(User.phone == phone))
        assert user is not None
        assert user.approval_status == "PENDING_APPROVAL"
        assert user.role.name == "RESIDENT"
        assert user.company_id == ctx["company_id"]  # Enforced server-side

        resident = db.scalar(sa.select(Resident).where(Resident.user_id == user.id))
        assert resident is not None
        assert resident.status == "PENDING_APPROVAL"
        db.close()

    def test_pending_resident_blocked_from_invoices_and_payments(self, client):
        ctx = seed_approval_test_context(client.app.state.testing_session)
        phone = "9876543221"
        client.post("/api/v1/auth/resident/register/otp/request", json={"phone": phone})
        otp = DevMockSMSProvider.get_last_otp(phone)

        reg_res = client.post(
            "/api/v1/auth/resident/register",
            json={
                "phone": phone,
                "otp": otp,
                "full_name": "Sneha Patel",
                "password": "Password@123",
                "property_id": str(ctx["prop_1_id"]),
            },
        )
        assert reg_res.status_code == 201

        db = client.app.state.testing_session()
        user = db.scalar(sa.select(User).where(User.phone == phone))
        resident = db.scalar(sa.select(Resident).where(Resident.user_id == user.id))
        user_id = user.id
        resident_id = resident.id
        company_id = user.company_id

        # Seed an invoice for this resident to test access control
        inv = Invoice(
            property_id=ctx["prop_1_id"],
            resident_id=resident_id,
            invoice_number="INV-TEST-001",
            billing_month="2026-10",
            invoice_type="RENT",
            amount=10000.0,
            paid_amount=0.0,
            due_date=date(2026, 11, 5),
            status="PENDING",
        )
        db.add(inv)
        db.commit()
        invoice_id = str(inv.id)
        db.close()

        auth_headers = make_auth_header(user_id, "RESIDENT", company_id)

        # 1. Access to profile (/residents/me) must succeed and show pending state
        me_res = client.get("/api/v1/residents/me", headers=auth_headers)
        assert me_res.status_code == 200
        assert me_res.json()["data"]["status"] == "PENDING_APPROVAL"
        assert me_res.json()["data"]["approval_status"] == "PENDING_APPROVAL"

        # 2. Access to invoices must be blocked (403 Forbidden)
        inv_res = client.get("/api/v1/invoices/my", headers=auth_headers)
        assert inv_res.status_code == 403
        assert "pending admin approval" in get_error_message(inv_res).lower()

        single_inv_res = client.get(f"/api/v1/invoices/{invoice_id}", headers=auth_headers)
        assert single_inv_res.status_code == 403

        # 3. Access to payment creation must be blocked (403 Forbidden)
        pay_res = client.post(
            "/api/v1/payments/requests",
            json={"invoice_id": invoice_id, "amount": 10000.0, "idempotency_key": "IDEMP-TEST-001"},
            headers=auth_headers,
        )
        assert pay_res.status_code == 403

        # 4. Access to receipts must be blocked (403 Forbidden)
        rec_res = client.get("/api/v1/receipts/my", headers=auth_headers)
        assert rec_res.status_code == 403

    def test_admin_review_pending_approvals_with_property_boundary(self, client):
        ctx = seed_approval_test_context(client.app.state.testing_session)
        # Register resident in prop_1
        phone1 = "9876543231"
        client.post("/api/v1/auth/resident/register/otp/request", json={"phone": phone1})
        client.post(
            "/api/v1/auth/resident/register",
            json={
                "phone": phone1,
                "otp": DevMockSMSProvider.get_last_otp(phone1),
                "full_name": "Resident Prop 1",
                "password": "Password@123",
                "property_id": str(ctx["prop_1_id"]),
            },
        )

        # Admin 1 (manages prop_1) can see pending registrations
        admin_1_headers = make_auth_header(ctx["admin_user_id"], "PROPERTY_MANAGER", ctx["company_id"])
        res1 = client.get("/api/v1/residents/pending-approvals", headers=admin_1_headers)
        assert res1.status_code == 200
        items1 = res1.json()["data"]["items"]
        assert any(item["phone"] == phone1 for item in items1)

        # Admin 2 (manages only prop_2) cannot see prop_1's pending registrations
        admin_2_headers = make_auth_header(ctx["admin_user_2_id"], "PROPERTY_MANAGER", ctx["company_id"])
        res2 = client.get("/api/v1/residents/pending-approvals", headers=admin_2_headers)
        assert res2.status_code == 200
        items2 = res2.json()["data"]["items"]
        assert not any(item["phone"] == phone1 for item in items2)

    def test_admin_approve_resident_and_grant_access(self, client):
        ctx = seed_approval_test_context(client.app.state.testing_session)
        phone = "9876543241"
        client.post("/api/v1/auth/resident/register/otp/request", json={"phone": phone})
        reg_res = client.post(
            "/api/v1/auth/resident/register",
            json={
                "phone": phone,
                "otp": DevMockSMSProvider.get_last_otp(phone),
                "full_name": "Arjun Das",
                "password": "Password@123",
                "property_id": str(ctx["prop_1_id"]),
            },
        )
        resident_id = reg_res.json()["data"]["resident_id"]

        # Admin 1 approves resident and assigns room and bed
        admin_headers = make_auth_header(ctx["admin_user_id"], "PROPERTY_MANAGER", ctx["company_id"])
        approve_res = client.post(
            f"/api/v1/residents/{resident_id}/approve",
            json={
                "room_id": str(ctx["room_id"]),
                "bed_id": str(ctx["bed_1_id"]),
                "monthly_rent": 12500.0,
                "security_deposit": 25000.0,
            },
            headers=admin_headers,
        )
        assert approve_res.status_code == 200
        approved_data = approve_res.json()["data"]
        assert approved_data["status"] == "ACTIVE"
        assert approved_data["bed_id"] == str(ctx["bed_1_id"])

        # Verify DB user is now APPROVED and bed is occupied
        db = client.app.state.testing_session()
        res_db = db.get(Resident, uuid.UUID(resident_id))
        assert res_db.status == "ACTIVE"
        user_db = db.get(User, res_db.user_id)
        assert user_db.approval_status == "APPROVED"
        assert user_db.is_active is True
        user_id = user_db.id
        company_id = user_db.company_id

        bed_db = db.get(Bed, ctx["bed_1_id"])
        assert bed_db.status == "OCCUPIED"
        db.close()

        # Now approved resident can access /invoices/my without 403
        resident_headers = make_auth_header(user_id, "RESIDENT", company_id)
        inv_res = client.get("/api/v1/invoices/my", headers=resident_headers)
        assert inv_res.status_code == 200

    def test_admin_reject_resident_deactivates_account(self, client):
        ctx = seed_approval_test_context(client.app.state.testing_session)
        phone = "9876543251"
        client.post("/api/v1/auth/resident/register/otp/request", json={"phone": phone})
        reg_res = client.post(
            "/api/v1/auth/resident/register",
            json={
                "phone": phone,
                "otp": DevMockSMSProvider.get_last_otp(phone),
                "full_name": "Rejected Applicant",
                "password": "Password@123",
                "property_id": str(ctx["prop_1_id"]),
            },
        )
        resident_id = reg_res.json()["data"]["resident_id"]

        # Admin rejects resident with reason
        admin_headers = make_auth_header(ctx["admin_user_id"], "PROPERTY_MANAGER", ctx["company_id"])
        rej_res = client.post(
            f"/api/v1/residents/{resident_id}/reject",
            json={"reason": "Incomplete verification documents."},
            headers=admin_headers,
        )
        assert rej_res.status_code == 200
        assert rej_res.json()["data"]["status"] == "REJECTED"

        # Verify DB user is marked REJECTED and inactive
        db = client.app.state.testing_session()
        res_db = db.get(Resident, uuid.UUID(resident_id))
        assert res_db.status == "REJECTED"
        user_db = db.get(User, res_db.user_id)
        assert user_db.approval_status == "REJECTED"
        assert user_db.is_active is False
        user_id = user_db.id
        company_id = user_db.company_id
        db.close()

        # Attempt to access with rejected user credentials
        auth_headers = make_auth_header(user_id, "RESIDENT", company_id)
        inv_res = client.get("/api/v1/invoices/my", headers=auth_headers)
        # Blocked as inactive / rejected
        assert inv_res.status_code in (401, 403)


class TestSecurityAndEdgeCases:
    def test_cross_property_approval_attempt_blocked(self, client):
        ctx = seed_approval_test_context(client.app.state.testing_session)
        # Resident in prop_1
        phone = "9876543261"
        client.post("/api/v1/auth/resident/register/otp/request", json={"phone": phone})
        reg_res = client.post(
            "/api/v1/auth/resident/register",
            json={
                "phone": phone,
                "otp": DevMockSMSProvider.get_last_otp(phone),
                "full_name": "Resident Prop 1",
                "password": "Password@123",
                "property_id": str(ctx["prop_1_id"]),
            },
        )
        resident_id = reg_res.json()["data"]["resident_id"]

        # Admin 2 (manages only prop_2) tries to approve resident of prop_1
        admin_2_headers = make_auth_header(ctx["admin_user_2_id"], "PROPERTY_MANAGER", ctx["company_id"])
        res = client.post(
            f"/api/v1/residents/{resident_id}/approve",
            json={},
            headers=admin_2_headers,
        )
        assert res.status_code == 403
        assert "not have access rights" in get_error_message(res).lower()

    def test_unauthorized_user_cannot_approve(self, client):
        ctx = seed_approval_test_context(client.app.state.testing_session)
        phone = "9876543271"
        client.post("/api/v1/auth/resident/register/otp/request", json={"phone": phone})
        reg_res = client.post(
            "/api/v1/auth/resident/register",
            json={
                "phone": phone,
                "otp": DevMockSMSProvider.get_last_otp(phone),
                "full_name": "Applicant",
                "password": "Password@123",
                "property_id": str(ctx["prop_1_id"]),
            },
        )
        resident_id = reg_res.json()["data"]["resident_id"]

        # Resident attempts to approve another resident
        db = client.app.state.testing_session()
        res_db = db.get(Resident, uuid.UUID(resident_id))
        user_id = res_db.user_id
        company_id = ctx["company_id"]
        db.close()

        res_headers = make_auth_header(user_id, "RESIDENT", company_id)
        res = client.post(
            f"/api/v1/residents/{resident_id}/approve",
            json={},
            headers=res_headers,
        )
        assert res.status_code == 403

    def test_bed_conflict_cannot_double_assign(self, client):
        ctx = seed_approval_test_context(client.app.state.testing_session)

        # 1. Register and approve resident A with bed_1
        phone_a = "9876543281"
        client.post("/api/v1/auth/resident/register/otp/request", json={"phone": phone_a})
        reg_a = client.post(
            "/api/v1/auth/resident/register",
            json={
                "phone": phone_a,
                "otp": DevMockSMSProvider.get_last_otp(phone_a),
                "full_name": "Resident A",
                "password": "Password@123",
                "property_id": str(ctx["prop_1_id"]),
            },
        )
        res_a_id = reg_a.json()["data"]["resident_id"]

        admin_headers = make_auth_header(ctx["admin_user_id"], "PROPERTY_MANAGER", ctx["company_id"])
        client.post(
            f"/api/v1/residents/{res_a_id}/approve",
            json={"room_id": str(ctx["room_id"]), "bed_id": str(ctx["bed_1_id"])},
            headers=admin_headers,
        )

        # 2. Register resident B and attempt to approve with same bed_1
        phone_b = "9876543282"
        client.post("/api/v1/auth/resident/register/otp/request", json={"phone": phone_b})
        reg_b = client.post(
            "/api/v1/auth/resident/register",
            json={
                "phone": phone_b,
                "otp": DevMockSMSProvider.get_last_otp(phone_b),
                "full_name": "Resident B",
                "password": "Password@123",
                "property_id": str(ctx["prop_1_id"]),
            },
        )
        res_b_id = reg_b.json()["data"]["resident_id"]

        res_double = client.post(
            f"/api/v1/residents/{res_b_id}/approve",
            json={"room_id": str(ctx["room_id"]), "bed_id": str(ctx["bed_1_id"])},
            headers=admin_headers,
        )
        assert res_double.status_code == 409
        assert "already occupied" in get_error_message(res_double).lower()

    def test_existing_approved_users_maintain_access(self, client):
        ctx = seed_approval_test_context(client.app.state.testing_session)
        # Seed an existing resident with approval_status="APPROVED" and status="ACTIVE"
        db = client.app.state.testing_session()
        role = db.scalar(sa.select(Role).where(Role.name == "RESIDENT"))
        old_user = User(
            company_id=ctx["company_id"],
            role_id=role.id,
            email="existing@origin.com",
            phone="9876543299",
            full_name="Existing Resident",
            password_hash=get_password_hash("password123"),
            is_active=True,
            approval_status="APPROVED",
        )
        db.add(old_user)
        db.flush()

        old_resident = Resident(
            user_id=old_user.id,
            property_id=ctx["prop_1_id"],
            check_in_date=date.today(),
            monthly_rent=10000.0,
            security_deposit=20000.0,
            status="ACTIVE",
        )
        db.add(old_resident)
        db.commit()
        old_user_id = old_user.id
        db.close()

        # Existing resident accesses /invoices/my -> works without requiring approval
        old_headers = make_auth_header(old_user_id, "RESIDENT", ctx["company_id"])
        res = client.get("/api/v1/invoices/my", headers=old_headers)
        assert res.status_code == 200


def setup_cross_property_fixtures(client, ctx):
    db = client.app.state.testing_session()
    room_p2 = Room(
        property_id=ctx["prop_2_id"],
        room_number="201",
        floor_number=2,
        room_type="SINGLE",
        max_occupancy=1,
    )
    db.add(room_p2)
    db.flush()
    bed_p2 = Bed(room_id=room_p2.id, bed_number="B201-1", status="AVAILABLE")
    db.add(bed_p2)
    db.commit()
    r2_id, b2_id = room_p2.id, bed_p2.id
    db.close()
    return r2_id, b2_id


def register_pending_resident(client, prop_id, phone, full_name="Pending Resident"):
    client.post("/api/v1/auth/resident/register/otp/request", json={"phone": phone})
    otp = DevMockSMSProvider.get_last_otp(phone)
    reg_res = client.post(
        "/api/v1/auth/resident/register",
        json={
            "phone": phone,
            "otp": otp,
            "full_name": full_name,
            "password": "Password@123",
            "property_id": str(prop_id),
        },
    )
    assert reg_res.status_code == 201
    return reg_res.json()["data"]["resident_id"]


class TestCrossPropertyAndConcurrencySafety:
    def test_cross_property_bed_omitted_room_rejected(self, client):
        ctx = seed_approval_test_context(client.app.state.testing_session)
        room_p2_id, bed_p2_id = setup_cross_property_fixtures(client, ctx)
        res_id = register_pending_resident(client, ctx["prop_1_id"], "9876590001")

        admin_headers = make_auth_header(ctx["admin_user_id"], "PROPERTY_MANAGER", ctx["company_id"])
        response = client.post(
            f"/api/v1/residents/{res_id}/approve",
            json={"bed_id": str(bed_p2_id)},  # room_id omitted
            headers=admin_headers,
        )
        assert response.status_code == 400
        assert "does not belong to this property" in get_error_message(response).lower()

    def test_cross_property_bed_supplied_room_rejected(self, client):
        ctx = seed_approval_test_context(client.app.state.testing_session)
        room_p2_id, bed_p2_id = setup_cross_property_fixtures(client, ctx)
        res_id = register_pending_resident(client, ctx["prop_1_id"], "9876590002")

        admin_headers = make_auth_header(ctx["admin_user_id"], "PROPERTY_MANAGER", ctx["company_id"])
        response = client.post(
            f"/api/v1/residents/{res_id}/approve",
            json={"room_id": str(ctx["room_id"]), "bed_id": str(bed_p2_id)},
            headers=admin_headers,
        )
        assert response.status_code == 400
        err = get_error_message(response).lower()
        assert "does not belong" in err

    def test_bed_and_room_from_different_properties_rejected(self, client):
        ctx = seed_approval_test_context(client.app.state.testing_session)
        room_p2_id, bed_p2_id = setup_cross_property_fixtures(client, ctx)
        res_id = register_pending_resident(client, ctx["prop_1_id"], "9876590003")

        admin_headers = make_auth_header(ctx["admin_user_id"], "PROPERTY_MANAGER", ctx["company_id"])
        # Pass room from prop_2 and bed from prop_1
        response = client.post(
            f"/api/v1/residents/{res_id}/approve",
            json={"room_id": str(room_p2_id), "bed_id": str(ctx["bed_1_id"])},
            headers=admin_headers,
        )
        assert response.status_code == 400
        err = get_error_message(response).lower()
        assert "does not belong" in err

    def test_valid_bed_allocation_with_room_supplied_succeeds(self, client):
        ctx = seed_approval_test_context(client.app.state.testing_session)
        res_id = register_pending_resident(client, ctx["prop_1_id"], "9876590004")

        admin_headers = make_auth_header(ctx["admin_user_id"], "PROPERTY_MANAGER", ctx["company_id"])
        response = client.post(
            f"/api/v1/residents/{res_id}/approve",
            json={"room_id": str(ctx["room_id"]), "bed_id": str(ctx["bed_1_id"])},
            headers=admin_headers,
        )
        assert response.status_code == 200
        data = response.json()["data"]
        assert data["status"] == "ACTIVE"
        assert data["room_id"] == str(ctx["room_id"])
        assert data["bed_id"] == str(ctx["bed_1_id"])

        db = client.app.state.testing_session()
        res_db = db.get(Resident, uuid.UUID(res_id))
        assert res_db.status == "ACTIVE"
        assert res_db.room_id == ctx["room_id"]
        assert res_db.bed_id == ctx["bed_1_id"]
        bed_db = db.get(Bed, ctx["bed_1_id"])
        assert bed_db.status == "OCCUPIED"
        db.close()

    def test_valid_bed_allocation_with_room_omitted_syncs_room(self, client):
        ctx = seed_approval_test_context(client.app.state.testing_session)
        res_id = register_pending_resident(client, ctx["prop_1_id"], "9876590005")

        admin_headers = make_auth_header(ctx["admin_user_id"], "PROPERTY_MANAGER", ctx["company_id"])
        response = client.post(
            f"/api/v1/residents/{res_id}/approve",
            json={"bed_id": str(ctx["bed_2_id"])},  # room_id omitted
            headers=admin_headers,
        )
        assert response.status_code == 200
        data = response.json()["data"]
        assert data["status"] == "ACTIVE"
        assert data["bed_id"] == str(ctx["bed_2_id"])
        assert data["room_id"] == str(ctx["room_id"])

        db = client.app.state.testing_session()
        res_db = db.get(Resident, uuid.UUID(res_id))
        assert res_db.room_id == ctx["room_id"]
        assert res_db.bed_id == ctx["bed_2_id"]
        bed_db = db.get(Bed, ctx["bed_2_id"])
        assert bed_db.status == "OCCUPIED"
        db.close()

    def test_room_only_allocation_preserves_behavior(self, client):
        ctx = seed_approval_test_context(client.app.state.testing_session)
        res_id = register_pending_resident(client, ctx["prop_1_id"], "9876590006")

        admin_headers = make_auth_header(ctx["admin_user_id"], "PROPERTY_MANAGER", ctx["company_id"])
        response = client.post(
            f"/api/v1/residents/{res_id}/approve",
            json={"room_id": str(ctx["room_id"])},  # No bed_id
            headers=admin_headers,
        )
        assert response.status_code == 200
        data = response.json()["data"]
        assert data["status"] == "ACTIVE"
        assert data["room_id"] == str(ctx["room_id"])
        assert data["bed_id"] is None

        db = client.app.state.testing_session()
        bed_1 = db.get(Bed, ctx["bed_1_id"])
        assert bed_1.status == "AVAILABLE"
        db.close()

    def test_nonexistent_bed_rejected(self, client):
        ctx = seed_approval_test_context(client.app.state.testing_session)
        res_id = register_pending_resident(client, ctx["prop_1_id"], "9876590007")

        admin_headers = make_auth_header(ctx["admin_user_id"], "PROPERTY_MANAGER", ctx["company_id"])
        response = client.post(
            f"/api/v1/residents/{res_id}/approve",
            json={"bed_id": str(uuid.uuid4())},
            headers=admin_headers,
        )
        assert response.status_code == 404
        assert "not found" in get_error_message(response).lower()

    def test_nonexistent_room_rejected(self, client):
        ctx = seed_approval_test_context(client.app.state.testing_session)
        res_id = register_pending_resident(client, ctx["prop_1_id"], "9876590008")

        admin_headers = make_auth_header(ctx["admin_user_id"], "PROPERTY_MANAGER", ctx["company_id"])
        response = client.post(
            f"/api/v1/residents/{res_id}/approve",
            json={"room_id": str(uuid.uuid4())},
            headers=admin_headers,
        )
        assert response.status_code == 404
        assert "not found" in get_error_message(response).lower()

    def test_two_residents_competing_for_same_bed(self, client):
        ctx = seed_approval_test_context(client.app.state.testing_session)
        res_a_id = register_pending_resident(client, ctx["prop_1_id"], "9876590011", "Resident One")
        res_b_id = register_pending_resident(client, ctx["prop_1_id"], "9876590012", "Resident Two")

        admin_headers = make_auth_header(ctx["admin_user_id"], "PROPERTY_MANAGER", ctx["company_id"])
        res_1 = client.post(
            f"/api/v1/residents/{res_a_id}/approve",
            json={"bed_id": str(ctx["bed_1_id"])},
            headers=admin_headers,
        )
        assert res_1.status_code == 200

        res_2 = client.post(
            f"/api/v1/residents/{res_b_id}/approve",
            json={"bed_id": str(ctx["bed_1_id"])},
            headers=admin_headers,
        )
        assert res_2.status_code == 409
        assert "already occupied" in get_error_message(res_2).lower()

    def test_duplicate_user_allocation_rejected_safely(self, client, monkeypatch):
        ctx = seed_approval_test_context(client.app.state.testing_session)
        res_id = register_pending_resident(client, ctx["prop_1_id"], "9876590013")
        admin_headers = make_auth_header(ctx["admin_user_id"], "PROPERTY_MANAGER", ctx["company_id"])

        def mock_commit(self):
            raise sa.exc.IntegrityError(
                statement="UPDATE residents SET user_id=...",
                params={},
                orig=Exception("duplicate key value violates unique constraint \"ix_residents_user_id\""),
            )

        monkeypatch.setattr(sa.orm.Session, "commit", mock_commit)
        res = client.post(
            f"/api/v1/residents/{res_id}/approve",
            json={"bed_id": str(ctx["bed_1_id"])},
            headers=admin_headers,
        )
        assert res.status_code == 409
        assert "already active or assigned" in get_error_message(res).lower()

    def test_failed_approval_leaves_no_partial_updates(self, client):
        ctx = seed_approval_test_context(client.app.state.testing_session)
        room_p2_id, bed_p2_id = setup_cross_property_fixtures(client, ctx)
        res_id = register_pending_resident(client, ctx["prop_1_id"], "9876590014")

        admin_headers = make_auth_header(ctx["admin_user_id"], "PROPERTY_MANAGER", ctx["company_id"])
        res = client.post(
            f"/api/v1/residents/{res_id}/approve",
            json={"bed_id": str(bed_p2_id)},
            headers=admin_headers,
        )
        assert res.status_code == 400

        db = client.app.state.testing_session()
        res_db = db.get(Resident, uuid.UUID(res_id))
        assert res_db.status == "PENDING_APPROVAL"
        assert res_db.room_id is None
        assert res_db.bed_id is None
        user_db = db.get(User, res_db.user_id)
        assert user_db.approval_status == "PENDING_APPROVAL"
        assert user_db.is_active is True

        bed_p2_db = db.get(Bed, bed_p2_id)
        assert bed_p2_db.status == "AVAILABLE"
        db.close()

