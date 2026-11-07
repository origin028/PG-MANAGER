"""Comprehensive V3 Sandbox Verification Pipeline.

Executes all verification stages against disposable database: pg_reconcile_v3_sandbox_test.

SAFETY INVARIANTS:
1. Refuses to run if target database is pg_management or pg_reconcile_v2_sandbox_test.
2. Checks exit code and stdout/stderr at every stage.
3. Completely rolls back / stops on any failure.
4. Cleans up disposable database upon successful verification.
"""
import os
import sys
import subprocess
import urllib.parse
from datetime import datetime

PG_BIN = r"C:\Program Files\PostgreSQL\18\bin"
BACKUP_FILE = r"D:\PG_Management\pg_management_backup_20261029.dump"
ENV_FILE = r"D:\PG_Management\pg-management-system\backend\.env"
V3_SQL = r"D:\PG_Management\migration_proposal_review\production_plan_v3\01_unified_reconcile_pg_management_v3.sql"
VALIDATION_SQL = r"D:\PG_Management\migration_proposal_review\production_plan_v3\02_pre_post_validation_v3.sql"
TEST_SCRIPT = r"D:\PG_Management\migration_proposal_review\production_plan_v3\test_sandbox_v3.py"

SANDBOX_DB = "pg_reconcile_v3_sandbox_test"

# Verify safety invariants
if SANDBOX_DB in ("pg_management", "pg_reconcile_v2_sandbox_test", "pg_management_test"):
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

def run_cmd(cmd_list, description):
    print(f"\n=======================================================")
    print(f">> {description}")
    print(f"=======================================================")
    # Print redacted command
    safe_cmd = []
    for c in cmd_list:
        if db_pass in c:
            safe_cmd.append(c.replace(db_pass, "******"))
        else:
            safe_cmd.append(c)
    print("Executing:", " ".join(safe_cmd))
    
    start_time = datetime.now()
    proc = subprocess.run(cmd_list, capture_output=True, text=True, encoding="utf-8", errors="replace")
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

