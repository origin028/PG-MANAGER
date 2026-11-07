"""PostgreSQL Resident Allocation Concurrency and Row-Locking Integration Tests.

Verifies real PostgreSQL concurrency semantics for Resident bed allocation:
- Row-level locking (with_for_update) on Bed
- Simultaneous competing resident allocation requests for the same bed
- Database unique constraint (ix_residents_bed_id) enforcement under concurrency
- Duplicate user allocation conflict handling (ix_residents_user_id)
- Atomic rollback leaving zero partial state updates

SAFETY ENFORCED:
- Runs strictly on disposable temporary PostgreSQL databases created and dropped per test run.
- Refuses to connect if TEST_DATABASE_URL points to protected databases ('pg_management', etc.).
- Completely isolated from live pg_management and sandbox baselines.
"""

import concurrent.futures
import logging
import os
import threading
import uuid
from datetime import date
from urllib.parse import urlparse

import psycopg
import pytest
import sqlalchemy as sa
from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.api.v1.endpoints.residents import approve_resident_registration
from app.core.config import settings
from app.core.exceptions import BadRequestError, ConflictError, NotFoundError
from app.models.bed import Bed
from app.models.property import Company, Property
from app.models.resident import Resident
from app.models.role import Role
from app.models.room import Room
from app.models.user import User, UserPropertyAccess
from app.schemas.resident_registration import ResidentApprovalActionRequest

TEST_DB_URL_ENV = os.environ.get("TEST_DATABASE_URL")

pytestmark = pytest.mark.skipif(
    not TEST_DB_URL_ENV,
    reason="PostgreSQL integration tests require TEST_DATABASE_URL environment variable.",
)


def is_safe_test_url(url: str) -> bool:
    parsed = urlparse(url)
    db_name = parsed.path.lstrip("/").lower()
    protected = {"pg_management", "postgres", "production", "prod", "master", "main"}
    if db_name in protected or not db_name:
        return False
    return True


@pytest.fixture(scope="session")
def postgres_resident_conc_engine():
    raw_url = os.environ.get("TEST_DATABASE_URL", "").strip()
    if not is_safe_test_url(raw_url):
        raise ValueError(
            f"TEST_DATABASE_URL='{raw_url}' is not a safe disposable database name."
        )

    parsed = urlparse(raw_url)
    admin_dsn = f"postgresql://{parsed.username}:{parsed.password}@{parsed.hostname}:{parsed.port or 5432}/postgres"
    disposable_db_name = f"test_res_conc_{uuid.uuid4().hex[:10]}"

    admin_conn = psycopg.connect(admin_dsn, autocommit=True)
    admin_conn.execute(f"CREATE DATABASE {disposable_db_name}")

    test_db_url = (
        f"postgresql+psycopg://{parsed.username}:{parsed.password}@"
        f"{parsed.hostname}:{parsed.port or 5432}/{disposable_db_name}"
    )

    engine = create_engine(test_db_url, pool_size=10, max_overflow=20)

    orig_db_url = settings.DATABASE_URL
    settings.DATABASE_URL = test_db_url
    alembic_cfg = Config("alembic.ini")
    command.upgrade(alembic_cfg, "head")

    # Re-enable any loggers disabled by alembic fileConfig
    for name in list(logging.root.manager.loggerDict.keys()):
        log_obj = logging.getLogger(name)
        if hasattr(log_obj, "disabled"):
            log_obj.disabled = False

    try:
        yield engine
    finally:
        engine.dispose()
        settings.DATABASE_URL = orig_db_url
        admin_conn.execute(
            f"SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '{disposable_db_name}'"
        )
        admin_conn.execute(f"DROP DATABASE {disposable_db_name}")
        admin_conn.close()


@pytest.fixture
def pg_session_factory(postgres_resident_conc_engine):
    return sessionmaker(bind=postgres_resident_conc_engine, autocommit=False, autoflush=False)


