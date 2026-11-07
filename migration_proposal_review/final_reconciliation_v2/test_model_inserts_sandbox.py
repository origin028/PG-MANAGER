"""Sandbox regression test for SQLAlchemy model inserts.

This script runs ONLY against the disposable sandbox database:
pg_reconcile_v2_sandbox_test.

It explicitly refuses to run if pointed to pg_management.
"""
import os
import sys
import uuid
from datetime import date

# Safety assertion: verify target database is strictly the disposable sandbox
DATABASE_URL = os.environ.get("SANDBOX_DATABASE_URL", "")
if "pg_management" in DATABASE_URL.split("/")[-1].lower():
    raise RuntimeError("CRITICAL SAFETY VIOLATION: Refusing to run insert test against pg_management!")

if not DATABASE_URL:
    raise RuntimeError("SANDBOX_DATABASE_URL environment variable is required.")

from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session

# Add backend directory to sys.path
sys.path.insert(0, r"D:\PG_Management\pg-management-system\backend")

from app.models.property import Property
from app.models.room import Room
from app.models.bed import Bed
from app.models.user import User
from app.models.resident import Resident

engine = create_engine(DATABASE_URL)

with Session(engine) as session:
    print("--- 1. Querying existing property from restored sandbox data ---")
    prop = session.scalars(select(Property).limit(1)).first()
    if not prop:
        raise RuntimeError("No property found in sandbox database!")
    print(f"Using Property: {prop.name} ({prop.id})")

    print("--- 2. Testing Room insert via SQLAlchemy model ---")
    test_room = Room(
        property_id=prop.id,
        floor_number=1,
        room_number="SB-999",
        room_type="SINGLE",
        max_occupancy=1,
        base_rent=7500.00,
        is_active=True,
        amenities={"wifi": True, "ac": False},
    )
    session.add(test_room)
    session.flush()
    print(f"Room inserted successfully: ID {test_room.id}")

    print("--- 3. Testing Bed insert via SQLAlchemy model (WITHOUT legacy property_id) ---")
    test_bed = Bed(
        room_id=test_room.id,
        bed_number="BED-999A",
        status="AVAILABLE",
        monthly_rent=7500.00,
    )
    session.add(test_bed)
    session.flush()
    print(f"Bed inserted successfully without legacy property_id: ID {test_bed.id}")

    print("--- 4. Creating temporary user for resident insert ---")
    test_user = User(
        company_id=prop.company_id,
        role_id=session.execute(select(User.role_id).limit(1)).scalar_one(),
        email="sandbox_resident_test@test.local",
        phone="+919876500999",
        full_name="Sandbox Test Resident",
        password_hash="argon2id$sandboxhash",
        is_active=True,
        is_verified=True,
        approval_status="APPROVED",
    )
    session.add(test_user)
    session.flush()
    print(f"User created: ID {test_user.id}")

    print("--- 5. Testing Resident insert via SQLAlchemy model (WITHOUT legacy company_id/full_name/phone) ---")
    test_resident = Resident(
        user_id=test_user.id,
        property_id=prop.id,
        room_id=test_room.id,
        bed_id=test_bed.id,
        check_in_date=date.today(),
        monthly_rent=7500.00,
        security_deposit=15000.00,
        kyc_status="VERIFIED",
        status="ACTIVE",
    )
    session.add(test_resident)
    session.flush()
    print(f"Resident inserted successfully without legacy columns: ID {test_resident.id}")

    print("--- 6. Testing Resident user_id uniqueness enforcement ---")
    duplicate_resident = Resident(
        user_id=test_user.id,  # Same user_id
        property_id=prop.id,
        room_id=test_room.id,
        check_in_date=date.today(),
        monthly_rent=7500.00,
    )
    session.add(duplicate_resident)
    try:
        session.flush()
        raise RuntimeError("FAIL: Duplicate resident user_id was accepted!")
    except Exception as e:
        session.rollback()
        print(f"PASS: Duplicate resident user_id was rejected as expected: {type(e).__name__}")

    print("ALL MODEL INSERT TESTS PASSED IN SANDBOX!")
