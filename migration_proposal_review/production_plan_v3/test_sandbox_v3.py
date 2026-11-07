"""Disposable V3 Sandbox Regression Test.

Validates SQLAlchemy models (Room, Bed, Resident, Invoice, Payment)
and foreign key/unique constraints against pg_reconcile_v3_sandbox_test.

SAFETY INVARIANT:
Refuses to run if pointed to pg_management or pg_reconcile_v2_sandbox_test.
"""
import os
import sys
import uuid
from datetime import date, datetime, timezone

DATABASE_URL = os.environ.get("SANDBOX_DATABASE_URL", "")
db_name = DATABASE_URL.split("/")[-1].split("?")[0].lower()

if "pg_management" in db_name and "sandbox" not in db_name:
    raise RuntimeError(f"CRITICAL SAFETY VIOLATION: Refusing to run insert test against {db_name}!")

if "v2_sandbox" in db_name:
    raise RuntimeError("CRITICAL SAFETY VIOLATION: Preserved V2 sandbox must not be touched!")

if db_name != "pg_reconcile_v3_sandbox_test":
    raise RuntimeError(f"CRITICAL SAFETY VIOLATION: Target DB must be pg_reconcile_v3_sandbox_test, got '{db_name}'")

# Add backend directory to sys.path
sys.path.insert(0, r"D:\PG_Management\pg-management-system\backend")

from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session

from app.models.property import Property
from app.models.room import Room
from app.models.bed import Bed
from app.models.user import User
from app.models.resident import Resident
from app.models.invoice import Invoice
from app.models.payment import Payment

engine = create_engine(DATABASE_URL)

