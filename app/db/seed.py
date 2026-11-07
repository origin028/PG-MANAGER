import uuid
import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.core.logging import logger, setup_logging
from app.core.security import get_password_hash
from app.db.session import SessionLocal
from app.models.company import Company
from app.models.property import Property
from app.models.role import Role
from app.models.user import User, UserPropertyAccess


def seed_database(db: Session) -> None:
    """Seeds the database with initial company, roles, 5 properties, and test users."""

    # 1. Seed or retrieve Company
    company = db.scalar(sa.select(Company).where(Company.code == "ORIGIN"))
    if not company:
        company = Company(
            name="Origin PG Hospitality",
            code="ORIGIN",
            email="contact@originpg.com",
            phone="+919876500000",
            address="100 Feet Road, Koramangala 4th Block, Bangalore, Karnataka 560034",
            tax_id="29ABCDE1234F1Z5",
            is_active=True,
        )
        db.add(company)
        db.flush()
        logger.info(f"Created company: {company.name} ({company.id})")
    else:
        logger.info(f"Company already exists: {company.name}")

    # 2. Seed Roles
    roles_data = [
        {
            "name": "SUPER_ADMIN",
            "display_name": "Super Administrator / Owner",
            "description": "Full access to all properties, operations, staff, financials, and configurations.",
            "is_system_role": True,
            "permissions": ["*"],
        },
        {
            "name": "PROPERTY_MANAGER",
            "display_name": "Property Manager",
            "description": "Operational control over assigned PG properties (residents, rooms, rent, complaints).",
            "is_system_role": True,
            "permissions": [
                "properties:read",
                "rooms:manage",
                "beds:manage",
                "residents:manage",
                "invoices:manage",
                "payments:record",
                "complaints:manage",
                "expenses:read",
                "leads:manage",
            ],
        },
        {
            "name": "STAFF",
            "display_name": "Staff / Warden",
            "description": "Daily ground operations (bed status, resident checks, complaint resolution, visitor logs).",
            "is_system_role": True,
            "permissions": [
                "properties:read",
                "rooms:read",
                "beds:read",
                "beds:status_update",
                "residents:read",
                "complaints:manage",
            ],
        },
        {
            "name": "RESIDENT",
            "display_name": "Resident",
            "description": "Resident Mobile user. Scoped exclusively to own room, dues, payments, notices, and complaints.",
            "is_system_role": True,
            "permissions": [
                "profile:self",
                "bed:self",
                "invoices:self",
                "payments:self",
                "complaints:self",
                "notices:read",
            ],
        },
    ]

    roles_map = {}
    for r_data in roles_data:
        role = db.scalar(sa.select(Role).where(Role.name == r_data["name"]))
        if not role:
            role = Role(
                name=r_data["name"],
                display_name=r_data["display_name"],
                description=r_data["description"],
                is_system_role=r_data["is_system_role"],
                permissions=r_data["permissions"],
            )
            db.add(role)
            db.flush()
            logger.info(f"Created role: {role.name}")
        roles_map[r_data["name"]] = role

    # 3. Seed 5 PG Properties
    properties_data = [
        {
            "name": "Origin Grand PG - Koramangala",
            "code": "OG-KOR",
            "property_type": "CO_LIVING",
            "address_line1": "45, 80 Feet Road, 4th Block, Koramangala",
            "address_line2": "Near Sony World Signal",
            "city": "Bangalore",
            "state": "Karnataka",
            "pincode": "560034",
            "contact_phone": "+919876543201",
            "contact_email": "koramangala@originpg.com",
            "total_floors": 4,
        },
        {
            "name": "Origin Luxury PG - HSR Layout",
            "code": "OG-HSR",
            "property_type": "MENS_PG",
            "address_line1": "12, 17th Cross, Sector 4, HSR Layout",
            "address_line2": "Opposite BDA Complex",
            "city": "Bangalore",
            "state": "Karnataka",
            "pincode": "560102",
            "contact_phone": "+919876543202",
            "contact_email": "hsr@originpg.com",
            "total_floors": 5,
        },
        {
            "name": "Origin Elite PG - Indiranagar",
            "code": "OG-IND",
            "property_type": "LADIES_PG",
            "address_line1": "78, 12th Main Road, HAL 2nd Stage, Indiranagar",
            "address_line2": "Behind Metro Station",
            "city": "Bangalore",
            "state": "Karnataka",
            "pincode": "560038",
            "contact_phone": "+919876543203",
            "contact_email": "indiranagar@originpg.com",
            "total_floors": 3,
        },
        {
            "name": "Origin Comfort PG - Electronic City",
            "code": "OG-ELC",
            "property_type": "CO_LIVING",
            "address_line1": "22, Neeladri Road, Electronics City Phase 1",
            "address_line2": "Near Infosys Gate 10",
            "city": "Bangalore",
            "state": "Karnataka",
            "pincode": "560100",
            "contact_phone": "+919876543204",
            "contact_email": "ecity@originpg.com",
            "total_floors": 4,
        },
        {
            "name": "Origin Prime PG - Bellandur",
            "code": "OG-BLR",
            "property_type": "MENS_PG",
            "address_line1": "89, Green Glen Layout, Bellandur",
            "address_line2": "Near Ecospace Tech Park",
            "city": "Bangalore",
            "state": "Karnataka",
            "pincode": "560103",
            "contact_phone": "+919876543205",
            "contact_email": "bellandur@originpg.com",
            "total_floors": 4,
        },
    ]

    properties_map = {}
    for p_data in properties_data:
        prop = db.scalar(sa.select(Property).where(Property.code == p_data["code"]))
        if not prop:
            prop = Property(
                company_id=company.id,
                name=p_data["name"],
                code=p_data["code"],
                property_type=p_data["property_type"],
                address_line1=p_data["address_line1"],
                address_line2=p_data.get("address_line2"),
                city=p_data["city"],
                state=p_data["state"],
                pincode=p_data["pincode"],
                contact_phone=p_data.get("contact_phone"),
                contact_email=p_data.get("contact_email"),
                total_floors=p_data["total_floors"],
                is_active=True,
                settings={"curfew_time": "22:30", "gate_biometric": True},
            )
            db.add(prop)
            db.flush()
            logger.info(f"Created property: {prop.name} ({prop.code})")
        properties_map[p_data["code"]] = prop

    # 4. Seed Users for Phase 1 Acceptance Testing
    users_data = [
        {
            "full_name": "Rajesh Kumar (Owner)",
            "email": "admin@originpg.com",
            "phone": "9876543210",
            "password": "Admin@123456",
            "role": "SUPER_ADMIN",
            "assigned_properties": [],  # Super admin has portfolio-wide access
        },
        {
            "full_name": "Suresh Nair (Property Manager)",
            "email": "manager@originpg.com",
            "phone": "9876543211",
            "password": "Manager@123456",
            "role": "PROPERTY_MANAGER",
            "assigned_properties": ["OG-KOR", "OG-HSR"],
        },
        {
            "full_name": "Anil Sharma (Warden / Staff)",
            "email": "staff@originpg.com",
            "phone": "9876543212",
            "password": "Staff@123456",
            "role": "STAFF",
            "assigned_properties": ["OG-KOR"],
        },
        {
            "full_name": "Rohan Deshmukh (Resident)",
            "email": "resident@originpg.com",
            "phone": "9876543213",
            "password": "Resident@123456",
            "role": "RESIDENT",
            "assigned_properties": ["OG-KOR"],
        },
    ]

    for u_data in users_data:
        user = db.scalar(sa.select(User).where(User.phone == u_data["phone"]))
        if not user:
            user = User(
                company_id=company.id,
                role_id=roles_map[u_data["role"]].id,
                full_name=u_data["full_name"],
                email=u_data["email"],
                phone=u_data["phone"],
                password_hash=get_password_hash(u_data["password"]),
                is_active=True,
                is_verified=True,
            )
            db.add(user)
            db.flush()
            logger.info(f"Created user: {user.full_name} ({user.email}) [{u_data['role']}]")

            # Assign properties if specified
            for prop_code in u_data["assigned_properties"]:
                prop = properties_map.get(prop_code)
                if prop:
                    access = UserPropertyAccess(
                        user_id=user.id,
                        property_id=prop.id,
                        access_level="MANAGER" if u_data["role"] == "PROPERTY_MANAGER" else "STAFF",
                    )
                    db.add(access)

    db.commit()
    logger.info("Database seeding completed successfully.")


if __name__ == "__main__":
    setup_logging()
    db = SessionLocal()
    try:
        seed_database(db)
    finally:
        db.close()
