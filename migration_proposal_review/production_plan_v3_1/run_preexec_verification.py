"""
Pre-Execution Restore & Migration Verification Harness
Target: Disposable database pg_verify_preexec_20261030
Validates:
1. Restore of new timestamped backup
2. Pre-migration state (13 tables, 63 rows, rev 6cb475ecad6d)
3. Execution of 01_unified_reconcile_pg_management_v3_1.sql
4. Post-migration state (24 tables, 63 rows preserved, rev b2c3d4e5f6a7, FKs, ON DELETE RESTRICT)
5. Direct SQLAlchemy ORM validation & Pytest critical suites
6. Clean teardown of disposable database
7. Live database pg_management read-only integrity check
"""

import os
import sys
import re
import time
import subprocess
import hashlib
import urllib.parse
from pathlib import Path
import psycopg
from psycopg import sql

# Paths
BACKEND_DIR = Path("D:/PG_Management/pg-management-system/backend")
ENV_FILE = BACKEND_DIR / ".env"
SQL_FILE = Path("D:/PG_Management/migration_proposal_review/production_plan_v3_1/01_unified_reconcile_pg_management_v3_1.sql")
BACKUP_DIR = Path("D:/PG_Management/production_backups")
PG_RESTORE_BIN = r"C:\Program Files\PostgreSQL\18\bin\pg_restore.exe"
PSQL_BIN = r"C:\Program Files\PostgreSQL\18\bin\psql.exe"
PYTHON_BIN = r"D:\PG_Management\.venv\Scripts\python.exe"

DISPOSABLE_DB = "pg_verify_preexec_20261030"
PROTECTED_DBS = {"pg_management", "postgres", "pg_management_test", "pg_reconcile_v2_sandbox_test"}

def get_db_credentials():
    content = ENV_FILE.read_text(encoding="utf-8")
    for line in content.splitlines():
        m = re.match(r"^DATABASE_URL=.*://([^:]+):([^@]+)@([^:/]+)(?::(\d+))?/(.+)$", line)
        if m:
            user = m.group(1)
            password = urllib.parse.unquote(m.group(2))
            host = m.group(3)
            port = int(m.group(4) or 5432)
            dbname = m.group(5)
            return user, password, host, port, dbname
    raise RuntimeError("Could not parse DATABASE_URL from .env")

def get_latest_backup():
    backups = sorted(BACKUP_DIR.glob("pg_management_backup_*.dump"), key=lambda p: p.stat().st_mtime, reverse=True)
    if not backups:
        raise RuntimeError("No backup found in production_backups")
    return backups[0]

