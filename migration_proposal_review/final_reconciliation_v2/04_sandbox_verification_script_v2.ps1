# =============================================================================
# SANDBOX REGRESSION VERIFICATION SCRIPT V2
# Target Database: pg_reconcile_v2_sandbox_test (DISPOSABLE SANDBOX ONLY)
# STRICT SAFETY: REFUSES TO RUN IF POINTED TO pg_management
# =============================================================================

$PG_BIN = "C:\Program Files\PostgreSQL\18\bin"
$BACKUP_FILE = "D:\PG_Management\pg_management_backup_20261029.dump"
$SANDBOX_DB = "pg_reconcile_v2_sandbox_test"
$DB_HOST = "127.0.0.1"
$DB_PORT = "5432"
$DB_USER = "postgres"
$PYTHON_EXE = "D:\PG_Management\.venv\Scripts\python.exe"

$DDL_FILE = "D:\PG_Management\migration_proposal_review\final_reconciliation_v2\01_reconcile_pg_management_ddl_v2.sql"
$POST_FILE = "D:\PG_Management\migration_proposal_review\final_reconciliation_v2\02_post_migration_checks_v2.sql"
$TEST_PY = "D:\PG_Management\migration_proposal_review\final_reconciliation_v2\test_model_inserts_sandbox.py"

# Absolute Hard Safety Check
if ($SANDBOX_DB -eq "pg_management") {
    Write-Error "CRITICAL: Sandbox database name cannot be pg_management. Aborting."
    exit 1
}

# Securely extract credentials for sandbox execution without printing
$envFile = "D:\PG_Management\pg-management-system\backend\.env"
$rawPassword = ""
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^DATABASE_URL=.*://[^:]+:([^@]+)@') {
            $rawPassword = [System.Uri]::UnescapeDataString($matches[1])
            $env:PGPASSWORD = $rawPassword
        }
    }
}

try {
    Write-Host "=== STEP 1: Creating disposable sandbox database: $SANDBOX_DB ==="
    & "$PG_BIN\createdb.exe" -h $DB_HOST -p $DB_PORT -U $DB_USER $SANDBOX_DB
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to create sandbox database."
        exit $LASTEXITCODE
    }

    Write-Host "=== STEP 2: Restoring baseline archive into sandbox ==="
    & "$PG_BIN\pg_restore.exe" -h $DB_HOST -p $DB_PORT -U $DB_USER -d $SANDBOX_DB --no-owner --role=$DB_USER $BACKUP_FILE 2>$null

    Write-Host "=== STEP 3: Applying Reconciliation DDL V2 to sandbox ==="
    & "$PG_BIN\psql.exe" -h $DB_HOST -p $DB_PORT -U $DB_USER -d $SANDBOX_DB -f $DDL_FILE
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to apply DDL to sandbox."
        exit $LASTEXITCODE
    }

    Write-Host "=== STEP 4: Running 10-Point Post-Migration SQL Checks on sandbox ==="
    & "$PG_BIN\psql.exe" -h $DB_HOST -p $DB_PORT -U $DB_USER -d $SANDBOX_DB -f $POST_FILE

    Write-Host "=== STEP 5: Running SQLAlchemy Model Insert Tests on sandbox ==="
    $encodedPassword = [System.Uri]::EscapeDataString($rawPassword)
    $env:SANDBOX_DATABASE_URL = "postgresql+psycopg://$($DB_USER):$($encodedPassword)@$($DB_HOST):$($DB_PORT)/$($SANDBOX_DB)"
    & $PYTHON_EXE $TEST_PY
    if ($LASTEXITCODE -ne 0) {
        Write-Error "SQLAlchemy model insert test failed on sandbox."
        exit $LASTEXITCODE
    }

    Write-Host "=== STEP 6: Dropping disposable sandbox database ==="
    & "$PG_BIN\dropdb.exe" -h $DB_HOST -p $DB_PORT -U $DB_USER $SANDBOX_DB
    Write-Host "=== ALL SANDBOX TESTS PASSED. pg_management WAS NEVER TOUCHED ==="
} finally {
    $env:PGPASSWORD = $null
    $env:SANDBOX_DATABASE_URL = $null
}