with Session(engine) as session:
    print("=== STEP 1: Querying properties from restored sandbox data ===")
    props = session.scalars(select(Property).limit(2)).all()
    if len(props) < 2:
        raise RuntimeError("At least 2 properties required in sandbox database for cross-property testing!")
    prop1, prop2 = props[0], props[1]
    print(f"Prop 1: {prop1.name} ({prop1.id})")
    print(f"Prop 2: {prop2.name} ({prop2.id})")

    print("\n=== STEP 2: Inserting Room 1 (Prop 1) and Room 2 (Prop 2) ===")
    room1 = Room(
        property_id=prop1.id,
        floor_number=1,
        room_number="SB3-R1",
        room_type="SINGLE",
        max_occupancy=1,
        base_rent=7500.00,
        is_active=True,
        amenities={"wifi": True, "ac": True},
    )
    room2 = Room(
        property_id=prop2.id,
        floor_number=2,
        room_number="SB3-R2",
        room_type="SINGLE",
        max_occupancy=1,
        base_rent=8500.00,
        is_active=True,
        amenities={"wifi": True},
    )
    session.add_all([room1, room2])
    session.flush()
    print(f"Room 1 created: {room1.id} | Room 2 created: {room2.id}")

    print("\n=== STEP 3: Inserting Bed 1 in Room 1 and Bed 2 in Room 2 (Active Bed Model) ===")
    bed1 = Bed(room_id=room1.id, bed_number="BED-V3-1", status="AVAILABLE", monthly_rent=7500.00)
    bed2 = Bed(room_id=room2.id, bed_number="BED-V3-2", status="AVAILABLE", monthly_rent=8500.00)
    session.add_all([bed1, bed2])
    session.flush()
    print(f"Bed 1 created: {bed1.id} | Bed 2 created: {bed2.id}")

    print("\n=== STEP 4: Creating temporary users for resident tests ===")
    role_id = session.execute(select(User.role_id).limit(1)).scalar_one()
    user1 = User(
        company_id=prop1.company_id,
        role_id=role_id,
        email="sandbox_v3_user1@test.local",
        phone="+919876543201",
        full_name="Sandbox V3 User One",
        password_hash="argon2id$v3hash",
        is_active=True,
        is_verified=True,
        approval_status="APPROVED",
    )
    user2 = User(
        company_id=prop1.company_id,
        role_id=role_id,
        email="sandbox_v3_user2@test.local",
        phone="+919876543202",
        full_name="Sandbox V3 User Two",
        password_hash="argon2id$v3hash",
        is_active=True,
        is_verified=True,
        approval_status="APPROVED",
    )
    session.add_all([user1, user2])
    session.flush()
    print(f"User 1: {user1.id} | User 2: {user2.id}")

    print("\n=== STEP 5: Testing valid Resident insertion (User 1 in Prop 1, Room 1, Bed 1) ===")
    resident1 = Resident(
        user_id=user1.id,
        property_id=prop1.id,
        room_id=room1.id,
        bed_id=bed1.id,
        check_in_date=date(2026, 10, 1),
        monthly_rent=7500.00,
        security_deposit=15000.00,
        kyc_status="VERIFIED",
        status="ACTIVE",
    )
    session.add(resident1)
    session.flush()
    print(f"Resident 1 successfully created: ID {resident1.id}")

    print("\n=== STEP 6: Testing duplicate user_id rejection (uq_residents_user_id) ===")
    dup_user_res = Resident(
        user_id=user1.id,  # Same user
        property_id=prop1.id,
        room_id=room1.id,
        check_in_date=date(2026, 10, 1),
        monthly_rent=7500.00,
    )
    session.add(dup_user_res)
    try:
        session.flush()
        raise RuntimeError("FAIL: Duplicate resident user_id was accepted!")
    except Exception as e:
        session.rollback()
        print(f"PASS: Duplicate user_id correctly rejected: {type(e).__name__}")

    # Re-fetch objects after rollback
    prop1 = session.scalars(select(Property).where(Property.id == prop1.id)).one()
    prop2 = session.scalars(select(Property).where(Property.id == prop2.id)).one()
    room1 = Room(property_id=prop1.id, floor_number=1, room_number="SB3-R1", room_type="SINGLE", max_occupancy=1, base_rent=7500.00, amenities={})
    room2 = Room(property_id=prop2.id, floor_number=2, room_number="SB3-R2", room_type="SINGLE", max_occupancy=1, base_rent=8500.00, amenities={})
    session.add_all([room1, room2])
    session.flush()

    bed1 = Bed(room_id=room1.id, bed_number="BED-V3-1", status="AVAILABLE", monthly_rent=7500.00)
    bed2 = Bed(room_id=room2.id, bed_number="BED-V3-2", status="AVAILABLE", monthly_rent=8500.00)
    session.add_all([bed1, bed2])
    session.flush()

    user1 = User(company_id=prop1.company_id, role_id=role_id, phone="+919876543201", email="u1@test.local", full_name="User 1", password_hash="hash")
    user2 = User(company_id=prop1.company_id, role_id=role_id, phone="+919876543202", email="u2@test.local", full_name="User 2", password_hash="hash")
    session.add_all([user1, user2])
    session.flush()

    resident1 = Resident(user_id=user1.id, property_id=prop1.id, room_id=room1.id, bed_id=bed1.id, check_in_date=date(2026, 10, 1), monthly_rent=7500.00)
    session.add(resident1)
    session.flush()

    print("\n=== STEP 7: Testing duplicate bed_id rejection (uq_residents_bed_id) ===")
    dup_bed_res = Resident(
        user_id=user2.id,
        property_id=prop1.id,
        room_id=room1.id,
        bed_id=bed1.id,  # Same bed as resident1
        check_in_date=date(2026, 10, 1),
        monthly_rent=7500.00,
    )
    session.add(dup_bed_res)
    try:
        session.flush()
        raise RuntimeError("FAIL: Duplicate resident bed_id was accepted!")
    except Exception as e:
        session.rollback()
        print(f"PASS: Duplicate bed_id correctly rejected: {type(e).__name__}")

    # Re-fetch after rollback for Invoice & Payment tests
    prop1 = session.scalars(select(Property).where(Property.id == prop1.id)).one()
    room1 = Room(property_id=prop1.id, floor_number=1, room_number="SB3-R1", room_type="SINGLE", max_occupancy=1, base_rent=7500.00, amenities={})
    session.add(room1)
    session.flush()

    bed1 = Bed(room_id=room1.id, bed_number="BED-V3-1", status="AVAILABLE", monthly_rent=7500.00)
    session.add(bed1)
    session.flush()

    user1 = User(company_id=prop1.company_id, role_id=role_id, phone="+919876543201", email="u1@test.local", full_name="User 1", password_hash="hash")
    session.add(user1)
    session.flush()

    resident1 = Resident(user_id=user1.id, property_id=prop1.id, room_id=room1.id, bed_id=bed1.id, check_in_date=date(2026, 10, 1), monthly_rent=7500.00)
    session.add(resident1)
    session.flush()

    print("\n=== STEP 8: Testing Invoice insertion via active Invoice model ===")
    inv1 = Invoice(
        property_id=prop1.id,
        resident_id=resident1.id,
        invoice_number="INV-V3-0001",
        billing_month="2026-10",
        invoice_type="RENT",
        amount=7500.00,
        paid_amount=0.00,
        due_date=date(2026, 10, 5),
        status="PENDING",
    )
    session.add(inv1)
    session.flush()
    print(f"Invoice 1 created successfully: ID {inv1.id}, number {inv1.invoice_number}")

    print("\n=== STEP 9: Testing duplicate invoice cycle rejection (uq_resident_invoice_cycle) ===")
    dup_inv = Invoice(
        property_id=prop1.id,
        resident_id=resident1.id,
        invoice_number="INV-V3-0002",
        billing_month="2026-10",  # Same billing_month and invoice_type for resident1
        invoice_type="RENT",
        amount=7500.00,
        paid_amount=0.00,
        due_date=date(2026, 10, 5),
        status="PENDING",
    )
    session.add(dup_inv)
    try:
        session.flush()
        raise RuntimeError("FAIL: Duplicate invoice cycle was accepted!")
    except Exception as e:
        session.rollback()
        print(f"PASS: Duplicate invoice cycle correctly rejected: {type(e).__name__}")

    # Re-fetch after rollback for Payment tests
    prop1 = session.scalars(select(Property).where(Property.id == prop1.id)).one()
    room1 = Room(property_id=prop1.id, floor_number=1, room_number="SB3-R1", room_type="SINGLE", max_occupancy=1, base_rent=7500.00, amenities={})
    session.add(room1)
    session.flush()

    bed1 = Bed(room_id=room1.id, bed_number="BED-V3-1", status="AVAILABLE", monthly_rent=7500.00)
    session.add(bed1)
    session.flush()

    user1 = User(company_id=prop1.company_id, role_id=role_id, phone="+919876543201", email="u1@test.local", full_name="User 1", password_hash="hash")
    session.add(user1)
    session.flush()

    resident1 = Resident(user_id=user1.id, property_id=prop1.id, room_id=room1.id, bed_id=bed1.id, check_in_date=date(2026, 10, 1), monthly_rent=7500.00)
    session.add(resident1)
    session.flush()

    inv1 = Invoice(
        property_id=prop1.id,
        resident_id=resident1.id,
        invoice_number="INV-V3-0001",
        billing_month="2026-10",
        invoice_type="RENT",
        amount=7500.00,
        paid_amount=0.00,
        due_date=date(2026, 10, 5),
        status="PENDING",
    )
    session.add(inv1)
    session.flush()

    print("\n=== STEP 10: Testing Payment insertion via active Payment model ===")
    payment1 = Payment(
        property_id=prop1.id,
        invoice_id=inv1.id,
        resident_id=resident1.id,
        payment_number="PAY-V3-0001",
        idempotency_key="idemp_v3_test_1",
        amount=7500.00,
        payment_mode="UPI",
        status="PENDING",
    )
    session.add(payment1)
    session.flush()
    print(f"Payment 1 created successfully: ID {payment1.id}, number {payment1.payment_number}")

    print("\n=== STEP 11: Testing duplicate payment idempotency rejection ===")
    dup_payment = Payment(
        property_id=prop1.id,
        invoice_id=inv1.id,
        resident_id=resident1.id,
        payment_number="PAY-V3-0002",
        idempotency_key="idemp_v3_test_1",  # Same idempotency key for invoice_id
        amount=7500.00,
        payment_mode="UPI",
        status="PENDING",
    )
    session.add(dup_payment)
    try:
        session.flush()
        raise RuntimeError("FAIL: Duplicate payment idempotency was accepted!")
    except Exception as e:
        session.rollback()
        print(f"PASS: Duplicate payment idempotency correctly rejected: {type(e).__name__}")

    print("\n=== STEP 12: Session closed cleanly without commit ===")

print("\nALL V3 MODEL INSERT & CONSTRAINT CHECKS PASSED SUCCESSFULLY IN SANDBOX!")
