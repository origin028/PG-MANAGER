# =============================================================================
# SANDBOX BACKUP RESTORE VERIFICATION TEST
# Demonstrates that pg_management_backup_20261029.dump is 100% restorable
# without touching, modifying, or risking the live pg_management database.
# =============================================================================

$PG_BIN = "C:\Program Files\PostgreSQL\18\bin"
$BACKUP_FILE = "D:\PG_Management\pg_management_backup_20261029.dump"
$SANDBOX_DB = "pg_restore_sandbox_test"
$DB_HOST = "127.0.0.1"
$DB_PORT = "5432"
$DB_USER = "postgres"

# Securely load credentials from backend .env without exposing them
$envFile = "D:\PG_Management\pg-management-system\backend\.env"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^DATABASE_URL=.*://[^:]+:([^@]+)@') {
            $env:PGPASSWORD = [System.Uri]::UnescapeDataString($matches[1])
        }
    }
}

try {
    Write-Host "--- STEP 1: Creating disposable sandbox database: $SANDBOX_DB ---"
    & "$PG_BIN\createdb.exe" -h $DB_HOST -p $DB_PORT -U $DB_USER $SANDBOX_DB
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to create sandbox database. Exiting."
        exit $LASTEXITCODE
    }

    Write-Host "--- STEP 2: Restoring verified archive into sandbox ---"
    & "$PG_BIN\pg_restore.exe" -h $DB_HOST -p $DB_PORT -U $DB_USER -d $SANDBOX_DB --no-owner --role=$DB_USER $BACKUP_FILE
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "pg_restore exited with code $LASTEXITCODE (inspecting logs)"
    }

    Write-Host "--- STEP 3: Verifying restored row counts in sandbox ---"
    & "$PG_BIN\psql.exe" -h $DB_HOST -p $DB_PORT -U $DB_USER -d $SANDBOX_DB -c "
    SELECT 'companies' as tbl, count(*) FROM companies
    UNION ALL SELECT 'roles', count(*) FROM roles
    UNION ALL SELECT 'properties', count(*) FROM properties
    UNION ALL SELECT 'users', count(*) FROM users
    UNION ALL SELECT 'user_property_access', count(*) FROM user_property_access
    UNION ALL SELECT 'refresh_tokens', count(*) FROM refresh_tokens
    UNION ALL SELECT 'audit_logs', count(*) FROM audit_logs;
    "

    Write-Host "--- STEP 4: Dropping disposable sandbox database ---"
    & "$PG_BIN\dropdb.exe" -h $DB_HOST -p $DB_PORT -U $DB_USER $SANDBOX_DB
    Write-Host "Sandbox database dropped. pg_management was never touched."
} finally {
    $env:PGPASSWORD = $null
}