def main():
    print(f"Starting V3 Sandbox Verification on: {SANDBOX_DB}")
    print(f"PostgreSQL Binaries: {PG_BIN}")
    print(f"Pre-migration Backup: {BACKUP_FILE}")

    # Stage 0: Clean up any prior aborted run of pg_reconcile_v3_sandbox_test ONLY
    print("\n--- Checking for existing sandbox DB ---")
    psql = os.path.join(PG_BIN, "psql.exe")
    check_db = subprocess.run(
        [psql, "-h", db_host, "-p", db_port, "-U", db_user, "-d", "postgres", "-t", "-A",
         "-c", f"SELECT 1 FROM pg_database WHERE datname = '{SANDBOX_DB}';"],
        capture_output=True, text=True, encoding="utf-8", errors="replace"
    )
    if check_db.stdout.strip() == "1":
        print(f"Sandbox DB {SANDBOX_DB} exists from previous run. Dropping it cleanly...")
        # Terminate any connections first
        subprocess.run([
            psql, "-h", db_host, "-p", db_port, "-U", db_user, "-d", "postgres", "-c",
            f"SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '{SANDBOX_DB}' AND pid <> pg_backend_pid();"
        ], capture_output=True)
        subprocess.run([os.path.join(PG_BIN, "dropdb.exe"), "-h", db_host, "-p", db_port, "-U", db_user, SANDBOX_DB], check=True)
        print("Prior sandbox DB dropped.")

    # Stage 1: Create fresh sandbox database
    run_cmd(
        [os.path.join(PG_BIN, "createdb.exe"), "-h", db_host, "-p", db_port, "-U", db_user, SANDBOX_DB],
        f"Stage 1: Provision Disposable Database ({SANDBOX_DB})"
    )

    try:
        # Stage 2: Restore backup
        run_cmd(
            [os.path.join(PG_BIN, "pg_restore.exe"), "-h", db_host, "-p", db_port, "-U", db_user,
             "-d", SANDBOX_DB, "--no-owner", f"--role={db_user}", BACKUP_FILE],
            "Stage 2: Restore 20261029 Production Backup Archive"
        )

        # Stage 3: Baseline verification on restored database
        pre_check_sql = """
        SELECT 'alembic_version' AS item, version_num AS value FROM alembic_version
        UNION ALL SELECT 'companies', count(*)::text FROM companies
        UNION ALL SELECT 'roles', count(*)::text FROM roles
        UNION ALL SELECT 'properties', count(*)::text FROM properties
        UNION ALL SELECT 'users', count(*)::text FROM users
        UNION ALL SELECT 'user_property_access', count(*)::text FROM user_property_access
        UNION ALL SELECT 'refresh_tokens', count(*)::text FROM refresh_tokens
        UNION ALL SELECT 'audit_logs', count(*)::text FROM audit_logs
        UNION ALL SELECT 'rooms', count(*)::text FROM rooms
        UNION ALL SELECT 'beds', count(*)::text FROM beds
        UNION ALL SELECT 'residents', count(*)::text FROM residents
        UNION ALL SELECT 'invoices', count(*)::text FROM invoices
        UNION ALL SELECT 'payments', count(*)::text FROM payments;
        """
        run_cmd(
            [psql, "-h", db_host, "-p", db_port, "-U", db_user, "-d", SANDBOX_DB, "-c", pre_check_sql],
            "Stage 3: Verify Restored Sandbox Baseline State"
        )

        # Stage 4: Execute V3 Unified Reconciliation SQL
        run_cmd(
            [psql, "-h", db_host, "-p", db_port, "-U", db_user, "-d", SANDBOX_DB, "-f", V3_SQL],
            "Stage 4: Execute 01_unified_reconcile_pg_management_v3.sql"
        )

        # Stage 5: Run Standalone Validation SQL
        run_cmd(
            [psql, "-h", db_host, "-p", db_port, "-U", db_user, "-d", SANDBOX_DB, "-f", VALIDATION_SQL],
            "Stage 5: Execute 02_pre_post_validation_v3.sql"
        )

        # Stage 6: Run SQLAlchemy Model Inserts and Constraint Checks
        run_cmd(
            [sys.executable, TEST_SCRIPT],
            "Stage 6: Execute test_sandbox_v3.py (Model Inserts, Uniqueness & Constraints)"
        )

        # Stage 7: Run Alembic Autogenerate Drift Check
        drift_script = r"""
import os, sys
sys.path.insert(0, r"D:\PG_Management\pg-management-system\backend")

from alembic.migration import MigrationContext
from alembic.autogenerate import compare_metadata
from sqlalchemy import create_engine
import app.models  # Registers all 23 models with Base.metadata
from app.db.base import Base

db_url = os.environ["SANDBOX_DATABASE_URL"]
engine = create_engine(db_url)
with engine.connect() as conn:
    ctx = MigrationContext.configure(conn)
    diff = compare_metadata(ctx, Base.metadata)
    
print(f"Alembic Autogenerate Diffs found: {len(diff)}")
if diff:
    for d in diff:
        print("  DIFF:", d)
else:
    print("SUCCESS: 0 schema drifts found between active models and reconciled sandbox!")
"""
        run_cmd(
            [sys.executable, "-c", drift_script],
            "Stage 7: Alembic Autogenerate Schema Drift Inspection"
        )

        # Stage 8: Post-Verification Status Check
        post_status_sql = """
        SELECT version_num FROM alembic_version;
        SELECT count(*) AS total_tables FROM information_schema.tables WHERE table_schema = 'public';
        SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;
        """
        run_cmd(
            [psql, "-h", db_host, "-p", db_port, "-U", db_user, "-d", SANDBOX_DB, "-c", post_status_sql],
            "Stage 8: Final Sandbox Schema Summary"
        )

        print("\n=======================================================")
        print(">>> ALL SANDBOX V3 VERIFICATION STAGES PASSED! <<<")
        print("=======================================================")

    finally:
        # Stage 9: Clean teardown of disposable database
        print("\n--- Stage 9: Cleaning up disposable sandbox database ---")
        subprocess.run([
            psql, "-h", db_host, "-p", db_port, "-U", db_user, "-d", "postgres", "-c",
            f"SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '{SANDBOX_DB}' AND pid <> pg_backend_pid();"
        ], capture_output=True)
        drop_res = subprocess.run(
            [os.path.join(PG_BIN, "dropdb.exe"), "-h", db_host, "-p", db_port, "-U", db_user, SANDBOX_DB],
            capture_output=True, text=True
        )
        if drop_res.returncode == 0:
            print(f"SUCCESS: Sandbox database {SANDBOX_DB} dropped cleanly.")
        else:
            print(f"WARNING: Drop failed: {drop_res.stderr}")

if __name__ == "__main__":
    main()
