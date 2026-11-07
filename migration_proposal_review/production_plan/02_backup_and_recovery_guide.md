# PG Management — Production Backup & Disaster Recovery Guide

**Document:** `migration_proposal_review/production_plan/02_backup_and_recovery_guide.md`  
**Target Database:** `pg_management` (PostgreSQL 18.6 on `127.0.0.1:5432`)  
**Status:** READ-ONLY PLAN — ZERO CHANGES EXECUTED  

---

## 1. Absolute Safety Invariants

1. **Zero Overwrite Rule:** Never restore directly into or overwrite `pg_management` while in an uncertain state.
2. **Forensic Preservation:** Never drop a failed database before archiving it; rename it for forensic analysis.
3. **Pre-Flight Validation:** Never apply production migrations without first creating and verifying a restorable custom-format backup archive.

---

## 2. Step 1: Create Fresh Custom-Format Backup

Before any production reconciliation is authorized, execute a full PostgreSQL custom-format (`-Fc`) backup:

```powershell
# In PowerShell (Run as Administrator or Developer Session)
$PG_BIN = "C:\Program Files\PostgreSQL\18\bin"
$TIMESTAMP = (Get-Date).ToString("yyyyMMdd_HHmmss")
$BACKUP_DIR = "D:\PG_Management\backups"
if (!(Test-Path $BACKUP_DIR)) { New-Item -ItemType Directory -Path $BACKUP_DIR -Force }

$BACKUP_FILE = "$BACKUP_DIR\pg_management_pre_reconcile_$TIMESTAMP.dump"

# Securely extract PGPASSWORD without echoing
$env:PGPASSWORD = (Get-Content "D:\PG_Management\pg-management-system\backend\.env" | 
    Where-Object { $_ -match '^DATABASE_URL=.*://[^:]+:([^@]+)@' } | 
    ForEach-Object { [System.Uri]::UnescapeDataString($matches[1]) })

# Execute custom-format backup (includes blobs, schema, and table data)
& "$PG_BIN\pg_dump.exe" -h 127.0.0.1 -p 5432 -U postgres -Fc -b -v -f $BACKUP_FILE pg_management

if ($LASTEXITCODE -eq 0) {
    Write-Host "SUCCESS: Backup written to $BACKUP_FILE" -ForegroundColor Green
} else {
    Write-Error "CRITICAL: Backup failed with exit code $LASTEXITCODE"
}
```

---

## 3. Step 2: Validate Backup Integrity (Table of Contents)

Verify that the backup archive is uncorrupted and contains all essential database objects:

```powershell
# List TOC and verify key table data entries
& "$PG_BIN\pg_restore.exe" -l $BACKUP_FILE | Select-String -Pattern "TABLE DATA public (users|properties|companies|audit_logs|roles)"

# Confirm byte size is reasonable (> 50 KB)
$fileSize = (Get-Item $BACKUP_FILE).Length
Write-Host "Backup archive size: $fileSize bytes"
if ($fileSize -lt 40000) {
    Write-Error "Backup file unexpectedly small. Do not proceed."
}
```

---

## 4. Step 3: Disposable Sandbox Verification

Prove that the archive restores cleanly into a temporary, disposable database before touching production:

```powershell
$DISPOSABLE_TEST_DB = "pg_verify_restore_$TIMESTAMP"

try {
    # 1. Create disposable database
    & "$PG_BIN\createdb.exe" -h 127.0.0.1 -p 5432 -U postgres $DISPOSABLE_TEST_DB

    # 2. Restore archive into disposable database
    & "$PG_BIN\pg_restore.exe" -h 127.0.0.1 -p 5432 -U postgres -d $DISPOSABLE_TEST_DB --no-owner --role=postgres $BACKUP_FILE

    # 3. Verify record counts and alembic version in disposable database
    & "$PG_BIN\psql.exe" -h 127.0.0.1 -p 5432 -U postgres -d $DISPOSABLE_TEST_DB -c "
        SELECT 'companies' AS tbl, count(*) FROM companies
        UNION ALL SELECT 'roles', count(*) FROM roles
        UNION ALL SELECT 'properties', count(*) FROM properties
        UNION ALL SELECT 'users', count(*) FROM users
        UNION ALL SELECT 'user_property_access', count(*) FROM user_property_access
        UNION ALL SELECT 'refresh_tokens', count(*) FROM refresh_tokens
        UNION ALL SELECT 'audit_logs', count(*) FROM audit_logs
        UNION ALL SELECT 'alembic_version', count(*) FROM alembic_version;
        SELECT version_num FROM alembic_version;
    "

    # 4. Tear down disposable test database
    & "$PG_BIN\dropdb.exe" -h 127.0.0.1 -p 5432 -U postgres $DISPOSABLE_TEST_DB
    Write-Host "DISPOSABLE RESTORE VERIFIED AND CLEANED UP." -ForegroundColor Green
} finally {
    $env:PGPASSWORD = $null
}
```

---

## 5. Step 4: Disaster Recovery Protocol (If Any Migration Fails)

In the event that an authorized migration fails and cannot be rolled back in-transaction:

### Phase A: Isolate Application
```powershell
# Stop FastAPI backend service to cease incoming traffic
Stop-Process -Name "python" -Force -ErrorAction SilentlyContinue
```

### Phase B: Terminate Active Connections
```powershell
& "$PG_BIN\psql.exe" -h 127.0.0.1 -p 5432 -U postgres -d postgres -c "
    SELECT pg_terminate_backend(pid) 
    FROM pg_stat_activity 
    WHERE datname = 'pg_management' AND pid <> pg_backend_pid();
"
```

### Phase C: Forensic Database Renaming (Never Overwrite)
```powershell
$RENAME_TS = (Get-Date).ToString("yyyyMMdd_HHmmss")
& "$PG_BIN\psql.exe" -h 127.0.0.1 -p 5432 -U postgres -d postgres -c "
    ALTER DATABASE pg_management RENAME TO pg_management_failed_$RENAME_TS;
"
```

### Phase D: Clean Database Provisioning
```powershell
& "$PG_BIN\createdb.exe" -h 127.0.0.1 -p 5432 -U postgres pg_management
```

### Phase E: Restore Validated Pre-Migration Backup
```powershell
& "$PG_BIN\pg_restore.exe" -h 127.0.0.1 -p 5432 -U postgres -d pg_management --no-owner --role=postgres $BACKUP_FILE
```

### Phase F: Verify Restored Production State
```powershell
& "$PG_BIN\psql.exe" -h 127.0.0.1 -p 5432 -U postgres -d pg_management -c "
    SELECT 'companies' AS tbl, count(*) FROM companies
    UNION ALL SELECT 'roles', count(*) FROM roles
    UNION ALL SELECT 'properties', count(*) FROM properties
    UNION ALL SELECT 'users', count(*) FROM users
    UNION ALL SELECT 'user_property_access', count(*) FROM user_property_access
    UNION ALL SELECT 'refresh_tokens', count(*) FROM refresh_tokens
    UNION ALL SELECT 'audit_logs', count(*) FROM audit_logs;
    SELECT version_num FROM alembic_version;
"
# Expected:
# companies: 1, roles: 4, properties: 5, users: 4, user_property_access: 4, refresh_tokens: 8, audit_logs: 36
# version_num: 6cb475ecad6d
```

### Phase G: Restart Services
```powershell
# Restart backend application service
# Application resumes cleanly against restored pg_management baseline
```