def seed_resident_concurrency_context(session_factory):
    db = session_factory()
    try:
        company = Company(name="PG Conc Resident Co", code=f"RC_{uuid.uuid4().hex[:4]}")
        db.add(company)
        db.flush()

        admin_role = db.scalar(sa.select(Role).where(Role.name == "PROPERTY_MANAGER"))
        if not admin_role:
            admin_role = Role(name="PROPERTY_MANAGER", display_name="Property Manager")
            db.add(admin_role)

        res_role = db.scalar(sa.select(Role).where(Role.name == "RESIDENT"))
        if not res_role:
            res_role = Role(name="RESIDENT", display_name="Resident")
            db.add(res_role)
        db.flush()

        prop = Property(
            company_id=company.id,
            name="PG Concurrency Tower",
            code=f"PROP_{uuid.uuid4().hex[:4]}",
            address_line1="456 Concurrency Blvd",
            pincode="560001",
        )
        db.add(prop)
        db.flush()

        admin_user = User(
            company_id=company.id,
            role_id=admin_role.id,
            phone=f"91{uuid.uuid4().int % 100000000:08d}",
            full_name="Admin Manager",
            password_hash="pwd_hash",
            is_active=True,
            approval_status="APPROVED",
        )
        db.add(admin_user)
        db.flush()

        db.add(UserPropertyAccess(user_id=admin_user.id, property_id=prop.id, access_level="MANAGER"))

        room = Room(property_id=prop.id, room_number="301", floor_number=3, max_occupancy=2)
        db.add(room)
        db.flush()

        bed = Bed(room_id=room.id, bed_number="B-CONC-1", status="AVAILABLE", monthly_rent=6000.00)
        db.add(bed)
        db.flush()

        # Create two separate pending residents competing for bed
        user1 = User(
            company_id=company.id,
            role_id=res_role.id,
            phone=f"93{uuid.uuid4().int % 100000000:08d}",
            full_name="Resident Competitor One",
            password_hash="pwd_hash",
            is_active=False,
            approval_status="PENDING_APPROVAL",
        )
        user2 = User(
            company_id=company.id,
            role_id=res_role.id,
            phone=f"94{uuid.uuid4().int % 100000000:08d}",
            full_name="Resident Competitor Two",
            password_hash="pwd_hash",
            is_active=False,
            approval_status="PENDING_APPROVAL",
        )
        db.add_all([user1, user2])
        db.flush()

        res1 = Resident(
            user_id=user1.id,
            property_id=prop.id,
            room_id=None,
            bed_id=None,
            status="PENDING_APPROVAL",
            check_in_date=date.today(),
            monthly_rent=6000.00,
        )
        res2 = Resident(
            user_id=user2.id,
            property_id=prop.id,
            room_id=None,
            bed_id=None,
            status="PENDING_APPROVAL",
            check_in_date=date.today(),
            monthly_rent=6000.00,
        )
        db.add_all([res1, res2])
        db.commit()

        ctx = {
            "company_id": company.id,
            "property_id": prop.id,
            "admin_user_id": admin_user.id,
            "room_id": room.id,
            "bed_id": bed.id,
            "user1_id": user1.id,
            "user2_id": user2.id,
            "res1_id": res1.id,
            "res2_id": res2.id,
        }
        return ctx
    finally:
        db.close()


def test_pg_simultaneous_bed_allocation_requests_competing_for_same_bed(pg_session_factory):
    """
    Real PostgreSQL concurrency test:
    Two concurrent worker threads attempt to allocate the exact same Bed to two different residents.
    Verifies:
      - PostgreSQL row-level locking (with_for_update) serializes the requests
      - Exactly ONE request succeeds (HTTP 200 response)
      - The competing request receives ConflictError (HTTP 409)
      - No unhandled HTTP 500 occurs
      - Exactly ONE resident is allocated the bed in PostgreSQL
      - Bed status transitions to OCCUPIED and resident assignments remain consistent
    """
    ctx = seed_resident_concurrency_context(pg_session_factory)
    bed_id = ctx["bed_id"]
    res1_id = ctx["res1_id"]
    res2_id = ctx["res2_id"]
    admin_id = ctx["admin_user_id"]

    barrier = threading.Barrier(2)
    results = []

    def attempt_approval(thread_idx, resident_id):
        db = pg_session_factory()
        admin_user = db.get(User, admin_id)
        payload = ResidentApprovalActionRequest(bed_id=bed_id)
        barrier.wait()  # Fire simultaneously
        try:
            resp = approve_resident_registration(
                resident_id=resident_id,
                payload=payload,
                current_user=admin_user,
                db=db,
            )
            results.append((thread_idx, True, 200, resp.data.id))
        except ConflictError as ce:
            results.append((thread_idx, False, 409, str(ce)))
        except Exception as exc:
            results.append((thread_idx, False, 500, f"UNHANDLED: {type(exc).__name__}: {str(exc)}"))
        finally:
            db.close()

    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
        f1 = executor.submit(attempt_approval, 1, res1_id)
        f2 = executor.submit(attempt_approval, 2, res2_id)
        f1.result()
        f2.result()

    successes = [r for r in results if r[1] is True]
    conflicts = [r for r in results if r[2] == 409]
    errors = [r for r in results if r[2] == 500]

    # Exactly one must succeed and exactly one must receive 409 Conflict
    assert len(errors) == 0, f"Encountered unhandled 500 errors: {errors}"
    assert len(successes) == 1, f"Expected 1 success, got {len(successes)}: {results}"
    assert len(conflicts) == 1, f"Expected 1 409 conflict, got {len(conflicts)}: {results}"
    assert "already occupied by another active resident" in conflicts[0][3]

    # Verify actual PostgreSQL database state
    db = pg_session_factory()
    # 1. Exactly one resident holds this bed_id
    assigned_residents = db.query(Resident).filter_by(bed_id=bed_id).all()
    assert len(assigned_residents) == 1
    winning_resident = assigned_residents[0]

    # 2. Bed status is OCCUPIED
    bed_db = db.get(Bed, bed_id)
    assert bed_db.status == "OCCUPIED"

    # 3. Winning resident is ACTIVE and room_id is synchronized
    assert winning_resident.status == "ACTIVE"
    assert winning_resident.room_id == bed_db.room_id
    winning_user = db.get(User, winning_resident.user_id)
    assert winning_user.approval_status == "APPROVED"
    assert winning_user.is_active is True

    # 4. Losing resident remains PENDING_APPROVAL with no bed or room assigned
    losing_res_id = res2_id if winning_resident.id == res1_id else res1_id
    losing_resident = db.get(Resident, losing_res_id)
    assert losing_resident.status == "PENDING_APPROVAL"
    assert losing_resident.bed_id is None
    assert losing_resident.room_id is None
    losing_user = db.get(User, losing_resident.user_id)
    assert losing_user.approval_status == "PENDING_APPROVAL"
    assert losing_user.is_active is False
    db.close()


