-- =============================================================================
-- PRE- AND POST-MIGRATION VALIDATION SUITE V3 (STRICT READ-ONLY)
-- File: migration_proposal_review/production_plan_v3/02_pre_post_validation_v3.sql
-- Target Database: pg_management (or Disposable Sandbox)
-- =============================================================================

-- =============================================================================
-- PART 1: PRE-MIGRATION PREFLIGHT CHECKS
-- =============================================================================

-- Precheck 1: Verify current Alembic revision is exactly '6cb475ecad6d'
SELECT version_num,
       CASE WHEN version_num = '6cb475ecad6d' THEN 'PASS: At baseline revision'
            ELSE 'FAIL: Unexpected revision' END AS precheck_revision_status
FROM alembic_version;

-- Precheck 2: Verify baseline record counts
SELECT 'companies' AS table_name, count(*) AS count, CASE WHEN count(*) = 1 THEN 'PASS' ELSE 'FAIL' END AS status FROM companies
UNION ALL SELECT 'roles', count(*), CASE WHEN count(*) = 4 THEN 'PASS' ELSE 'FAIL' END FROM roles
UNION ALL SELECT 'properties', count(*), CASE WHEN count(*) = 5 THEN 'PASS' ELSE 'FAIL' END FROM properties
UNION ALL SELECT 'users', count(*), CASE WHEN count(*) = 4 THEN 'PASS' ELSE 'FAIL' END FROM users
UNION ALL SELECT 'user_property_access', count(*), CASE WHEN count(*) = 4 THEN 'PASS' ELSE 'FAIL' END FROM user_property_access
UNION ALL SELECT 'refresh_tokens', count(*), CASE WHEN count(*) = 8 THEN 'PASS' ELSE 'FAIL' END FROM refresh_tokens
UNION ALL SELECT 'audit_logs', count(*), CASE WHEN count(*) = 36 THEN 'PASS' ELSE 'FAIL' END FROM audit_logs;

-- Precheck 3: Confirm downstream entity tables contain exactly 0 rows
SELECT 'rooms' AS entity_table, count(*) AS count, CASE WHEN count(*) = 0 THEN 'PASS' ELSE 'FAIL: Data exists' END AS status FROM rooms
UNION ALL SELECT 'beds', count(*), CASE WHEN count(*) = 0 THEN 'PASS' ELSE 'FAIL: Data exists' END FROM beds
UNION ALL SELECT 'residents', count(*), CASE WHEN count(*) = 0 THEN 'PASS' ELSE 'FAIL: Data exists' END FROM residents
UNION ALL SELECT 'invoices', count(*), CASE WHEN count(*) = 0 THEN 'PASS' ELSE 'FAIL: Data exists' END FROM invoices
UNION ALL SELECT 'payments', count(*), CASE WHEN count(*) = 0 THEN 'PASS' ELSE 'FAIL: Data exists' END FROM payments;


-- =============================================================================
-- PART 2: POST-MIGRATION INTEGRITY CHECKS
-- =============================================================================

-- Postcheck 1: Verify all 23 active backend application domain tables exist
SELECT count(*) AS total_tables_present,
       CASE WHEN count(*) = 23 THEN 'PASS: All 23 tables exist' ELSE 'FAIL: Missing tables' END AS status
FROM information_schema.tables 
WHERE table_schema = 'public' 
  AND table_name IN (
    'companies', 'roles', 'properties', 'users', 'user_property_access', 
    'refresh_tokens', 'audit_logs', 'rooms', 'beds', 'residents', 
    'invoices', 'payments', 'receipts', 'payment_links', 'processed_webhook_events', 
    'device_tokens', 'otp_verifications', 'staff', 'complaints', 'expenses', 
    'leads', 'notices', 'notifications'
  );

-- Postcheck 2: Verify existing users have approval_status = 'APPROVED'
SELECT count(*) AS approved_users_count,
       CASE WHEN count(*) = 4 THEN 'PASS: All existing users approved' ELSE 'FAIL: Unexpected count' END AS status
FROM users 
WHERE approval_status = 'APPROVED';

-- Postcheck 3: Verify zero obsolete legacy columns exist
SELECT count(*) AS obsolete_columns_count,
       CASE WHEN count(*) = 0 THEN 'PASS: Zero legacy columns remain' ELSE 'FAIL: Legacy columns linger' END AS status
FROM information_schema.columns 
WHERE table_schema = 'public' 
  AND (
    (table_name = 'rooms' AND column_name IN ('base_monthly_rent', 'deposit_amount')) OR
    (table_name = 'beds' AND column_name IN ('property_id', 'is_active')) OR
    (table_name = 'residents' AND column_name IN ('company_id', 'full_name', 'email', 'phone', 'kyc_notes', 'verified_at', 'verified_by_id')) OR
    (table_name = 'invoices' AND column_name IN ('company_id', 'billing_period_start', 'billing_period_end', 'issue_date', 'rent_amount', 'additional_charges', 'discount_amount', 'total_amount', 'balance_amount')) OR
    (table_name = 'payments' AND column_name IN ('company_id', 'payment_method', 'transaction_reference', 'recorded_by_user_id', 'payment_date'))
  );

-- Postcheck 4: Verify zero obsolete composite constraints exist
SELECT count(*) AS obsolete_constraints_count,
       CASE WHEN count(*) = 0 THEN 'PASS: Zero obsolete composite constraints' ELSE 'FAIL: Lingering constraints' END AS status
