"""
Side-by-side reconciliation of table row counts across:
1. Live Database (pg_management)
2. Historical Backup (pg_management_backup_20261029.dump)
3. New Production Backup (pg_management_backup_20261030_120657.dump)
4. Reconciled V2 Sandbox (pg_reconcile_v2_sandbox_test)
"""

import os
import re
import urllib.parse
import subprocess
from pathlib import Path
import psycopg

BACKEND_DIR = Path("D:/PG_Management/pg-management-system/backend")
ENV_FILE = BACKEND_DIR / ".env"
PG_RESTORE_BIN = r"C:\Program Files\PostgreSQL\18\bin\pg_restore.exe"

content = ENV_FILE.read_text(encoding="utf-8")
for line in content.splitlines():
    m = re.match(r"^DATABASE_URL=.*://([^:]+):([^@]+)@([^:/]+)(?::(\d+))?/(.+)$", line)
    if m:
        u = m.group(1)
        p = urllib.parse.unquote(m.group(2))
        h = m.group(3)
        port = int(m.group(4) or 5432)
        live_db = m.group(5)
        break

env = os.environ.copy()
env["PGPASSWORD"] = p
maint_conn = f"postgresql://{u}:{urllib.parse.quote_plus(p)}@{h}:{port}/postgres"

# 1. Live counts
live_conn = f"postgresql://{u}:{urllib.parse.quote_plus(p)}@{h}:{port}/{live_db}"
live_counts = {}
with psycopg.connect(live_conn) as conn:
    with conn.cursor() as cur:
        cur.execute("SELECT table_name FROM information_schema.tables WHERE table_schema='public' ORDER BY table_name;")
        tables = [r[0] for r in cur.fetchall()]
        for t in tables:
            cur.execute(f"SELECT count(*) FROM {t};")
            live_counts[t] = cur.fetchone()[0]

# 2. Restore 20261029 dump to temp
with psycopg.connect(maint_conn, autocommit=True) as conn:
    with conn.cursor() as cur:
        cur.execute("DROP DATABASE IF EXISTS pg_temp_dump1;")
        cur.execute(f"CREATE DATABASE pg_temp_dump1 OWNER {u};")
subprocess.run([PG_RESTORE_BIN, "-h", h, "-p", str(port), "-U", u, "-d", "pg_temp_dump1", "--no-owner", "--no-acl", "D:/PG_Management/pg_management_backup_20261029.dump"], env=env, capture_output=True)

dump1_counts = {}
with psycopg.connect(f"postgresql://{u}:{urllib.parse.quote_plus(p)}@{h}:{port}/pg_temp_dump1") as conn:
    with conn.cursor() as cur:
        for t in tables:
            cur.execute(f"SELECT count(*) FROM {t};")
            dump1_counts[t] = cur.fetchone()[0]

# 3. Restore 20261030 dump to temp
with psycopg.connect(maint_conn, autocommit=True) as conn:
    with conn.cursor() as cur:
        cur.execute("DROP DATABASE IF EXISTS pg_temp_dump2;")
        cur.execute(f"CREATE DATABASE pg_temp_dump2 OWNER {u};")
subprocess.run([PG_RESTORE_BIN, "-h", h, "-p", str(port), "-U", u, "-d", "pg_temp_dump2", "--no-owner", "--no-acl", "D:/PG_Management/production_backups/pg_management_backup_20261030_120657.dump"], env=env, capture_output=True)

dump2_counts = {}
with psycopg.connect(f"postgresql://{u}:{urllib.parse.quote_plus(p)}@{h}:{port}/pg_temp_dump2") as conn:
    with conn.cursor() as cur:
        for t in tables:
            cur.execute(f"SELECT count(*) FROM {t};")
            dump2_counts[t] = cur.fetchone()[0]

# 4. Check sandbox pg_reconcile_v2_sandbox_test
sandbox_counts = {}
with psycopg.connect(f"postgresql://{u}:{urllib.parse.quote_plus(p)}@{h}:{port}/pg_reconcile_v2_sandbox_test") as conn:
    with conn.cursor() as cur:
        for t in tables:
            cur.execute(f"SELECT count(*) FROM {t};")
            sandbox_counts[t] = cur.fetchone()[0]

# Clean up temps
with psycopg.connect(maint_conn, autocommit=True) as conn:
    with conn.cursor() as cur:
        cur.execute("DROP DATABASE IF EXISTS pg_temp_dump1;")
        cur.execute("DROP DATABASE IF EXISTS pg_temp_dump2;")

col1 = "Table Name"
col2 = "Live DB"
col3 = "Dump 2026-10-29"
col4 = "Dump 2026-10-30"
col5 = "V2 Sandbox"
col6 = "Identical?"

print(f"| {col1:22} | {col2:10} | {col3:15} | {col4:15} | {col5:12} | {col6:10} |")
print("|" + "-"*24 + "|" + "-"*12 + "|" + "-"*17 + "|" + "-"*17 + "|" + "-"*14 + "|" + "-"*12 + "|")
all_match = True
for t in tables:
    c_live = live_counts[t]
    c_d1 = dump1_counts[t]
    c_d2 = dump2_counts[t]
    c_sb = sandbox_counts[t]
    match = (c_live == c_d1 == c_d2 == c_sb)
    if not match:
        all_match = False
    print(f"| {t:22} | {c_live:10} | {c_d1:15} | {c_d2:15} | {c_sb:12} | {str(match):10} |")

tot_live = sum(live_counts.values())
tot_d1 = sum(dump1_counts.values())
tot_d2 = sum(dump2_counts.values())
tot_sb = sum(sandbox_counts.values())

print("|" + "-"*24 + "|" + "-"*12 + "|" + "-"*17 + "|" + "-"*17 + "|" + "-"*14 + "|" + "-"*12 + "|")
print(f"| {'TOTAL ALL ROWS':22} | {tot_live:10} | {tot_d1:15} | {tot_d2:15} | {tot_sb:12} | {str(all_match):10} |")

# Breakdown by Business Entities vs Audit Logs vs Alembic Metadata
biz_tables = ['companies', 'roles', 'properties', 'users', 'user_property_access', 'refresh_tokens', 'rooms', 'beds', 'residents', 'invoices', 'payments']
biz_live = sum(live_counts[t] for t in biz_tables)
audit_live = live_counts['audit_logs']
meta_live = live_counts['alembic_version']

print("\n--- Categorical Classification ---")
print(f"1. Core Business Records (excluding audit logs & alembic_version) : {biz_live}")
print(f"2. Audit Log Records (immutable security ledger)                  : {audit_live}")
print(f"3. Migration Metadata Records (alembic_version)                   : {meta_live}")
print(f"   Grand Total Physical Database Records                          : {biz_live + audit_live + meta_live}")
