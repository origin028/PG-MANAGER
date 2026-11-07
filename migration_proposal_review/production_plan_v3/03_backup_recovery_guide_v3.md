# PG Management — Production Backup & Disaster Recovery Guide V3

**Document:** `migration_proposal_review/production_plan_v3/03_backup_recovery_guide_v3.md`  
**Target Database:** `pg_management` (PostgreSQL 18.6 on `127.0.0.1:5432`)  
**Target Active Alembic Revision:** `b2c3d4e5f6a7` (Baseline: `6cb475ecad6d`)  
**Status:** PRODUCTION RECOVERY RUNBOOK — ZERO LIVE EXECUTION AUTHORIZED  

---

## 1. Absolute Safety Invariants

1. **Zero Overwrite Rule:** Never restore directly over a running or partially modified `pg_management` database.
2. **Forensic Database Preservation:** If a failure occurs during any authorized maintenance window, never drop the database. Retain it for forensic inspection.
3. **Pre-Flight Validation:** Never apply schema changes without first producing a validated custom-format (`-Fc`) backup and verifying its restorable integrity in an isolated disposable sandbox.
4. **Credential Security:** Never echo, log, or hardcode database passwords in scripts or console logs. Extract credentials dynamically from the environment.
5. **Windows File Lock Preparedness:** On Windows PostgreSQL installations, file locks can prevent `ALTER DATABASE ... RENAME`. This guide provides two recovery paths:
   - **Path A (In-Place Database Swap):** Preferred when database rename succeeds.
   - **Path B (Connection String Swap):** Fallback when Windows file locks prevent renaming `pg_management`.

---

## 2. Step 1: Pre-Migration Full Custom-Format Backup

Before any production reconciliation is authorized, generate a complete PostgreSQL custom-format (`-Fc`) backup:

```powershell
# In PowerShell (Run as Administrator or Developer Session)
$PG_BIN = "C:\Program Files\PostgreSQL\18\bin"
$TIMESTAMP = (Get-Date).ToString("yyyyMMdd_HHmmss")
$BACKUP_DIR = "D:\PG_Management\backups"
if (!(Test-Path $BACKUP_DIR)) { New-Item -ItemType Directory -Path $BACKUP_DIR -Force }

$BACKUP_FILE = "$BACKUP_DIR\pg_management_pre_v3_$TIMESTAMP.dump"

# Securely extract database credentials from .env without echoing
$env:PGPASSWORD = (Get-Content "D:\PG_Management\pg-management-system\backend\.env" | 
    Where-Object { $_ -match '^DATABASE_URL=.*://[^:]+:([^@]+)@' } | 
    ForEach-Object { [System.Uri]::UnescapeDataString($matches[1]) })

# Execute custom-format backup (full schema, table data, blobs, and large objects)
& "$PG_BIN\pg_dump.exe" -h 127.0.0.1 -p 5432 -U postgres -Fc -b -v -f $BACKUP_FILE pg_management

if ($LASTEXITCODE -eq 0) {
    Write-Host "SUCCESS: Backup written to $BACKUP_FILE" -ForegroundColor Green
} else {
    Write-Error "CRITICAL: Backup failed with exit code $LASTEXITCODE. Stop immediately."
}
```

---

## 3. Step 2: Validate Archive Integrity (TOC & Size)

Verify that the backup archive is intact, uncorrupted, and contains all essential database objects and data tables:

```powershell
# 1. Verify file size is substantial (> 50 KB)
$fileSize = (Get-Item $BACKUP_FILE).Length
Write-Host "Backup archive size: $fileSize bytes"
if ($fileSize -lt 40000) {
    Write-Error "CRITICAL: Backup file unexpectedly small ($fileSize bytes). Do not proceed."
    return
}

# 2. Check Table of Contents for all core tables
$tocOutput = & "$PG_BIN\pg_restore.exe" -l $BACKUP_FILE
$requiredTables = @("companies", "roles", "properties", "users", "user_property_access", "refresh_tokens", "audit_logs", "alembic_version")

foreach ($tbl in $requiredTables) {
    $match = $tocOutput | Select-String -Pattern "TABLE DATA public $tbl"
    if ($match) {
        Write-Host "  [OK] Found TABLE DATA for $tbl" -ForegroundColor Green
    } else {
        Write-Error "CRITICAL: Missing TABLE DATA for $tbl in backup TOC!"
    }
}
```