FROM pg_constraint 
WHERE conname IN (
    'fk_residents_bed_id_property_id', 'fk_residents_room_id_property_id',
    'fk_beds_room_id_property_id', 'fk_invoices_resident_id_property_id',
    'fk_payments_invoice_id_property_id', 'fk_payments_resident_id_property_id',
    'uq_beds_id_property_id', 'uq_residents_id_property_id',
    'uq_rooms_id_property_id', 'uq_invoices_id_property_id',
    'uq_resident_billing_month_type'
);

-- Postcheck 5: Verify unique constraints on invoices
SELECT conname, pg_get_constraintdef(oid) AS definition,
       CASE 
         WHEN conname = 'uq_resident_invoice_cycle' THEN 'PASS: Cycle unique constraint'
         WHEN conname = 'invoices_invoice_number_key' THEN 'PASS: Invoice number unique constraint'
         ELSE 'FAIL: Unexpected unique constraint' 
       END AS status
FROM pg_constraint 
WHERE conrelid = 'invoices'::regclass AND contype = 'u';

-- Postcheck 6: Verify active 3NF single-column foreign keys and on-delete rules
SELECT conname, conrelid::regclass::text AS source_table, pg_get_constraintdef(oid) AS definition,
       CASE 
         WHEN conname = 'rooms_property_id_fkey' AND pg_get_constraintdef(oid) LIKE '%ON DELETE CASCADE%' THEN 'PASS'
         WHEN conname = 'beds_room_id_fkey' AND pg_get_constraintdef(oid) LIKE '%ON DELETE CASCADE%' THEN 'PASS'
         WHEN conname = 'residents_user_id_fkey' AND pg_get_constraintdef(oid) LIKE '%ON DELETE CASCADE%' THEN 'PASS'
         WHEN conname = 'residents_property_id_fkey' AND pg_get_constraintdef(oid) LIKE '%ON DELETE RESTRICT%' THEN 'PASS'
         WHEN conname = 'residents_room_id_fkey' AND pg_get_constraintdef(oid) LIKE '%ON DELETE SET NULL%' THEN 'PASS'
         WHEN conname = 'residents_bed_id_fkey' AND pg_get_constraintdef(oid) LIKE '%ON DELETE SET NULL%' THEN 'PASS'
         WHEN conname = 'invoices_resident_id_fkey' AND pg_get_constraintdef(oid) LIKE '%ON DELETE RESTRICT%' THEN 'PASS'
         WHEN conname = 'invoices_property_id_fkey' AND pg_get_constraintdef(oid) LIKE '%ON DELETE RESTRICT%' THEN 'PASS'
         WHEN conname = 'payments_property_id_fkey' AND pg_get_constraintdef(oid) LIKE '%ON DELETE RESTRICT%' THEN 'PASS'
         WHEN conname = 'payments_invoice_id_fkey' AND pg_get_constraintdef(oid) LIKE '%ON DELETE RESTRICT%' THEN 'PASS'
         WHEN conname = 'payments_resident_id_fkey' AND pg_get_constraintdef(oid) LIKE '%ON DELETE RESTRICT%' THEN 'PASS'
         ELSE 'FAIL: Constraint definition mismatch'
       END AS status
FROM pg_constraint 
WHERE conname IN (
    'rooms_property_id_fkey', 'beds_room_id_fkey', 'residents_user_id_fkey',
    'residents_property_id_fkey', 'residents_room_id_fkey', 'residents_bed_id_fkey',
    'invoices_resident_id_fkey', 'invoices_property_id_fkey',
    'payments_property_id_fkey', 'payments_invoice_id_fkey', 'payments_resident_id_fkey'
)
ORDER BY source_table, conname;

-- Postcheck 7: Verify unique indexes on residents (user_id, bed_id)
SELECT indexname, indexdef,
       CASE WHEN indexdef LIKE '%UNIQUE%' THEN 'PASS: Unique index enforced' ELSE 'FAIL: Non-unique' END AS status
FROM pg_indexes 
WHERE tablename = 'residents' AND indexname IN ('ix_residents_user_id', 'ix_residents_bed_id')
ORDER BY indexname;

-- Postcheck 8: Verify Alembic revision is synchronized to active head
SELECT version_num,
       CASE WHEN version_num = 'b2c3d4e5f6a7' THEN 'PASS: Alembic head b2c3d4e5f6a7' ELSE 'FAIL: Version mismatch' END AS status
FROM alembic_version;

-- Postcheck 9: Verify zero data loss on baseline tables
SELECT 'companies' AS table_name, count(*) AS count, CASE WHEN count(*) = 1 THEN 'PASS' ELSE 'FAIL' END AS status FROM companies
UNION ALL SELECT 'roles', count(*), CASE WHEN count(*) = 4 THEN 'PASS' ELSE 'FAIL' END FROM roles
UNION ALL SELECT 'properties', count(*), CASE WHEN count(*) = 5 THEN 'PASS' ELSE 'FAIL' END FROM properties
UNION ALL SELECT 'users', count(*), CASE WHEN count(*) = 4 THEN 'PASS' ELSE 'FAIL' END FROM users
UNION ALL SELECT 'user_property_access', count(*), CASE WHEN count(*) = 4 THEN 'PASS' ELSE 'FAIL' END FROM user_property_access
UNION ALL SELECT 'refresh_tokens', count(*), CASE WHEN count(*) = 8 THEN 'PASS' ELSE 'FAIL' END FROM refresh_tokens
UNION ALL SELECT 'audit_logs', count(*), CASE WHEN count(*) = 36 THEN 'PASS' ELSE 'FAIL' END FROM audit_logs;
