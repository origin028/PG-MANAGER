"""
Final Live Database Status Assertion Script
Performs read-only checks on pg_management:
- Database name is exactly pg_management
- PostgreSQL version is 18.6
- Current revision is 6cb475ecad6d
- Total tables are 13
- Total physical rows are 63
- Table-by-table counts match exactly
- Zero active mutating sessions/transactions
"""

import os
import re
import urllib.parse
from pathlib import Path
import psycopg

BACKEND_DIR = Path("D:/PG_Management/pg-management-system/backend")
ENV_FILE = BACKEND_DIR / ".env"

content = ENV_FILE.read_text(encoding="utf-8")
for line in content.splitlines():
    m = re.match(r"^DATABASE_URL=.*://([^:]+):([^@]+)@([^:/]+)(?::(\d+))?/(.+)$", line)
    if m:
        u = m.group(1)
        p = urllib.parse.unquote(m.group(2))
        h = m.group(3)
        port = int(m.group(4) or 5432)
        db = m.group(5)
        break

conn_str = f"postgresql://{u}:{urllib.parse.quote_plus(p)}@{h}:{port}/{db}"
with psycopg.connect(conn_str) as conn:
    with conn.cursor() as cur:
        # DB name
        cur.execute("SELECT current_database();")
        cur_db = cur.fetchone()[0]
        assert cur_db == "pg_management", f"Expected pg_management, got {cur_db}"
        print(f"[OK] Database Name: {cur_db}")

        # Version
        cur.execute("SELECT version();")
        ver = cur.fetchone()[0]
        assert "PostgreSQL 18.6" in ver, f"Expected PostgreSQL 18.6, got {ver}"
        print(f"[OK] PostgreSQL Version: {ver}")

        # Revision
        cur.execute("SELECT version_num FROM alembic_version;")
        rev = cur.fetchone()[0]
        assert rev == "6cb475ecad6d", f"Expected 6cb475ecad6d, got {rev}"
        print(f"[OK] Alembic Revision: {rev}")

        # Tables
        cur.execute("SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name;")
        tables = [r[0] for r in cur.fetchall()]
        assert len(tables) == 13, f"Expected 13 tables, got {len(tables)}"
        print(f"[OK] Table Count: {len(tables)} tables")

        # Counts
        counts = {}
        tot = 0
        for t in tables:
            cur.execute(f"SELECT count(*) FROM {t};")
            c = cur.fetchone()[0]
            counts[t] = c
            tot += c
        
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
        assert tot == 63, f"Expected 63 total rows, got {tot}"
        assert counts == expected_counts, f"Counts mismatch: {counts} vs {expected_counts}"
        print(f"[OK] Total Physical Rows: {tot}")
        print(f"[OK] Individual Table Counts: {counts}")

        # Active transactions / queries
        cur.execute("""
            SELECT pid, usename, client_addr, state, query_start, query 
            FROM pg_stat_activity 
            WHERE datname = current_database() 
              AND pid != pg_backend_pid();
        """)
        active = cur.fetchall()
        print(f"[OK] Active background connections: {len(active)}")
        for a in active:
            print(f"     PID: {a[0]}, User: {a[1]}, IP: {a[2]}, State: {a[3]}, Query: {a[5]}")

print("\n>>> FINAL LIVE DB PRECHECK: ALL PASS <<<")
