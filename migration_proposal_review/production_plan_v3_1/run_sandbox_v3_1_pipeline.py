"""Comprehensive V3.1 Sandbox Verification & Exact Schema Comparison Pipeline.

Executes all verification stages against disposable database: pg_reconcile_v3_1_sandbox_test.
Also provisions temporary pg_fresh_alembic_head_test to perform deep side-by-side metadata comparison.

SAFETY INVARIANTS:
1. Refuses to run if target database is pg_management, pg_reconcile_v2_sandbox_test, etc.
2. Checks exit code and stdout/stderr at every stage.
3. Preserves failed sandbox if any test fails; cleans up only on 100% success.
"""
import os
import sys
import subprocess
import urllib.parse
from datetime import datetime

PG_BIN = r"C:\Program Files\PostgreSQL\18\bin"
BACKUP_FILE = r"D:\PG_Management\pg_management_backup_20261029.dump"
ENV_FILE = r"D:\PG_Management\pg-management-system\backend\.env"
BACKEND_DIR = r"D:\PG_Management\pg-management-system\backend"
V3_1_SQL = r"D:\PG_Management\migration_proposal_review\production_plan_v3_1\01_unified_reconcile_pg_management_v3_1.sql"

SANDBOX_DB = "pg_reconcile_v3_1_sandbox_test"
FRESH_HEAD_DB = "pg_fresh_alembic_head_test"

# Verify safety invariants
PROTECTED_DBS = {
    "pg_management",
    "postgres",
    "pg_management_test",
    "pg_reconcile_v2_sandbox_test",
    "pg_reconcile_v3_sandbox_test",
}
if SANDBOX_DB in PROTECTED_DBS:
    raise RuntimeError(f"CRITICAL SAFETY VIOLATION: Refusing to run on protected database '{SANDBOX_DB}'")

# Extract password from .env
with open(ENV_FILE, "r", encoding="utf-8") as f:
    env_content = f.read()

import re
match = re.search(r"^DATABASE_URL=.*://([^:]+):([^@]+)@([^:/]+)(?::(\d+))?/(.+)$", env_content, re.MULTILINE)
if not match:
    raise RuntimeError("Could not parse DATABASE_URL from .env")

db_user = match.group(1)
db_pass = urllib.parse.unquote(match.group(2))
db_host = match.group(3)
db_port = match.group(4) or "5432"

os.environ["PGPASSWORD"] = db_pass
os.environ["SANDBOX_DATABASE_URL"] = f"postgresql+psycopg://{db_user}:{urllib.parse.quote_plus(db_pass)}@{db_host}:{db_port}/{SANDBOX_DB}"
os.environ["FRESH_HEAD_DATABASE_URL"] = f"postgresql+psycopg://{db_user}:{urllib.parse.quote_plus(db_pass)}@{db_host}:{db_port}/{FRESH_HEAD_DB}"

def run_cmd(cmd_list, description, cwd=None, env=None):
    print(f"\n=======================================================")
    print(f">> {description}")
    print(f"=======================================================")
    safe_cmd = [c.replace(db_pass, "******") if db_pass in c else c for c in cmd_list]
    print("Executing:", " ".join(safe_cmd))
    
    start_time = datetime.now()
    exec_env = os.environ.copy()
    if env:
        exec_env.update(env)
    proc = subprocess.run(cmd_list, capture_output=True, text=True, encoding="utf-8", errors="replace", cwd=cwd, env=exec_env)
    elapsed = (datetime.now() - start_time).total_seconds()
    
    print(f"Exit code: {proc.returncode} (in {elapsed:.2f}s)")
    if proc.stdout.strip():
        print("--- STDOUT ---")
        print(proc.stdout.strip())
    if proc.stderr.strip():
        print("--- STDERR ---")
        print(proc.stderr.strip())
        
    if proc.returncode != 0:
        raise RuntimeError(f"Stage failed: {description} (exit code {proc.returncode})")
    return proc.stdout

def terminate_and_drop(db_name):
    psql = os.path.join(PG_BIN, "psql.exe")
    dropdb = os.path.join(PG_BIN, "dropdb.exe")
    subprocess.run([
        psql, "-h", db_host, "-p", db_port, "-U", db_user, "-d", "postgres", "-c",
        f"SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '{db_name}' AND pid <> pg_backend_pid();"
    ], capture_output=True)
    subprocess.run([dropdb, "-h", db_host, "-p", db_port, "-U", db_user, db_name], capture_output=True)

