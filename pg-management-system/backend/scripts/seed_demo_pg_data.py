import sys
import os
from datetime import date, datetime, timedelta
from decimal import Decimal

# Add backend directory to sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.core.logging import logger, setup_logging
from app.core.security import get_password_hash
from app.db.base import Base
from app.db.session import engine, SessionLocal
from app.models.property import Company, Property
from app.models.role import Role
from app.models.user import User
from app.models.room import Room
from app.models.bed import Bed
from app.models.resident import Resident
from app.models.invoice import Invoice
from app.models.notice import Notice
from app.models.food_menu import FoodMenu
from app.models.complaint import Complaint


def seed_demo_data(db: Session) -> None:
    setup_logging()
    logger.info("Initializing metadata tables...")
    Base.metadata.create_all(bind=engine)

    # 1. Company
    company = db.scalar(sa.select(Company).where(Company.code == "ORIGIN"))
    if not company:
        company = Company(
            name="Origin PG Hospitality",
            code="ORIGIN",
            email="admin@originpg.com",
            phone="+919876500000",
            address="100 Feet Road, Koramangala 4th Block, Bangalore 560034",
            tax_id="29ABCDE1234F1Z5",
            is_active=True,
        )
        db.add(company)
        db.flush()

    # 2. Roles
    roles = [
        ("SUPER_ADMIN", "Super Administrator / Owner", ["*"]),
        ("PROPERTY_MANAGER", "Property Manager", ["properties:read", "rooms:manage", "residents:manage", "invoices:manage", "complaints:manage"]),
        ("STAFF", "Staff / Warden", ["properties:read", "rooms:read", "beds:status_update", "residents:read", "complaints:read"]),
        ("RESIDENT", "Resident", ["profile:self", "bed:self", "invoices:self", "payments:self", "complaints:self", "notices:read"]),
    ]
    role_map = {}
    for r_name, r_display, r_perms in roles:
        role = db.scalar(sa.select(Role).where(Role.name == r_name))
        if not role:
            role = Role(name=r_name, display_name=r_display, is_system_role=True, permissions=r_perms)
            db.add(role)
            db.flush()
        role_map[r_name] = role

    # 3. Super Admin User - ensure phone is 9876500000 so 9876543210 is free for Priya Sharma
    admin_user = db.scalar(sa.select(User).where(User.email == "admin@originpg.com"))
    if admin_user:
        admin_user.phone = "9876500000"
        db.flush()
    else:
        admin_user = User(
            company_id=company.id,
            role_id=role_map["SUPER_ADMIN"].id,
            full_name="Rajesh Kumar (Owner)",
            email="admin@originpg.com",
            phone="9876500000",
            password_hash=get_password_hash("Admin@123456"),
            is_active=True,
            is_verified=True,
            approval_status="APPROVED",
        )
        db.add(admin_user)
        db.flush()

    # 4. Property
    prop = db.scalar(sa.select(Property).where(Property.code == "OG-01"))
    if not prop:
        prop = Property(
            company_id=company.id,
            name="Origin Grand PG",
            code="OG-01",
            property_type="MENS",
            address_line1="124, 1st Cross, Koramangala 5th Block",
            city="Bengaluru",
            state="Karnataka",
            pincode="560095",
            contact_phone="9876500000",
            contact_email="admin@originpg.com",
            total_floors=3,
            is_active=True,
            amenities=["High-Speed Wi-Fi", "3 Meals Daily", "Washing Machine", "Daily Housekeeping", "Power Backup", "CCTV Security", "Geyser"],
        )
        db.add(prop)
        db.flush()

    # 5. Rooms
    rooms_data = [
        {"room_number": "101", "floor_number": 1, "room_type": "DOUBLE_SHARING", "base_monthly_rent": 8000.0, "deposit_amount": 16000.0},
        {"room_number": "102", "floor_number": 1, "room_type": "TRIPLE_SHARING", "base_monthly_rent": 6500.0, "deposit_amount": 8000.0},
        {"room_number": "201", "floor_number": 2, "room_type": "SINGLE", "base_monthly_rent": 12000.0, "deposit_amount": 15000.0},
    ]
    room_map = {}
    for r_data in rooms_data:
        room = db.scalar(sa.select(Room).where(Room.property_id == prop.id, Room.room_number == r_data["room_number"]))
        if not room:
            room = Room(
                property_id=prop.id,
                room_number=r_data["room_number"],
                floor_number=r_data["floor_number"],
                room_type=r_data["room_type"],
                base_monthly_rent=r_data["base_monthly_rent"],
                deposit_amount=r_data["deposit_amount"],
                is_active=True,
                amenities={"ac": True, "geyser": True, "cupboard": True},
            )
            db.add(room)
            db.flush()
        room_map[r_data["room_number"]] = room

    # 6. Beds
    beds_data = [
        {"room": "101", "bed_number": "101-A", "status": "OCCUPIED", "monthly_rent": 8000.0},
        {"room": "101", "bed_number": "101-B", "status": "OCCUPIED", "monthly_rent": 8000.0},
        {"room": "102", "bed_number": "102-A", "status": "OCCUPIED", "monthly_rent": 6500.0},
        {"room": "102", "bed_number": "102-B", "status": "AVAILABLE", "monthly_rent": 6500.0},
        {"room": "102", "bed_number": "102-C", "status": "AVAILABLE", "monthly_rent": 6500.0},
        {"room": "201", "bed_number": "201-A", "status": "AVAILABLE", "monthly_rent": 12000.0},
    ]
    bed_map = {}
    for b_data in beds_data:
        room = room_map[b_data["room"]]
        bed = db.scalar(sa.select(Bed).where(Bed.room_id == room.id, Bed.bed_number == b_data["bed_number"]))
        if not bed:
            bed = Bed(
                property_id=prop.id,
                room_id=room.id,
                bed_number=b_data["bed_number"],
                status=b_data["status"],
                monthly_rent=b_data["monthly_rent"],
                is_active=True,
            )
            db.add(bed)
            db.flush()
        bed_map[b_data["bed_number"]] = bed

    # 7. Resident Users
    residents_data = [
        {
            "name": "Priya Sharma",
            "phone": "9876543210",
            "email": "priya.sharma@example.com",
            "room": "101",
            "bed": "101-B",
            "rent": 8000.0,
            "dob": date(1998, 5, 15),
            "occupation": "Software Engineer",
            "emergency_name": "Ramesh Sharma",
            "emergency_phone": "9876543299",
            "approval_status": "APPROVED",
            "res_status": "ACTIVE",
        },
        {
            "name": "Siddarth Mishra",
            "phone": "9876543211",
            "email": "siddarth.mishra@example.com",
            "room": "101",
            "bed": "101-A",
            "rent": 8000.0,
            "dob": date(1996, 11, 20),
            "occupation": "Product Designer",
            "emergency_name": "K. Mishra",
            "emergency_phone": "9876543298",
            "approval_status": "APPROVED",
            "res_status": "ACTIVE",
        },
        {
            "name": "Rohan Mehta",
            "phone": "9876543290",
            "email": "rohan.mehta@example.com",
            "room": None,
            "bed": None,
            "rent": 0.0,
            "dob": date(1997, 4, 12),
            "occupation": "Software Consultant",
            "emergency_name": "A. Mehta",
            "emergency_phone": "9812345678",
            "approval_status": "PENDING_APPROVAL",
            "res_status": "PENDING_APPROVAL",
        },
    ]

    for res_info in residents_data:
        user = db.scalar(sa.select(User).where(User.phone == res_info["phone"]))
        if not user:
            user = User(
                company_id=company.id,
                role_id=role_map["RESIDENT"].id,
                full_name=res_info["name"],
                email=res_info["email"],
                phone=res_info["phone"],
                password_hash=get_password_hash("Resident@123"),
                is_active=True,
                is_verified=True,
                approval_status=res_info["approval_status"],
            )
            db.add(user)
            db.flush()
        else:
            user.approval_status = res_info["approval_status"]

        room = room_map[res_info["room"]] if res_info["room"] else None
        bed = bed_map[res_info["bed"]] if res_info["bed"] else None

        res_profile = db.scalar(sa.select(Resident).where(Resident.user_id == user.id))
        if not res_profile:
            res_profile = Resident(
                user_id=user.id,
                property_id=prop.id,
                room_id=room.id if room else None,
                bed_id=bed.id if bed else None,
                date_of_birth=res_info["dob"],
                occupation=res_info["occupation"],
                emergency_contact=f"{res_info['emergency_name']} - {res_info['emergency_phone']}",
                emergency_contact_name=res_info["emergency_name"],
                emergency_contact_phone=res_info["emergency_phone"],
                monthly_rent=res_info["rent"],
                status=res_info["res_status"],
                check_in_date=date(2026, 1, 1),
            )
            db.add(res_profile)
            db.flush()
        else:
            res_profile.status = res_info["res_status"]
            if room:
                res_profile.room_id = room.id
            if bed:
                res_profile.bed_id = bed.id

        # Seed invoice for active resident
        if res_info["res_status"] == "ACTIVE":
            billing_month = datetime.now().strftime("%Y-%m")
            inv = db.scalar(
                sa.select(Invoice).where(
                    Invoice.resident_id == res_profile.id,
                    Invoice.billing_month == billing_month,
                    Invoice.invoice_type == "RENT",
                )
            )
            if not inv:
                inv = Invoice(
                    property_id=prop.id,
                    resident_id=res_profile.id,
                    invoice_number=f"INV-{res_info['phone'][-4:]}-{billing_month}",
                    billing_month=billing_month,
                    invoice_type="RENT",
                    amount=Decimal(str(res_info["rent"])),
                    paid_amount=Decimal("0.00"),
                    due_date=date.today() + timedelta(days=5),
                    status="PENDING",
                    notes="Monthly PG Accommodation Rent",
                )
                db.add(inv)
                db.flush()

    db.commit()
    logger.info("Demo PG residents seeded successfully!")


if __name__ == "__main__":
    db = SessionLocal()
    try:
        seed_demo_data(db)
    finally:
        db.close()
