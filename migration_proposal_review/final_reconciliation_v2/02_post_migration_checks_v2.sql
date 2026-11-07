-- =============================================================================
-- POST-MIGRATION VALIDATION CHECKS V2 (READ-ONLY)
-- Designed for sandbox regression testing & post-migration verification.
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

-- 3. Confirm nullability relaxation on legacy-only columns
SELECT table_name, column_name, is_nullable,
       CASE WHEN is_nullable = 'YES' THEN 'RELAXED (PASS)' ELSE 'STILL_NOT_NULL (FAIL)' END AS status
FROM information_schema.columns 
WHERE table_schema = 'public' 
  AND (
    (table_name = 'beds' AND column_name IN ('property_id', 'monthly_rent')) OR
    (table_name = 'residents' AND column_name IN ('company_id', 'full_name', 'phone')) OR
    (table_name = 'invoices' AND column_name IN ('company_id', 'total_amount', 'balance_amount')) OR
    (table_name = 'payments' AND column_name IN ('company_id', 'payment_method', 'payment_date', 'paid_at'))
  )
ORDER BY table_name, column_name;

-- 4. Confirm residents.user_id is NOT NULL
SELECT column_name, is_nullable,
       CASE WHEN is_nullable = 'NO' THEN 'USER_ID_NOT_NULL (PASS)' ELSE 'USER_ID_NULLABLE (FAIL)' END AS status
FROM information_schema.columns 
WHERE table_schema = 'public' AND table_name = 'residents' AND column_name = 'user_id';

-- 5. Confirm unique indexes on residents (user_id and bed_id)
SELECT indexname, indexdef,
       CASE WHEN indexdef LIKE '%UNIQUE%' THEN 'UNIQUE_INDEX (PASS)' ELSE 'NON_UNIQUE (FAIL)' END AS status
FROM pg_indexes 
WHERE tablename = 'residents' AND indexname IN ('ix_residents_user_id', 'ix_residents_bed_id');

-- 6. Confirm invoices billing cycle unique constraint
SELECT conname, contype,
       CASE WHEN conname = 'uq_resident_invoice_cycle' THEN 'CONSTRAINT_PRESENT (PASS)' ELSE 'UNKNOWN' END AS status
FROM pg_constraint 
WHERE conrelid = 'invoices'::regclass AND conname = 'uq_resident_invoice_cycle';

-- 7. Confirm payment constraints & indexes
SELECT conname, contype 
FROM pg_constraint 
WHERE conrelid = 'payments'::regclass 
  AND conname IN ('uq_payments_gateway_payment_id', 'uq_payment_invoice_idempotency');

-- 8. Confirm all secondary indexes on new tables (f1c4a0e3d2b1 through b2c3d4e5f6a7)
SELECT tablename, indexname 
FROM pg_indexes 
WHERE tablename IN ('receipts', 'processed_webhook_events', 'payment_links', 'otp_verifications', 'device_tokens', 'staff')
  AND indexname IN (
    'ix_receipts_payment_id', 'ix_receipts_receipt_number', 'ix_receipts_invoice_id', 'ix_receipts_whatsapp_status',
    'ix_processed_webhook_events_event_id', 'ix_processed_webhook_events_provider', 'ix_processed_webhook_events_event_type',
    'ix_payment_links_payment_id', 'ix_payment_links_token_hash', 'ix_payment_links_is_revoked', 'ix_payment_links_expires_at',
    'ix_otp_verifications_purpose', 'ix_otp_verifications_is_verified', 'ix_otp_verifications_phone', 'ix_otp_verifications_expires_at',
    'ix_device_tokens_user_id', 'ix_device_tokens_device_token',
    'ix_staff_user_id', 'ix_staff_property_id'
  )
ORDER BY tablename, indexname;

-- 9. Confirm updated Alembic head revision
SELECT version_num,
       CASE WHEN version_num = 'b2c3d4e5f6a7' THEN 'ALEMBIC_VERSION_AT_HEAD (PASS)' ELSE 'ALEMBIC_VERSION_MISMATCH (FAIL)' END AS status
FROM alembic_version;

-- 10. Verify zero data loss on baseline tables
SELECT 'companies' AS tbl, count(*) FROM companies
UNION ALL SELECT 'roles', count(*) FROM roles
UNION ALL SELECT 'properties', count(*) FROM properties
UNION ALL SELECT 'users', count(*) FROM users
UNION ALL SELECT 'user_property_access', count(*) FROM user_property_access
UNION ALL SELECT 'refresh_tokens', count(*) FROM refresh_tokens
UNION ALL SELECT 'audit_logs', count(*) FROM audit_logs;