def test_pg_duplicate_user_allocation_rejected_safely(pg_session_factory):
    """
    Verifies that attempting to allocate a resident when the user already has an active
    resident profile triggers unique constraint ix_residents_user_id and returns clean HTTP 409.
    """
    ctx = seed_resident_concurrency_context(pg_session_factory)
    db = pg_session_factory()

    # First approve Resident 1
    admin_user = db.get(User, ctx["admin_user_id"])
    approve_resident_registration(
        resident_id=ctx["res1_id"],
        payload=ResidentApprovalActionRequest(bed_id=ctx["bed_id"]),
        current_user=admin_user,
        db=db,
    )
    db.close()

    # In a second transaction, Resident 2 is updated to collide with User 1's user_id
    db2 = pg_session_factory()
    admin_user2 = db2.get(User, ctx["admin_user_id"])
    res2 = db2.get(Resident, ctx["res2_id"])
    # Create a secondary bed for Resident 2 so bed is not the conflict
    bed2 = Bed(room_id=ctx["room_id"], bed_number="B-CONC-2", status="AVAILABLE", monthly_rent=6000.00)
    db2.add(bed2)
    db2.flush()

    res2.user_id = ctx["user1_id"]  # Collide with existing approved user

    with pytest.raises(ConflictError) as exc_info:
        approve_resident_registration(
            resident_id=res2.id,
            payload=ResidentApprovalActionRequest(bed_id=bed2.id),
            current_user=admin_user2,
            db=db2,
        )

    assert "already active or assigned" in str(exc_info.value).lower()
    db2.close()


def test_pg_failed_approval_leaves_no_partial_updates(pg_session_factory):
    """
    Verifies that when an approval request fails on PostgreSQL (e.g. cross-property violation),
    transaction rollback leaves zero partial modifications in PostgreSQL.
    """
    ctx = seed_resident_concurrency_context(pg_session_factory)
    db = pg_session_factory()

    # Create a separate property and bed
    foreign_prop = Property(
        company_id=ctx["company_id"],
        name="Foreign PG",
        code=f"FP_{uuid.uuid4().hex[:4]}",
        address_line1="999 Foreign St",
        pincode="560002",
    )
    db.add(foreign_prop)
    db.flush()

    foreign_room = Room(property_id=foreign_prop.id, room_number="901")
    db.add(foreign_room)
    db.flush()

    foreign_bed = Bed(room_id=foreign_room.id, bed_number="F-BED-1", status="AVAILABLE")
    db.add(foreign_bed)
    db.commit()

    admin_user = db.get(User, ctx["admin_user_id"])

    # Attempt cross-property bed allocation
    with pytest.raises(BadRequestError) as exc_info:
        approve_resident_registration(
            resident_id=ctx["res1_id"],
            payload=ResidentApprovalActionRequest(bed_id=foreign_bed.id),
            current_user=admin_user,
            db=db,
        )

    assert "does not belong to this property" in str(exc_info.value).lower()
    db.close()

    # Confirm PostgreSQL state is pristine
    db_verify = pg_session_factory()
    res1 = db_verify.get(Resident, ctx["res1_id"])
    assert res1.status == "PENDING_APPROVAL"
    assert res1.bed_id is None
    assert res1.room_id is None

    user1 = db_verify.get(User, ctx["user1_id"])
    assert user1.approval_status == "PENDING_APPROVAL"
    assert user1.is_active is False

    bed_f = db_verify.get(Bed, foreign_bed.id)
    assert bed_f.status == "AVAILABLE"
    db_verify.close()
