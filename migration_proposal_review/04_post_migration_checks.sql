-- =============================================================================
-- POST-MIGRATION VALIDATION CHECKS (READ-ONLY)
-- Run against pg_management immediately after DDL execution
-- =============================================================================

-- 1. Verify all 23 active backend tables exist
SELECT count(*) AS total_tables_present,
       CASE WHEN count(*) = 23 THEN 'ALL_23_TABLES_PRESENT (PASS)' ELSE 'MISSING_TABLES (FAIL)' END AS status
FROM information_schema.tables 
WHERE table_schema = 'public' 
  AND table_name IN (
    'companies', 'roles', 'properties', 'users', 'user_property_access', 
    'refresh_tokens', 'audit_logs', 'rooms', 'beds', 'residents', 
    'invoices', 'payments', 'receipts', 'payment_links', 'processed_webhook_events', 
    'device_tokens', 'otp_verifications', 'staff', 'complaints', 'expenses', 
    'leads', 'notices', 'notifications'
  );

-- 2. Confirm existing 4 users have approval_status = 'APPROVED'
SELECT count(*) AS approved_users,
       CASE WHEN count(*) = 4 THEN 'ALL_USERS_APPROVED (PASS)' ELSE 'APPROVAL_STATUS_ISSUE (FAIL)' END AS status
FROM users 
WHERE approval_status = 'APPROVED';

-- 3. Confirm payments.paid_at is nullable
SELECT is_nullable, 
       CASE WHEN is_nullable = 'YES' THEN 'PAID_AT_IS_NULLABLE (PASS)' ELSE 'PAID_AT_NOT_NULL (FAIL)' END AS status
FROM information_schema.columns 
WHERE table_schema = 'public' AND table_name = 'payments' AND column_name = 'paid_at';

-- 4. Confirm unique constraints on payments
SELECT conname, contype 
FROM pg_constraint 
WHERE conrelid = 'payments'::regclass 
  AND conname IN ('uq_payments_gateway_payment_id', 'uq_payment_invoice_idempotency');

-- 5. Confirm receipts 1-to-1 payment constraint
SELECT conname, contype 
FROM pg_constraint 
WHERE conrelid = 'receipts'::regclass 
  AND conname LIKE '%payment_id%';

-- 6. Confirm invoices unique billing cycle constraint
SELECT conname, contype
FROM pg_constraint
WHERE conrelid = 'invoices'::regclass
  AND conname = 'uq_resident_invoice_cycle';

-- 7. Confirm updated Alembic head revision
SELECT version_num,
       CASE WHEN version_num = 'b2c3d4e5f6a7' THEN 'ALEMBIC_VERSION_AT_HEAD (PASS)' ELSE 'ALEMBIC_VERSION_MISMATCH (FAIL)' END AS status
FROM alembic_version;

-- 8. Verify zero data loss on baseline tables
SELECT 'companies' AS tbl, count(*) FROM companies
UNION ALL SELECT 'roles', count(*) FROM roles
UNION ALL SELECT 'properties', count(*) FROM properties
UNION ALL SELECT 'users', count(*) FROM users
UNION ALL SELECT 'user_property_access', count(*) FROM user_property_access
UNION ALL SELECT 'refresh_tokens', count(*) FROM refresh_tokens
UNION ALL SELECT 'audit_logs', count(*) FROM audit_logs;
