"""Creates the PG company and its first owner login on a freshly migrated database.

Run once per deployment (e.g. in the Render shell) after `alembic upgrade head`:

    python scripts/create_owner.py --company "Origin Living" --email owner@example.com \
        --phone 98XXXXXXXX --name "Owner Name" [--beds 250]

The password is read from the OWNER_PASSWORD environment variable, or asked for interactively.
It is never printed or stored anywhere except as a bcrypt hash. Safe to re-run: it refuses
to create a second owner with the same email or phone.
"""
import argparse
import getpass
import os
import re
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import sqlalchemy as sa  # noqa: E402

import app.models  # noqa: E402,F401  (registers every model)
from app.core.security import get_password_hash  # noqa: E402
from app.db.session import SessionLocal  # noqa: E402
from app.models.property import Company  # noqa: E402
from app.models.user import User  # noqa: E402
from app.services.role_service import ensure_system_roles_exist  # noqa: E402


def strong(pw: str) -> bool:
    return len(pw) >= 10 and bool(re.search(r"[a-z]", pw) and re.search(r"[A-Z]", pw) and re.search(r"\d", pw))


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--company", required=True)
    ap.add_argument("--email", required=True)
    ap.add_argument("--phone", required=True)
    ap.add_argument("--name", required=True)
    ap.add_argument("--beds", type=int, default=250, help="Bed capacity on the plan")
    a = ap.parse_args()

    password = os.environ.get("OWNER_PASSWORD") or getpass.getpass("Owner password: ")
    if not strong(password):
        raise SystemExit("Password must be at least 10 characters with upper case, lower case and a number.")

    db = SessionLocal()
    try:
        email, phone = a.email.strip().lower(), a.phone.strip()
        if db.scalar(sa.select(User.id).where(sa.or_(User.email == email, User.phone == phone))):
            raise SystemExit("A user with this email or phone already exists. Nothing was changed.")
        roles = ensure_system_roles_exist(db)
        code = re.sub(r"[^A-Z0-9]", "", a.company.upper())[:20] or "PG"
        if db.scalar(sa.select(Company.id).where(Company.code == code)):
            code = f"{code[:14]}{os.urandom(3).hex().upper()}"
        company = Company(name=a.company.strip(), code=code, email=email, phone=phone, is_active=True, bed_limit=a.beds)
        db.add(company)
        db.flush()
        db.add(User(company_id=company.id, role_id=roles["SUPER_ADMIN"].id, email=email, phone=phone, full_name=a.name.strip(),
                    password_hash=get_password_hash(password), is_active=True, is_verified=True, approval_status="APPROVED"))
        db.commit()
        print(f"Created company '{company.name}' and owner login {email}.")
    finally:
        db.close()


if __name__ == "__main__":
    main()
