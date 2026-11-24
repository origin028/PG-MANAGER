import uuid
from datetime import date, datetime, timezone
import pytest
import sqlalchemy as sa
from fastapi.testclient import TestClient

from app.core.security import create_access_token, get_password_hash
from app.models.property import Company, Property
from app.models.resident import Resident
from app.models.role import Role
from app.models.room import Room
from app.models.bed import Bed
from app.models.user import User


@pytest.fixture
def approval_setup(client: TestClient):
    """
    Sets up a multi-company test environment:
    - Company 1 ("ORIGIN") owns Property 1 ("Origin Comfort PG")
    - Company 2 ("NEW_ADMIN_CO") belongs to a new admin registered with Super Key
    - Super Admin user (company 2) has SUPER_ADMIN role
    - Property Manager user (company 2) has PROPERTY_MANAGER role
    - Staged pending resident registered under Property 1 (Company 1)
    """
    db_factory = client.app.state.testing_session
    with db_factory() as db_session:
        # 1. Create Roles
        super_admin_role = db_session.scalar(sa.select(Role).where(Role.name == "SUPER_ADMIN"))
        if not super_admin_role:
            super_admin_role = Role(name="SUPER_ADMIN", display_name="Super Admin", is_system_role=True, permissions=["*"])
            db_session.add(super_admin_role)

        pm_role = db_session.scalar(sa.select(Role).where(Role.name == "PROPERTY_MANAGER"))
        if not pm_role:
            pm_role = Role(name="PROPERTY_MANAGER", display_name="Property Manager", is_system_role=True, permissions=["*"])
            db_session.add(pm_role)

        resident_role = db_session.scalar(sa.select(Role).where(Role.name == "RESIDENT"))
        if not resident_role:
            resident_role = Role(name="RESIDENT", display_name="Resident", is_system_role=True, permissions=["profile:self"])
            db_session.add(resident_role)

        db_session.flush()

        # 2. Company 1 (Origin) & Property 1
        co_origin = Company(name="Origin PG Hospitality", code=f"ORIGIN_{uuid.uuid4().hex[:6].upper()}", is_active=True)
        db_session.add(co_origin)
        db_session.flush()

        prop_origin = Property(
            company_id=co_origin.id,
            name="Origin Comfort PG - Electronic City",
            code=f"PROP_{uuid.uuid4().hex[:4].upper()}",
            address_line1="Electronic City Phase 1",
            city="Bengaluru",
            state="Karnataka",
            pincode="560100",
            is_active=True,
        )
        db_session.add(prop_origin)
        db_session.flush()

        room = Room(property_id=prop_origin.id, room_number="101", floor_number=1, room_type="DOUBLE_SHARING")
        db_session.add(room)
        db_session.flush()

        bed = Bed(room_id=room.id, bed_number="101-A", status="AVAILABLE")
        db_session.add(bed)
        db_session.flush()

        # 3. Company 2 (New PG Owner registered with Super Key)
        co_admin = Company(name="Bangalore PG Enterprise", code=f"BLR_{uuid.uuid4().hex[:6].upper()}", is_active=True)
        db_session.add(co_admin)
        db_session.flush()

        # Owner (SUPER_ADMIN) of Company 1, which owns Property 1.
        super_admin = User(
            company_id=co_origin.id,
            role_id=super_admin_role.id,
            full_name="Platform Super Admin",
            email=f"superadmin_{uuid.uuid4().hex[:6]}@example.com",
            phone="9876500001",
            password_hash=get_password_hash("AdminPass123!"),
            is_active=True,
            is_verified=True,
            approval_status="APPROVED",
        )
        # Property Manager under Company 1 (Origin)
        manager = User(
            company_id=co_origin.id,
            role_id=pm_role.id,
            full_name="Origin PG Manager",
            email=f"manager_{uuid.uuid4().hex[:6]}@example.com",
            phone="9876500002",
            password_hash=get_password_hash("ManagerPass123!"),
            is_active=True,
            is_verified=True,
            approval_status="APPROVED",
        )
        # Unauthorized Property Manager under Company 2 (different company)
        manager_other = User(
            company_id=co_admin.id,
            role_id=pm_role.id,
            full_name="Other Company Manager",
            email=f"other_manager_{uuid.uuid4().hex[:6]}@example.com",
            phone="9876500003",
            password_hash=get_password_hash("OtherPass123!"),
            is_active=True,
            is_verified=True,
            approval_status="APPROVED",
        )
        # Owner (SUPER_ADMIN) of Company 2: must never see or act on Company 1's residents.
        other_owner = User(
            company_id=co_admin.id,
            role_id=super_admin_role.id,
            full_name="Other Company Owner",
            email=f"other_owner_{uuid.uuid4().hex[:6]}@example.com",
            phone="9876500004",
            password_hash=get_password_hash("OtherOwner123!"),
            is_active=True,
            is_verified=True,
            approval_status="APPROVED",
        )
        db_session.add_all([super_admin, manager, manager_other, other_owner])
        db_session.flush()

        # 4. Pending Resident registered for Property 1 (Company 1)
        res_user = User(
            company_id=co_origin.id,
            role_id=resident_role.id,
            full_name="Ananya Sharma",
            email=f"ananya_{uuid.uuid4().hex[:6]}@example.com",
            phone="9876543299",
            password_hash="!NO_PASSWORD",
            is_active=True,
            is_verified=True,
            approval_status="PENDING_APPROVAL",
        )
        db_session.add(res_user)
        db_session.flush()

        resident = Resident(
            user_id=res_user.id,
            property_id=prop_origin.id,
            date_of_birth=date(1999, 4, 12),
            gender="Female",
            occupation="Software Engineer",
            emergency_contact="Father - 9876543200",
            check_in_date=date(2026, 11, 23),
            monthly_rent=9000.0,
            security_deposit=18000.0,
            kyc_status="PENDING",
            status="PENDING_APPROVAL",
        )
        db_session.add(resident)
        db_session.commit()

        return {
            "co_origin_id": co_origin.id,
            "prop_origin_id": prop_origin.id,
            "prop_name": prop_origin.name,
            "room_id": room.id,
            "bed_id": bed.id,
            "co_admin_id": co_admin.id,
            "super_admin_id": super_admin.id,
            "super_admin_email": super_admin.email,
            "other_owner_id": other_owner.id,
            "other_owner_email": other_owner.email,
            "manager_id": manager.id,
            "manager_email": manager.email,
            "manager_other_id": manager_other.id,
            "manager_other_email": manager_other.email,
            "res_user_id": res_user.id,
            "resident_id": resident.id,
        }


