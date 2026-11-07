-- =============================================================================
-- PREFLIGHT VALIDATION CHECKS (READ-ONLY)
-- Run against pg_management prior to applying the reconciliation DDL
-- =============================================================================

-- 1. Check existing table row counts
SELECT 'companies' AS table_name, count(*) AS row_count FROM companies
UNION ALL SELECT 'roles', count(*) FROM roles
UNION ALL SELECT 'properties', count(*) FROM properties
UNION ALL SELECT 'users', count(*) FROM users
UNION ALL SELECT 'user_property_access', count(*) FROM user_property_access
UNION ALL SELECT 'refresh_tokens', count(*) FROM refresh_tokens
UNION ALL SELECT 'audit_logs', count(*) FROM audit_logs
UNION ALL SELECT 'invoices', count(*) FROM invoices
UNION ALL SELECT 'payments', count(*) FROM payments
UNION ALL SELECT 'residents', count(*) FROM residents
UNION ALL SELECT 'rooms', count(*) FROM rooms
UNION ALL SELECT 'beds', count(*) FROM beds
ORDER BY table_name;

-- 2. Verify current Alembic version
SELECT version_num FROM alembic_version;

-- 3. Confirm target database name
SELECT current_database(), current_user, inet_server_addr(), inet_server_port();

-- 4. Check for any unexpected active table locks
SELECT pid, mode, granted, query 
FROM pg_locks l 
JOIN pg_stat_activity a ON l.pid = a.pid 
WHERE a.datname = current_database() AND a.pid <> pg_backend_pid();