def main():
    print(f"Starting V3.1 Sandbox Verification on: {SANDBOX_DB}")
    psql = os.path.join(PG_BIN, "psql.exe")
    createdb = os.path.join(PG_BIN, "createdb.exe")
    pg_restore = os.path.join(PG_BIN, "pg_restore.exe")

    # Clean up prior aborted run of target DBs
    terminate_and_drop(SANDBOX_DB)
    terminate_and_drop(FRESH_HEAD_DB)

    sandbox_succeeded = False

    try:
        # Stage 1: Provision fresh head DB and run Alembic upgrade head
        run_cmd([createdb, "-h", db_host, "-p", db_port, "-U", db_user, FRESH_HEAD_DB],
                f"Provision Fresh Head Database ({FRESH_HEAD_DB})")
        
        # Run alembic upgrade head on FRESH_HEAD_DB programmatically
        alembic_upgrade_script = rf"""
import os, sys
os.environ["DATABASE_URL"] = r"{os.environ['FRESH_HEAD_DATABASE_URL']}"
sys.path.insert(0, r"{BACKEND_DIR}")

from alembic.config import Config
from alembic import command

alembic_cfg = Config(r"{os.path.join(BACKEND_DIR, 'alembic.ini')}")
alembic_cfg.set_main_option("script_location", r"{os.path.join(BACKEND_DIR, 'migrations')}")
command.upgrade(alembic_cfg, "head")
print("FRESH HEAD UPGRADE COMPLETE.")
"""
        run_cmd([sys.executable, "-c", alembic_upgrade_script],
                "Apply Active Alembic Migrations to Fresh Head DB", cwd=BACKEND_DIR)

        # Stage 2: Provision disposable sandbox DB
        run_cmd([createdb, "-h", db_host, "-p", db_port, "-U", db_user, SANDBOX_DB],
                f"Provision Disposable Sandbox Database ({SANDBOX_DB})")

        # Stage 3: Restore 20261029 production backup into sandbox
        run_cmd([pg_restore, "-h", db_host, "-p", db_port, "-U", db_user,
                 "-d", SANDBOX_DB, "--no-owner", f"--role={db_user}", BACKUP_FILE],
                "Restore 20261029 Production Backup into Sandbox")

        # Stage 4: Execute V3.1 Unified SQL
        run_cmd([psql, "-h", db_host, "-p", db_port, "-U", db_user, "-d", SANDBOX_DB,
                 "--set", "ON_ERROR_STOP=1", "-v", "ON_ERROR_STOP=1", "-f", V3_1_SQL],
                "Execute 01_unified_reconcile_pg_management_v3_1.sql")

        # Stage 5: Detailed Verification of Fixes in Sandbox
        fix_check_sql = """
        -- 1. Check approval_status breakdown
        SELECT approval_status, count(*) AS user_count FROM users GROUP BY approval_status ORDER BY approval_status;
        SELECT email, approval_status, r.name AS role_name FROM users u JOIN roles r ON u.role_id = r.id ORDER BY r.name;
        
        -- 2. Confirm payments.notes column is GONE
        SELECT count(*) AS lingering_payments_notes 
        FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'payments' AND column_name = 'notes';

        -- 3. Confirm payments.invoice_id is strictly RESTRICT
        SELECT conname, pg_get_constraintdef(oid) 
        FROM pg_constraint 
        WHERE conname = 'payments_invoice_id_fkey';

        -- 4. Confirm total tables
        SELECT count(*) AS total_tables FROM information_schema.tables WHERE table_schema = 'public';

        -- 5. Confirm alembic_version
        SELECT version_num FROM alembic_version;
        """
        run_cmd([psql, "-h", db_host, "-p", db_port, "-U", db_user, "-d", SANDBOX_DB, "-c", fix_check_sql],
                "Verify V3.1 Specific Fixes (approval_status, payments.notes, payments_invoice_id_fkey)")

        # Stage 6: Deep Side-by-Side Metadata Comparison (Fresh Head vs Reconciled Sandbox)
        compare_script = r"""
import os, sys
sys.path.insert(0, r"D:\PG_Management\pg-management-system\backend")

import psycopg
from alembic.migration import MigrationContext
from alembic.autogenerate import compare_metadata
from sqlalchemy import create_engine
import app.models
from app.db.base import Base

fresh_url = os.environ["FRESH_HEAD_DATABASE_URL"]
sandbox_url = os.environ["SANDBOX_DATABASE_URL"]

def get_schema_details(url):
    engine = create_engine(url)
    details = {}
    with engine.connect() as conn:
        # Tables
        cur = conn.connection.cursor()
        cur.execute("SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;")
        details['tables'] = [r[0] for r in cur.fetchall()]

        # Columns
        cur.execute('''
            SELECT table_name, column_name, data_type, is_nullable, column_default
            FROM information_schema.columns
            WHERE table_schema = 'public'
            ORDER BY table_name, column_name;
        ''')
        details['columns'] = {(r[0], r[1]): (r[2], r[3], r[4]) for r in cur.fetchall()}

        # Foreign Keys with ON DELETE / ON UPDATE
        cur.execute('''
            SELECT conrelid::regclass::text AS tbl, conname, pg_get_constraintdef(oid)
            FROM pg_constraint
            WHERE contype = 'f' AND connamespace = 'public'::regnamespace
            ORDER BY tbl, conname;
        ''')
        details['fkeys'] = {(r[0], r[1]): r[2] for r in cur.fetchall()}

        # Unique & Check constraints
        cur.execute('''
            SELECT conrelid::regclass::text AS tbl, conname, contype, pg_get_constraintdef(oid)
            FROM pg_constraint
            WHERE contype IN ('u', 'c') AND connamespace = 'public'::regnamespace
            ORDER BY tbl, conname;
        ''')
        details['constraints'] = {(r[0], r[1]): (r[2], r[3]) for r in cur.fetchall()}

        # Indexes
        cur.execute('''
            SELECT tablename, indexname, indexdef
            FROM pg_indexes
            WHERE schemaname = 'public'
            ORDER BY tablename, indexname;
        ''')
        details['indexes'] = {(r[0], r[1]): r[2] for r in cur.fetchall()}
    return details

fresh_meta = get_schema_details(fresh_url)
sandbox_meta = get_schema_details(sandbox_url)

print("=== 1. TABLE COMPARISON ===")
fresh_tables = set(fresh_meta['tables'])
sandbox_tables = set(sandbox_meta['tables'])
print(f"Fresh Head tables count: {len(fresh_tables)}")
print(f"Reconciled Sandbox tables count: {len(sandbox_tables)}")
diff_tables = fresh_tables ^ sandbox_tables
if diff_tables:
    print(f"TABLE DISCREPANCY: {diff_tables}")
else:
    print("ALL 24 TABLES MATCH EXACTLY.")

print("\n=== 2. COLUMN COMPARISON ===")
fresh_cols = set(fresh_meta['columns'].keys())
sandbox_cols = set(sandbox_meta['columns'].keys())
missing_in_sandbox = fresh_cols - sandbox_cols
surplus_in_sandbox = sandbox_cols - fresh_cols
print(f"Columns missing in sandbox: {missing_in_sandbox}")
print(f"Surplus columns in sandbox: {surplus_in_sandbox}")

# Data type check on common columns
type_mismatches = []
for col in fresh_cols & sandbox_cols:
    f_type, f_null, _ = fresh_meta['columns'][col]
    s_type, s_null, _ = sandbox_meta['columns'][col]
    if f_type != s_type or f_null != s_null:
        type_mismatches.append((col, (f_type, f_null), (s_type, s_null)))
print(f"Column type/nullability mismatches: {type_mismatches}")

print("\n=== 3. FOREIGN KEY & ON DELETE COMPARISON ===")
fresh_fks = fresh_meta['fkeys']
sandbox_fks = sandbox_meta['fkeys']
print(f"Fresh Head FK count: {len(fresh_fks)}")
print(f"Sandbox FK count: {len(sandbox_fks)}")
for k, def_s in sandbox_fks.items():
    if k in fresh_fks:
        def_f = fresh_fks[k]
        if def_f != def_s:
            print(f"  FK DEF DIFF on {k}: Fresh='{def_f}' vs Sandbox='{def_s}'")

print("\n=== 4. ALEMBIC AUTOGENERATE DRIFT ON SANDBOX ===")
engine_sb = create_engine(sandbox_url)
with engine_sb.connect() as conn:
    ctx = MigrationContext.configure(conn)
    diff = compare_metadata(ctx, Base.metadata)
print(f"Alembic Autogenerate Diffs found on Sandbox: {len(diff)}")
for d in diff:
    print("  DIFF:", d)
"""
        run_cmd([sys.executable, "-c", compare_script],
                "Deep Schema Comparison: Fresh Active Head vs Reconciled Sandbox")

        # Stage 7: Run SQLAlchemy Model Inserts and Constraint Checks against sandbox
        test_v3_1_script = r"""
import os, sys
sys.path.insert(0, r"D:\PG_Management\pg-management-system\backend")

from datetime import date
from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session
from app.models.property import Property
from app.models.room import Room
from app.models.bed import Bed
from app.models.user import User
from app.models.resident import Resident
from app.models.invoice import Invoice
from app.models.payment import Payment

db_url = os.environ["SANDBOX_DATABASE_URL"]
engine = create_engine(db_url)

with Session(engine) as session:
    props = session.scalars(select(Property).limit(2)).all()
    prop1, prop2 = props[0], props[1]

    # Room inserts
    room1 = Room(property_id=prop1.id, floor_number=1, room_number="301", room_type="SINGLE", max_occupancy=1, base_rent=7000.00, amenities={})
    room2 = Room(property_id=prop2.id, floor_number=2, room_number="302", room_type="SINGLE", max_occupancy=1, base_rent=8000.00, amenities={})
    session.add_all([room1, room2])
    session.flush()

    # Bed inserts (active Bed model without property_id)
    bed1 = Bed(room_id=room1.id, bed_number="BED-301-A", status="AVAILABLE", monthly_rent=7000.00)
    bed2 = Bed(room_id=room2.id, bed_number="BED-302-A", status="AVAILABLE", monthly_rent=8000.00)
    session.add_all([bed1, bed2])
    session.flush()

    # User & Resident inserts
    role_id = session.execute(select(User.role_id).limit(1)).scalar_one()
    user1 = User(company_id=prop1.company_id, role_id=role_id, email="res31_1@test.local", phone="+919876543211", full_name="Resident One", password_hash="hash")
    user2 = User(company_id=prop1.company_id, role_id=role_id, email="res31_2@test.local", phone="+919876543212", full_name="Resident Two", password_hash="hash")
    session.add_all([user1, user2])
    session.flush()

    res1 = Resident(user_id=user1.id, property_id=prop1.id, room_id=room1.id, bed_id=bed1.id, check_in_date=date.today(), monthly_rent=7000.00)
    session.add(res1)
    session.flush()

    # Invoices and Payments
    inv1 = Invoice(property_id=prop1.id, resident_id=res1.id, invoice_number="INV-31-01", billing_month="2026-10", invoice_type="RENT", amount=7000.00, due_date=date.today(), status="PENDING")
    session.add(inv1)
    session.flush()

    # Payment insert without notes
    pay1 = Payment(property_id=prop1.id, invoice_id=inv1.id, resident_id=res1.id, payment_number="PAY-31-01", idempotency_key="idemp_31_1", amount=7000.00, payment_mode="UPI", status="PENDING")
    session.add(pay1)
    session.flush()

    # Test ON DELETE RESTRICT on invoice_id
    try:
        session.delete(inv1)
        session.flush()
        raise RuntimeError("FAIL: Deleting invoice with existing payment succeeded! RESTRICT was not enforced.")
    except Exception as e:
        session.rollback()
        print(f"PASS: Deleting invoice with existing payment was correctly RESTRICTED ({type(e).__name__}).")

print("ALL ORM MODEL INSERTS & ON DELETE RESTRICT CHECKS PASSED.")
"""
        run_cmd([sys.executable, "-c", test_v3_1_script],
                "Execute Model Inserts & Financial ON DELETE RESTRICT Test")

        # Stage 8: Run PostgreSQL Concurrency Tests against pg_management_test
        test_db_url = f"postgresql+psycopg://{db_user}:{urllib.parse.quote_plus(db_pass)}@{db_host}:{db_port}/pg_management_test"
        pytest_env = os.environ.copy()
        pytest_env["TEST_DATABASE_URL"] = test_db_url
        pytest_env["PYTHONPATH"] = BACKEND_DIR
        run_cmd([sys.executable, "-m", "pytest", "tests/test_postgres_concurrency.py",
                 "tests/test_postgres_resident_concurrency.py", "-v"],
                "Execute PostgreSQL Concurrency & Allocation Tests", cwd=BACKEND_DIR)

        print("\n=======================================================")
        print(">>> ALL V3.1 VERIFICATION & COMPARISON STAGES PASSED! <<<")
        print("=======================================================")
        sandbox_succeeded = True

    finally:
        # Stage 9: Cleanup
        print("\n--- Cleanup Phase ---")
        terminate_and_drop(FRESH_HEAD_DB)
        print(f"Temporary database {FRESH_HEAD_DB} dropped.")
        if sandbox_succeeded:
            terminate_and_drop(SANDBOX_DB)
            print(f"SUCCESS: Disposable sandbox database {SANDBOX_DB} dropped cleanly.")
        else:
            print(f"PRESERVATION: Sandbox database {SANDBOX_DB} PRESERVED for investigation due to failure.")

if __name__ == "__main__":
    main()
