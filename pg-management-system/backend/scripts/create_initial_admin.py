import sys
import os

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


def create_initial_admin(db: Session) -> None:
    """Seeds the initial operating company, system roles, and super administrator."""
    setup_logging()
    logger.info("Initializing metadata tables in PostgreSQL...")
    Base.metadata.create_all(bind=engine)

    # 1. Seed or retrieve Company
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
        logger.info(f"Created company: {company.name}")
    else:
        logger.info(f"Existing company found: {company.name}")

    # 2. Seed System Roles
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
            role = Role(
                name=r_name,
                display_name=r_display,
                is_system_role=True,
                permissions=r_perms,
            )
            db.add(role)
            db.flush()
            logger.info(f"Created system role: {r_name}")
        role_map[r_name] = role

    # 3. Seed Initial Super Administrator User
    admin_phone = "9876543210"
    admin_email = "admin@originpg.com"
    existing_admin = db.scalar(sa.select(User).where(User.phone == admin_phone))
    if not existing_admin:
        admin_user = User(
            company_id=company.id,
            role_id=role_map["SUPER_ADMIN"].id,
            full_name="Rajesh Kumar (Owner)",
            email=admin_email,
            phone=admin_phone,
            password_hash=get_password_hash("Admin@123456"),
            is_active=True,
            is_verified=True,
        )
        db.add(admin_user)
        db.commit()
        logger.info(f"Successfully created Super Administrator: {admin_user.email} / {admin_user.phone}")
    else:
        logger.info(f"Super Administrator already exists: {existing_admin.email}")


if __name__ == "__main__":
    db = SessionLocal()
    try:
        create_initial_admin(db)
    finally:
        db.close()