def test_owner_cannot_view_pending_resident_approvals_of_another_company(client: TestClient, approval_setup):
    """An owner of one PG company must never see sign-ups waiting in another company's homes."""
    token = create_access_token(
        subject=str(approval_setup["other_owner_id"]),
        claims={
            "email": approval_setup["other_owner_email"],
            "role": "SUPER_ADMIN",
            "company_id": str(approval_setup["co_admin_id"]),
            "allowed_properties": ["*"],
        },
    )

    response = client.get(
        "/api/v1/residents/pending-approvals",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 200, response.text
    items = response.json()["data"]["items"]
    assert all(item["resident_id"] != str(approval_setup["resident_id"]) for item in items)


def test_property_manager_can_view_company_pending_approvals(client: TestClient, approval_setup):
    """Verifies that PROPERTY_MANAGER can view pending registrations for properties belonging to their company."""
    token = create_access_token(
        subject=str(approval_setup["manager_id"]),
        claims={
            "email": approval_setup["manager_email"],
            "role": "PROPERTY_MANAGER",
            "company_id": str(approval_setup["co_origin_id"]),
            "allowed_properties": ["*"],
        },
    )

    response = client.get(
        "/api/v1/residents/pending-approvals",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 200, response.text
    data = response.json()
    assert data["success"] is True
    items = data["data"]["items"]
    assert any(item["resident_id"] == str(approval_setup["resident_id"]) for item in items)


def test_unauthorized_property_manager_cannot_view_other_company_approvals(client: TestClient, approval_setup):
    """Verifies multi-tenancy: PROPERTY_MANAGER of Company B cannot see pending registrations for Company A."""
    token = create_access_token(
        subject=str(approval_setup["manager_other_id"]),
        claims={
            "email": approval_setup["manager_other_email"],
            "role": "PROPERTY_MANAGER",
            "company_id": str(approval_setup["co_admin_id"]),
            "allowed_properties": ["*"],
        },
    )

    response = client.get(
        "/api/v1/residents/pending-approvals",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 200, response.text
    data = response.json()
    assert data["success"] is True
    items = data["data"]["items"]
    # Must not contain Company A's pending resident!
    assert not any(item["resident_id"] == str(approval_setup["resident_id"]) for item in items)


def test_super_admin_can_approve_resident_and_it_disappears_from_pending(client: TestClient, approval_setup):
    """Verifies that approving a pending resident transitions state to ACTIVE and removes from pending list."""
    token = create_access_token(
        subject=str(approval_setup["super_admin_id"]),
        claims={
            "email": approval_setup["super_admin_email"],
            "role": "SUPER_ADMIN",
            "company_id": str(approval_setup["co_admin_id"]),
            "allowed_properties": ["*"],
        },
    )

    approve_payload = {
        "room_id": str(approval_setup["room_id"]),
        "bed_id": str(approval_setup["bed_id"]),
        "monthly_rent": 9500.0,
        "security_deposit": 19000.0,
        "check_in_date": "2026-11-25",
    }

    # 1. Call approve endpoint
    approve_res = client.post(
        f"/api/v1/residents/{approval_setup['resident_id']}/approve",
        headers={"Authorization": f"Bearer {token}"},
        json=approve_payload,
    )
    assert approve_res.status_code == 200, approve_res.text
    res_data = approve_res.json()
    assert res_data["success"] is True
    assert res_data["data"]["status"] == "ACTIVE"
    # No ID documents were uploaded, so approval keeps KYC pending and starts the KYC deadline.
    assert res_data["data"]["kyc_status"] == "PENDING"

    # 2. Verify in database
    db_factory = client.app.state.testing_session
    with db_factory() as db_session:
        updated_res = db_session.get(Resident, approval_setup["resident_id"])
        assert updated_res.status == "ACTIVE"
        assert updated_res.kyc_status == "PENDING" and updated_res.kyc_due_at is not None
        assert str(updated_res.bed_id) == str(approval_setup["bed_id"])

        updated_user = db_session.get(User, updated_res.user_id)
        assert updated_user.approval_status == "APPROVED"
        assert updated_user.is_active is True

    # 3. Verify it no longer appears in pending approvals
    list_res = client.get(
        "/api/v1/residents/pending-approvals",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert list_res.status_code == 200
    list_data = list_res.json()
    assert not any(item["resident_id"] == str(approval_setup["resident_id"]) for item in list_data["data"]["items"])


def test_reject_resident_registration_workflow(client: TestClient, approval_setup):
    """Verifies that rejecting a pending resident transitions state to REJECTED."""
    db_factory = client.app.state.testing_session
    with db_factory() as db_session:
        resident_role = db_session.scalar(sa.select(Role).where(Role.name == "RESIDENT"))
        rej_user = User(
            company_id=approval_setup["co_origin_id"],
            role_id=resident_role.id,
            full_name="Rahul Verma",
            email=f"rahul_{uuid.uuid4().hex[:6]}@example.com",
            phone="9876543288",
            password_hash="!NO_PASSWORD",
            is_active=True,
            is_verified=True,
            approval_status="PENDING_APPROVAL",
        )
        db_session.add(rej_user)
        db_session.flush()

        rej_resident = Resident(
            user_id=rej_user.id,
            property_id=approval_setup["prop_origin_id"],
            check_in_date=date(2026, 11, 23),
            status="PENDING_APPROVAL",
            kyc_status="PENDING",
        )
        db_session.add(rej_resident)
        db_session.commit()
        rej_resident_id = rej_resident.id
        rej_user_id = rej_user.id

    token = create_access_token(
        subject=str(approval_setup["super_admin_id"]),
        claims={
            "email": approval_setup["super_admin_email"],
            "role": "SUPER_ADMIN",
            "company_id": str(approval_setup["co_admin_id"]),
            "allowed_properties": ["*"],
        },
    )

    reject_res = client.post(
        f"/api/v1/residents/{rej_resident_id}/reject",
        headers={"Authorization": f"Bearer {token}"},
        json={"reason": "Incomplete Aadhaar card image submitted."},
    )
    assert reject_res.status_code == 200, reject_res.text
    data = reject_res.json()
    assert data["success"] is True

    with db_factory() as db_session:
        updated_rej = db_session.get(Resident, rej_resident_id)
        assert updated_rej.status == "REJECTED"
        assert updated_rej.kyc_status == "REJECTED"
        assert updated_rej.kyc_notes == "Incomplete Aadhaar card image submitted."

        updated_u = db_session.get(User, rej_user_id)
        assert updated_u.approval_status == "REJECTED"
        assert updated_u.is_active is False