def main():
    print("=" * 80)
    print("PG MANAGEMENT - V3.1 PRE-EXECUTION RESTORE & VERIFICATION HARNESS")
    print("=" * 80)

    user, password, host, port, live_db = get_db_credentials()
    latest_backup = get_latest_backup()
    print(f"[1] Verified Latest Backup:")
    print(f"    Path:   {latest_backup}")
    print(f"    Size:   {latest_backup.stat().st_size:,} bytes")
    
    h = hashlib.sha256()
    with open(latest_backup, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    backup_sha = h.hexdigest()
    print(f"    SHA256: {backup_sha}")

    # Check SQL file SHA256
    h_sql = hashlib.sha256()
    with open(SQL_FILE, "rb") as f:
        while chunk := f.read(65536):
            h_sql.update(chunk)
    sql_sha = h_sql.hexdigest()
    print(f"[2] Verified Migration SQL:")
    print(f"    Path:   {SQL_FILE}")
    print(f"    Size:   {SQL_FILE.stat().st_size:,} bytes")
    print(f"    SHA256: {sql_sha}")

    # Check safety of DB name
    if DISPOSABLE_DB in PROTECTED_DBS:
        raise ValueError(f"CRITICAL ERROR: {DISPOSABLE_DB} is in PROTECTED_DBS!")

    # Connect to postgres maintenance DB to recreate disposable DB
    print(f"[3] Recreating disposable database: {DISPOSABLE_DB}...")
    conn_str_maint = f"postgresql://{user}:{urllib.parse.quote_plus(password)}@{host}:{port}/postgres"
    with psycopg.connect(conn_str_maint, autocommit=True) as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT pg_terminate_backend(pid) 
                FROM pg_stat_activity 
                WHERE datname = %s AND pid <> pg_backend_pid();
            """, (DISPOSABLE_DB,))
            cur.execute(sql.SQL("DROP DATABASE IF EXISTS {}").format(sql.Identifier(DISPOSABLE_DB)))
            cur.execute(sql.SQL("CREATE DATABASE {} OWNER {}").format(sql.Identifier(DISPOSABLE_DB), sql.Identifier(user)))
    print("    Disposable database created successfully.")

    # Restore backup into disposable DB
    print(f"[4] Restoring {latest_backup.name} into {DISPOSABLE_DB}...")
    env = os.environ.copy()
    env["PGPASSWORD"] = password
    restore_cmd = [
        PG_RESTORE_BIN,
        "-h", host,
        "-p", str(port),
        "-U", user,
        "-d", DISPOSABLE_DB,
        "--no-owner",
        "--no-acl",
        "-v",
        str(latest_backup)
    ]
    t0 = time.time()
    res = subprocess.run(restore_cmd, env=env, capture_output=True, text=True)
    t_restore = time.time() - t0
    if res.returncode > 1:
        print("    pg_restore FAILED:")
        print(res.stderr)
        sys.exit(1)
    print(f"    Restore completed in {t_restore:.2f}s (Exit code: {res.returncode}).")

    # Connect to disposable DB and verify baseline
    conn_str_disp = f"postgresql://{user}:{urllib.parse.quote_plus(password)}@{host}:{port}/{DISPOSABLE_DB}"
    print(f"[5] Verifying Restored Baseline State in {DISPOSABLE_DB}...")
    with psycopg.connect(conn_str_disp) as conn:
        with conn.cursor() as cur:
            # Revision
            cur.execute("SELECT version_num FROM alembic_version;")
            row = cur.fetchone()
            rev = row[0] if row else None
            assert rev == "6cb475ecad6d", f"Expected rev 6cb475ecad6d, got {rev}"
            print(f"    - Alembic Revision: {rev} (VERIFIED)")

            # Tables
            cur.execute("""
                SELECT table_name 
                FROM information_schema.tables 
                WHERE table_schema = 'public' 
                ORDER BY table_name;
            """)
            tables = [r[0] for r in cur.fetchall()]
            assert len(tables) == 13, f"Expected 13 tables, got {len(tables)}: {tables}"
            print(f"    - Table Count: {len(tables)} tables (VERIFIED)")

            # Record count
            row_counts = {}
            total_rows = 0
            for t in tables:
                cur.execute(sql.SQL("SELECT count(*) FROM {}").format(sql.Identifier(t)))
                c = cur.fetchone()[0]
                row_counts[t] = c
                total_rows += c
            expected_counts = {
                'alembic_version': 1,
                'audit_logs': 36,
                'beds': 0,
                'companies': 1,
                'invoices': 0,
                'payments': 0,
                'properties': 5,
                'refresh_tokens': 8,
                'residents': 0,
                'roles': 4,
                'rooms': 0,
                'user_property_access': 4,
                'users': 4
            }
            assert row_counts == expected_counts, f"Row count mismatch: expected {expected_counts}, got {row_counts}"
            print(f"    - Total Row Count: {total_rows} rows across 13 tables (VERIFIED)")
            print(f"      Rows breakdown: {row_counts}")

            # Users & roles
            cur.execute("SELECT email, role_id, is_active FROM users ORDER BY email;")
            users = cur.fetchall()
            assert len(users) == 4, f"Expected 4 users, got {len(users)}"
            print(f"    - Users: {len(users)} users verified ({[u[0] for u in users]})")

            # Extensions
            cur.execute("SELECT extname FROM pg_extension WHERE extname IN ('uuid-ossp', 'pgcrypto');")
            exts = [r[0] for r in cur.fetchall()]
            print(f"    - Installed Extensions: {exts}")

    # Execute V3.1 Migration
    print(f"[6] Executing Migration SQL ({SQL_FILE.name}) on {DISPOSABLE_DB}...")
    psql_cmd = [
        PSQL_BIN,
        "-h", host,
        "-p", str(port),
        "-U", user,
        "-d", DISPOSABLE_DB,
        "--set", "ON_ERROR_STOP=1",
        "-v", "ON_ERROR_STOP=1",
        "-f", str(SQL_FILE)
    ]
    t0 = time.time()
    res_mig = subprocess.run(psql_cmd, env=env, capture_output=True, text=True)
    t_mig = time.time() - t0
    if res_mig.returncode != 0:
        print("    MIGRATION FAILED:")
        print(res_mig.stderr)
        sys.exit(1)
    print(f"    Migration executed successfully in {t_mig:.2f}s (Exit code: 0).")

    # Verify Post-Migration State
    print(f"[7] Verifying Post-Migration State in {DISPOSABLE_DB}...")
    with psycopg.connect(conn_str_disp) as conn:
        with conn.cursor() as cur:
            # Revision
            cur.execute("SELECT version_num FROM alembic_version;")
            row = cur.fetchone()
            rev = row[0] if row else None
            assert rev == "b2c3d4e5f6a7", f"Expected rev b2c3d4e5f6a7, got {rev}"
            print(f"    - Alembic Revision: {rev} (VERIFIED)")

            # Table count
            cur.execute("""
                SELECT table_name 
                FROM information_schema.tables 
                WHERE table_schema = 'public' 
                ORDER BY table_name;
            """)
            post_tables = [r[0] for r in cur.fetchall()]
            assert len(post_tables) == 24, f"Expected 24 tables, got {len(post_tables)}: {post_tables}"
            print(f"    - Table Count: {len(post_tables)} tables (VERIFIED)")

            # Preserved row counts
            for t, count in expected_counts.items():
                cur.execute(sql.SQL("SELECT count(*) FROM {}").format(sql.Identifier(t)))
                post_c = cur.fetchone()[0]
                assert post_c == count, f"Row count mismatch in {t}: expected {count}, got {post_c}"
            print(f"    - All 63 baseline records preserved identically (VERIFIED)")

            # Approval statuses
            cur.execute("SELECT approval_status, count(*) FROM users GROUP BY approval_status ORDER BY approval_status;")
            approval_counts = dict(cur.fetchall())
            assert approval_counts.get("APPROVED") == 3, f"Expected 3 APPROVED, got {approval_counts}"
            assert approval_counts.get("PENDING_APPROVAL") == 1, f"Expected 1 PENDING_APPROVAL, got {approval_counts}"
            print(f"    - User Approval Statuses: {approval_counts} (VERIFIED)")

            # Check payments.invoice_id ON DELETE RESTRICT
            cur.execute("""
                SELECT
                    tc.constraint_name,
                    rc.delete_rule,
                    kcu.column_name,
                    ccu.table_name AS foreign_table_name,
                    ccu.column_name AS foreign_column_name
                FROM information_schema.table_constraints AS tc
                JOIN information_schema.key_column_usage AS kcu
                  ON tc.constraint_name = kcu.constraint_name
                  AND tc.table_schema = kcu.table_schema
                JOIN information_schema.referential_constraints AS rc
                  ON tc.constraint_name = rc.constraint_name
                  AND tc.table_schema = rc.constraint_schema
                JOIN information_schema.constraint_column_usage AS ccu
                  ON rc.unique_constraint_name = ccu.constraint_name
                  AND rc.unique_constraint_schema = ccu.constraint_schema
                WHERE tc.table_name = 'payments' AND kcu.column_name = 'invoice_id';
            """)
            fk_rows = cur.fetchall()
            assert len(fk_rows) == 1, f"Expected 1 FK on payments.invoice_id, got {fk_rows}"
            fk_name, del_rule, col, ref_tbl, ref_col = fk_rows[0]
            assert del_rule == "RESTRICT", f"Expected RESTRICT, got {del_rule}"
            print(f"    - payments.invoice_id Foreign Key: {fk_name} -> {ref_tbl}.{ref_col} [ON DELETE {del_rule}] (VERIFIED)")

            # Check legacy columns pruned (all 26 columns across 5 tables)
            cur.execute("""
                SELECT table_name, column_name 
                FROM information_schema.columns 
                WHERE table_schema = 'public' 
                  AND (
                    (table_name = 'rooms' AND column_name IN ('base_monthly_rent', 'deposit_amount')) OR
                    (table_name = 'beds' AND column_name IN ('property_id', 'is_active')) OR
                    (table_name = 'residents' AND column_name IN ('company_id', 'full_name', 'email', 'phone', 'kyc_notes', 'verified_at', 'verified_by_id')) OR
                    (table_name = 'invoices' AND column_name IN ('company_id', 'billing_period_start', 'billing_period_end', 'issue_date', 'rent_amount', 'additional_charges', 'discount_amount', 'total_amount', 'balance_amount')) OR
                    (table_name = 'payments' AND column_name IN ('company_id', 'payment_method', 'transaction_reference', 'recorded_by_user_id', 'payment_date', 'notes'))
                  );
            """)
            legacy_cols = cur.fetchall()
            assert len(legacy_cols) == 0, f"Found unexpected legacy columns: {legacy_cols}"
            print("    - All 26 legacy columns pruned successfully (VERIFIED)")

            # Check foreign keys count
            cur.execute("""
                SELECT count(*) 
                FROM information_schema.table_constraints 
                WHERE table_schema = 'public' AND constraint_type = 'FOREIGN KEY';
            """)
            fk_count = cur.fetchone()[0]
            assert fk_count == 37, f"Expected 37 foreign keys, got {fk_count}"
            print(f"    - Total Foreign Keys: {fk_count} (VERIFIED)")

    # Direct ORM and Model constraint tests against restored & migrated database
    print(f"[8] Running Direct ORM Constraint & Transaction Tests against {DISPOSABLE_DB}...")
    import uuid
    from datetime import date
    import sqlalchemy as sa
    from sqlalchemy.orm import sessionmaker
    from sqlalchemy import create_engine
    from sqlalchemy.exc import IntegrityError

    # Import backend models
    sys.path.insert(0, str(BACKEND_DIR))
    from app.models.property import Company, Property
    from app.models.role import Role
    from app.models.user import User
    from app.models.room import Room
    from app.models.bed import Bed
    from app.models.resident import Resident
    from app.models.invoice import Invoice
    from app.models.payment import Payment

    sa_url = f"postgresql+psycopg://{user}:{urllib.parse.quote_plus(password)}@{host}:{port}/{DISPOSABLE_DB}"
    engine = create_engine(sa_url)
    Session = sessionmaker(bind=engine)
    with Session() as session:
        # Verify existing models
        company = session.query(Company).first()
        assert company is not None, "Failed to load company via ORM"
        props = session.query(Property).all()
        assert len(props) == 5, f"Expected 5 properties via ORM, got {len(props)}"
        users = session.query(User).all()
        assert len(users) == 4, f"Expected 4 users via ORM, got {len(users)}"
        print(f"    - ORM Read Test: Successfully queried Company, {len(props)} Properties, {len(users)} Users.")

        # Test ORM transaction insert & ON DELETE RESTRICT enforcement
        prop = props[0]
        test_room = Room(property_id=prop.id, room_number="TEST-RM-999", floor_number=1, room_type="DOUBLE_SHARING", base_rent=5000.0)
        session.add(test_room)
        session.flush()

        test_bed = Bed(room_id=test_room.id, bed_number="TEST-BED-999", monthly_rent=5000.0)
        session.add(test_bed)
        session.flush()

        # Find seed resident user
        res_user = session.query(User).filter_by(email="resident@originpg.com").first()
        test_resident = Resident(
            user_id=res_user.id,
            property_id=prop.id,
            room_id=test_room.id,
            bed_id=test_bed.id,
            check_in_date=date.today(),
            security_deposit=10000.0,
            monthly_rent=5000.0,
            status="ACTIVE"
        )
        session.add(test_resident)
        session.flush()

        test_invoice = Invoice(
            property_id=prop.id,
            resident_id=test_resident.id,
            invoice_number=f"INV-TEST-{uuid.uuid4().hex[:6]}",
            billing_month="2026-10",
            due_date=date(2026, 10, 5),
            amount=5000.0,
            paid_amount=5000.0,
            status="PAID"
        )
        session.add(test_invoice)
        session.flush()

        test_payment = Payment(
            property_id=prop.id,
            invoice_id=test_invoice.id,
            resident_id=test_resident.id,
            payment_number=f"PAY-TEST-{uuid.uuid4().hex[:6]}",
            amount=5000.0,
            payment_mode="UPI",
            status="SUCCESS"
        )
        session.add(test_payment)
        session.flush()
        print("    - ORM Insert Test: Successfully inserted Room, Bed, Resident, Invoice, and Payment.")

        # Test ON DELETE RESTRICT on invoice
        nested = session.begin_nested()
        try:
            session.delete(test_invoice)
            session.flush()
            raise AssertionError("CRITICAL FAILURE: Deleting invoice did not trigger ON DELETE RESTRICT on payments!")
        except IntegrityError:
            nested.rollback()
            print("    - ORM Foreign Key Test: ON DELETE RESTRICT correctly prevented deleting invoice with linked payment.")

        # Clean rollback of entire test transaction
        session.rollback()
        print("    - ORM Rollback Test: Complete test transaction rolled back cleanly.")

    engine.dispose()

    # Run critical Pytest suite targeting disposable DB
    print(f"[9] Running Critical Pytest Suites against {DISPOSABLE_DB}...")
    test_env = os.environ.copy()
    test_env["TEST_DATABASE_URL"] = sa_url
    test_env["DATABASE_URL"] = sa_url
    test_env["PYTHONPATH"] = str(BACKEND_DIR)

    test_targets = [
        "tests/test_resident_registration_approval.py",
        "tests/test_upi_rent_payments.py",
        "tests/test_postgres_concurrency.py",
        "tests/test_postgres_resident_concurrency.py",
    ]
    pytest_cmd = [
        PYTHON_BIN,
        "-m", "pytest",
        *test_targets,
        "-q"
    ]
    t0 = time.time()
    res_pytest = subprocess.run(pytest_cmd, cwd=str(BACKEND_DIR), env=test_env, capture_output=True, text=True)
    t_test = time.time() - t0
    print(f"    Pytest finished in {t_test:.2f}s (Exit code: {res_pytest.returncode})")
    
    summary_lines = [l for l in res_pytest.stdout.splitlines() if "passed" in l]
    summary_line = summary_lines[-1] if summary_lines else res_pytest.stdout[-300:]
    print(f"    Test Summary: {summary_line.strip()}")
    if res_pytest.returncode != 0:
        print("    PYTEST OUTPUT ON FAILURE:")
        print(res_pytest.stdout[-2000:])
        print(res_pytest.stderr[-1000:])
        sys.exit(1)

    # Clean teardown of disposable database
    print(f"[10] Tearing down disposable database {DISPOSABLE_DB}...")
    with psycopg.connect(conn_str_maint, autocommit=True) as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT pg_terminate_backend(pid) 
                FROM pg_stat_activity 
                WHERE datname = %s AND pid <> pg_backend_pid();
            """, (DISPOSABLE_DB,))
            cur.execute(sql.SQL("DROP DATABASE IF EXISTS {}").format(sql.Identifier(DISPOSABLE_DB)))
    print(f"    Disposable database {DISPOSABLE_DB} dropped cleanly.")

    # Live Database Read-Only Integrity Check
    print(f"[11] Live Database Read-Only Integrity Check (pg_management)...")
    conn_str_live = f"postgresql://{user}:{urllib.parse.quote_plus(password)}@{host}:{port}/{live_db}"
    with psycopg.connect(conn_str_live) as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT version_num FROM alembic_version;")
            live_rev = cur.fetchone()[0]
            assert live_rev == "6cb475ecad6d", f"Live rev altered! Got {live_rev}"
            
            cur.execute("SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';")
            live_tables = cur.fetchone()[0]
            assert live_tables == 13, f"Live tables altered! Got {live_tables}"

            cur.execute("""
                SELECT sum(c) FROM (
                    SELECT count(*) as c FROM users
                    UNION ALL SELECT count(*) FROM roles
                    UNION ALL SELECT count(*) FROM companies
                    UNION ALL SELECT count(*) FROM properties
                    UNION ALL SELECT count(*) FROM user_property_access
                    UNION ALL SELECT count(*) FROM refresh_tokens
                    UNION ALL SELECT count(*) FROM audit_logs
                    UNION ALL SELECT count(*) FROM alembic_version
                ) s;
            """)
            live_rows = cur.fetchone()[0]
            assert live_rows == 63, f"Live rows altered! Got {live_rows}"
            print(f"    - Live Revision: {live_rev} (UNTOUCHED)")
            print(f"    - Live Tables:   {live_tables} (UNTOUCHED)")
            print(f"    - Live Rows:     {live_rows} (UNTOUCHED)")

    print("=" * 80)
    print("ALL PRE-EXECUTION RESTORE & MIGRATION VERIFICATION CHECKS PASSED (100%)")
    print("=" * 80)

if __name__ == "__main__":
    main()