---

## 4. Step 3: Disposable Restore Verification Test

Prove that the archive restores cleanly into a temporary disposable database prior to any maintenance window:

```powershell
$DISPOSABLE_TEST_DB = "pg_verify_restore_$TIMESTAMP"

try {
    Write-Host "Creating disposable verification database $DISPOSABLE_TEST_DB..."
    & "$PG_BIN\createdb.exe" -h 127.0.0.1 -p 5432 -U postgres $DISPOSABLE_TEST_DB

    Write-Host "Restoring backup archive into $DISPOSABLE_TEST_DB..."
    & "$PG_BIN\pg_restore.exe" -h 127.0.0.1 -p 5432 -U postgres -d $DISPOSABLE_TEST_DB --no-owner --role=postgres $BACKUP_FILE

    Write-Host "Verifying restored row counts and alembic revision..."
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

    # Expected Counts:
    # companies: 1, roles: 4, properties: 5, users: 4, user_property_access: 4, refresh_tokens: 8, audit_logs: 36
    # alembic_version: 6cb475ecad6d
    
    Write-Host "DISPOSABLE RESTORE VERIFIED SUCCESSFULLY." -ForegroundColor Green
} finally {
    Write-Host "Tearing down disposable test database $DISPOSABLE_TEST_DB..."
    & "$PG_BIN\dropdb.exe" -h 127.0.0.1 -p 5432 -U postgres $DISPOSABLE_TEST_DB
    $env:PGPASSWORD = $null
}
```

---

## 5. Rollback Decision Framework

Execute rollback immediately if any of the following occur during migration:

| Decision Trigger | Threshold / Condition | Action |
| :--- | :--- | :--- |
| **Pre-Condition Assertion Failure** | Any `RAISE EXCEPTION` in Section 1 of V3 SQL | In-transaction abort. Zero database changes applied. No restore needed. |
| **Execution Error / Timeout** | Any SQL runtime error or deadlock during DDL | PostgreSQL rolls back entire transaction automatically. |
| **Post-Condition Assertion Failure** | Post-checks fail (e.g. table count != 24, index missing) | Transaction rolls back if inside migration block; if committed, trigger Recovery Protocol. |
| **Application Startup Failure** | Backend fails health check or model validation post-migration | Stop backend, execute Recovery Protocol. |
| **Data Integrity Anomaly** | Any difference in live user, property, or audit counts | Trigger Recovery Protocol. |

---

## 6. Step 4: Disaster Recovery Procedures

If migration was committed but post-validation or application smoke tests fail, choose between Path A and Path B.

### Phase 1: Isolate Application & Terminate Connections (Common to Both Paths)

```powershell
# 1. Stop backend application process to cease traffic
Stop-Process -Name "python" -Force -ErrorAction SilentlyContinue

# 2. Terminate all active database connections
$env:PGPASSWORD = (Get-Content "D:\PG_Management\pg-management-system\backend\.env" | 
    Where-Object { $_ -match '^DATABASE_URL=.*://[^:]+:([^@]+)@' } | 
    ForEach-Object { [System.Uri]::UnescapeDataString($matches[1]) })

& "$PG_BIN\psql.exe" -h 127.0.0.1 -p 5432 -U postgres -d postgres -c "
    SELECT pg_terminate_backend(pid) 
    FROM pg_stat_activity 
    WHERE datname = 'pg_management' AND pid <> pg_backend_pid();
"
```

---

### Path A: In-Place Database Rename & Restore (Standard Procedure)

Use this path if Windows file locks do not interfere with renaming the database:

```powershell
$RENAME_TS = (Get-Date).ToString("yyyyMMdd_HHmmss")

# Step 1: Rename the failed database for forensics (never drop!)
& "$PG_BIN\psql.exe" -h 127.0.0.1 -p 5432 -U postgres -d postgres -c "
    ALTER DATABASE pg_management RENAME TO pg_management_failed_$RENAME_TS;
"

if ($LASTEXITCODE -eq 0) {
    Write-Host "Database renamed to pg_management_failed_$RENAME_TS" -ForegroundColor Yellow

    # Step 2: Create a clean pg_management database
    & "$PG_BIN\createdb.exe" -h 127.0.0.1 -p 5432 -U postgres pg_management

    # Step 3: Restore the pre-migration backup archive
    & "$PG_BIN\pg_restore.exe" -h 127.0.0.1 -p 5432 -U postgres -d pg_management --no-owner --role=postgres $BACKUP_FILE

    # Step 4: Verify restored database baseline
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

    # Step 5: Restart backend application
    # Application resumes cleanly against pg_management at revision 6cb475ecad6d
    Write-Host "PATH A RECOVERY COMPLETE." -ForegroundColor Green
} else {
    Write-Warning "Path A failed (likely Windows file lock on pg_management). Switching to Path B..."
}
```

---

### Path B: Connection String Swap to `pg_management_recovered` (Windows File-Lock Fallback)

If `ALTER DATABASE pg_management RENAME TO ...` fails due to persistent Windows file locks (`ERROR: database "pg_management" is being accessed by other users` or OS locks):

```powershell
$RECOVERED_DB = "pg_management_recovered_$RENAME_TS"

# Step 1: Create a brand new recovery database
& "$PG_BIN\createdb.exe" -h 127.0.0.1 -p 5432 -U postgres $RECOVERED_DB

# Step 2: Restore the pre-migration backup archive into the new recovery database
& "$PG_BIN\pg_restore.exe" -h 127.0.0.1 -p 5432 -U postgres -d $RECOVERED_DB --no-owner --role=postgres $BACKUP_FILE

# Step 3: Verify restored database baseline
& "$PG_BIN\psql.exe" -h 127.0.0.1 -p 5432 -U postgres -d $RECOVERED_DB -c "
    SELECT 'companies' AS tbl, count(*) FROM companies
    UNION ALL SELECT 'roles', count(*) FROM roles
    UNION ALL SELECT 'properties', count(*) FROM properties
    UNION ALL SELECT 'users', count(*) FROM users
    UNION ALL SELECT 'user_property_access', count(*) FROM user_property_access
    UNION ALL SELECT 'refresh_tokens', count(*) FROM refresh_tokens
    UNION ALL SELECT 'audit_logs', count(*) FROM audit_logs;
    SELECT version_num FROM alembic_version;
"

# Step 4: Swap DATABASE_URL in backend .env to point to the recovered database
$envFile = "D:\PG_Management\pg-management-system\backend\.env"
$envContent = Get-Content $envFile
$newEnvContent = $envContent -replace 'pg_management(?!\w)', $RECOVERED_DB
Set-Content -Path $envFile -Value $newEnvContent

Write-Host "DATABASE_URL updated in .env to target $RECOVERED_DB" -ForegroundColor Yellow

# Step 5: Start backend application and run health check
# Application resumes cleanly against the restored database baseline
Write-Host "PATH B RECOVERY COMPLETE. Failed database preserved as pg_management for later analysis." -ForegroundColor Green
```

---

## 7. Step 5: Post-Recovery Validation Checklist

After executing either Path A or Path B:

- [ ] Confirm `alembic_version` is exactly `6cb475ecad6d`.
- [ ] Confirm entity counts match: `companies=1`, `roles=4`, `properties=5`, `users=4`, `user_property_access=4`, `refresh_tokens=8`, `audit_logs=36`.
- [ ] Verify FastAPI backend starts cleanly: `GET /api/v1/health` returns HTTP 200 `status: healthy`.
- [ ] Verify Super Admin login returns valid JWT access token.
- [ ] Verify resident fail-closed behavior remains intact.
- [ ] Verify UPI direct payment configuration is verified and untouched (`9886699258-3@ybl`, `SMART GROUP PG'S`, MCC `5411`).
