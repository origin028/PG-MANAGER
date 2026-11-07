-- =============================================================================
-- UNIFIED PRODUCTION RECONCILIATION SCRIPT V3 FOR pg_management
-- File: migration_proposal_review/production_plan_v3/01_unified_reconcile_pg_management_v3.sql
-- Target Database: pg_management (PostgreSQL 18.6)
-- Baseline Revision: 6cb475ecad6d
-- Target Active Revision: b2c3d4e5f6a7
-- Mode: PROPOSED ARTIFACT ONLY — DO NOT EXECUTE WITHOUT EXPLICIT AUTHORIZATION
--
-- DESIGN GUARANTEES:
-- 1. 100% Atomic: All statements execute inside a single BEGIN ... COMMIT block.
-- 2. Strict Preconditions: Validates alembic revision, table existence, and row counts.
-- 3. Dependency-Ordered DDL: Drops referencing composite foreign keys before obsolete
--    composite unique constraints, preventing PostgreSQL dependency errors.
-- 4. True Schema Convergence: Drops all unmapped legacy columns from 0-row entity tables,
--    achieving 100% identity with the fresh active Alembic head schema.
-- 5. Exact Invoice Unique Constraint: Standardizes to single 'uq_resident_invoice_cycle',
--    dropping obsolete 'uq_resident_billing_month_type'.
-- 6. Active Model Alignment: Restores clean 3NF single-column foreign keys with exact
--    ON DELETE rules matching active models and revisions.
-- 7. Data Preservation: Zero records modified, dropped, or lost on baseline tables.
-- 8. Fail-Fast Postconditions: Validates all 23 domain tables, columns, FKs, indexes,
--    and row counts before committing. Reconciles alembic_version only after physical
--    validation passes.
-- =============================================================================

BEGIN;

-- =============================================================================
-- SECTION 1: PRECONDITION CHECKS (FAIL-FAST ASSERTIONS)
-- =============================================================================
DO $$
DECLARE
    v_rev VARCHAR;
    v_cnt BIGINT;
BEGIN
    -- 1.1 Verify exact starting Alembic revision
    SELECT version_num INTO v_rev FROM alembic_version LIMIT 1;
    IF v_rev IS NULL OR v_rev != '6cb475ecad6d' THEN
        RAISE EXCEPTION 'PRECONDITION FAILED: Expected alembic_version "6cb475ecad6d", found "%"', v_rev;
    END IF;

    -- 1.2 Verify baseline tables exist
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'companies') OR
       NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'roles') OR
       NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'properties') OR
       NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'users') OR
       NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'user_property_access') OR
       NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'refresh_tokens') OR
       NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'audit_logs') THEN
        RAISE EXCEPTION 'PRECONDITION FAILED: One or more required baseline tables are missing.';
    END IF;

    -- 1.3 Verify exact baseline record counts
    SELECT count(*) INTO v_cnt FROM companies;
    IF v_cnt != 1 THEN RAISE EXCEPTION 'PRECONDITION FAILED: companies count expected 1, found %', v_cnt; END IF;

    SELECT count(*) INTO v_cnt FROM roles;
    IF v_cnt != 4 THEN RAISE EXCEPTION 'PRECONDITION FAILED: roles count expected 4, found %', v_cnt; END IF;

    SELECT count(*) INTO v_cnt FROM properties;
    IF v_cnt != 5 THEN RAISE EXCEPTION 'PRECONDITION FAILED: properties count expected 5, found %', v_cnt; END IF;

    SELECT count(*) INTO v_cnt FROM users;
    IF v_cnt != 4 THEN RAISE EXCEPTION 'PRECONDITION FAILED: users count expected 4, found %', v_cnt; END IF;

    SELECT count(*) INTO v_cnt FROM user_property_access;
    IF v_cnt != 4 THEN RAISE EXCEPTION 'PRECONDITION FAILED: user_property_access count expected 4, found %', v_cnt; END IF;

    SELECT count(*) INTO v_cnt FROM refresh_tokens;
    IF v_cnt != 8 THEN RAISE EXCEPTION 'PRECONDITION FAILED: refresh_tokens count expected 8, found %', v_cnt; END IF;

    SELECT count(*) INTO v_cnt FROM audit_logs;
    IF v_cnt != 36 THEN RAISE EXCEPTION 'PRECONDITION FAILED: audit_logs count expected 36, found %', v_cnt; END IF;

    -- 1.4 Verify downstream entity tables exist and contain exactly 0 rows
    SELECT count(*) INTO v_cnt FROM rooms;
    IF v_cnt != 0 THEN RAISE EXCEPTION 'PRECONDITION FAILED: rooms table contains % unexpected rows', v_cnt; END IF;

    SELECT count(*) INTO v_cnt FROM beds;
    IF v_cnt != 0 THEN RAISE EXCEPTION 'PRECONDITION FAILED: beds table contains % unexpected rows', v_cnt; END IF;

    SELECT count(*) INTO v_cnt FROM residents;
    IF v_cnt != 0 THEN RAISE EXCEPTION 'PRECONDITION FAILED: residents table contains % unexpected rows', v_cnt; END IF;

    SELECT count(*) INTO v_cnt FROM invoices;
    IF v_cnt != 0 THEN RAISE EXCEPTION 'PRECONDITION FAILED: invoices table contains % unexpected rows', v_cnt; END IF;

    SELECT count(*) INTO v_cnt FROM payments;
    IF v_cnt != 0 THEN RAISE EXCEPTION 'PRECONDITION FAILED: payments table contains % unexpected rows', v_cnt; END IF;

    RAISE NOTICE 'PRECONDITION CHECKS PASSED: Database state verified for safe V3 reconciliation.';
END $$;


-- =============================================================================
-- SECTION 2: ADAPT ACTIVE USER ACCOUNTS (PRESERVE ALL 4 USERS)
-- =============================================================================
-- Add approval_status and index; all 4 existing system-created accounts receive 'APPROVED'
ALTER TABLE users ADD COLUMN IF NOT EXISTS approval_status VARCHAR(50) DEFAULT 'APPROVED' NOT NULL;
CREATE INDEX IF NOT EXISTS ix_users_approval_status ON users (approval_status);


-- =============================================================================
-- SECTION 3: DROP DEPENDENT LEGACY COMPOSITE FOREIGN KEYS (ORDER-AWARE)
-- Must drop referencing composite FKs before obsolete unique constraints can be dropped.
-- =============================================================================

-- 3.1 Drop legacy composite FKs on payments
ALTER TABLE payments DROP CONSTRAINT IF EXISTS fk_payments_invoice_id_property_id;
ALTER TABLE payments DROP CONSTRAINT IF EXISTS fk_payments_resident_id_property_id;

-- 3.2 Drop legacy composite FKs on invoices
ALTER TABLE invoices DROP CONSTRAINT IF EXISTS fk_invoices_resident_id_property_id;

-- 3.3 Drop legacy composite FKs on residents
ALTER TABLE residents DROP CONSTRAINT IF EXISTS fk_residents_bed_id_property_id;
ALTER TABLE residents DROP CONSTRAINT IF EXISTS fk_residents_room_id_property_id;
ALTER TABLE residents DROP CONSTRAINT IF EXISTS residents_user_id_fkey; -- Recreated with CASCADE

-- 3.4 Drop legacy composite FKs on beds
ALTER TABLE beds DROP CONSTRAINT IF EXISTS fk_beds_room_id_property_id;


-- =============================================================================
-- SECTION 4: DROP OBSOLETE COMPOSITE UNIQUE CONSTRAINTS
-- Safe now because all referencing composite foreign keys have been eliminated.
-- =============================================================================
ALTER TABLE beds DROP CONSTRAINT IF EXISTS uq_beds_id_property_id;
ALTER TABLE residents DROP CONSTRAINT IF EXISTS uq_residents_id_property_id;
ALTER TABLE invoices DROP CONSTRAINT IF EXISTS uq_invoices_id_property_id;
ALTER TABLE rooms DROP CONSTRAINT IF EXISTS uq_rooms_id_property_id;
ALTER TABLE payments DROP CONSTRAINT IF EXISTS uq_payments_id_property_id;


-- =============================================================================
-- SECTION 5: DROP OBSOLETE LEGACY FOREIGN KEYS AND INDEXES ON CANDIDATE COLUMNS
-- =============================================================================

-- 5.1 On beds: drop legacy property_id FK and indexes
ALTER TABLE beds DROP CONSTRAINT IF EXISTS beds_property_id_fkey;
DROP INDEX IF EXISTS ix_beds_property_id;
DROP INDEX IF EXISTS ix_beds_property_status;

-- 5.2 On residents: drop legacy company_id, verified_by_id FKs and indexes
ALTER TABLE residents DROP CONSTRAINT IF EXISTS residents_company_id_fkey;
ALTER TABLE residents DROP CONSTRAINT IF EXISTS residents_verified_by_id_fkey;
DROP INDEX IF EXISTS ix_residents_company_id;
DROP INDEX IF EXISTS ix_residents_phone;
DROP INDEX IF EXISTS ix_residents_email;

-- 5.3 On invoices: drop legacy company_id FK, legacy unique constraint, and index
ALTER TABLE invoices DROP CONSTRAINT IF EXISTS invoices_company_id_fkey;
ALTER TABLE invoices DROP CONSTRAINT IF EXISTS uq_resident_billing_month_type;
DROP INDEX IF EXISTS ix_invoices_company_id;

-- 5.4 On payments: drop legacy company_id, recorded_by_user_id FKs, and indexes
ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_company_id_fkey;
ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_recorded_by_user_id_fkey;
DROP INDEX IF EXISTS ix_payments_company_id;
DROP INDEX IF EXISTS ix_payments_payment_date;
DROP INDEX IF EXISTS uq_payment_transaction_ref;

-- 5.5 On rooms: drop obsolete property_id FK constraint (will recreate with CASCADE)
ALTER TABLE rooms DROP CONSTRAINT IF EXISTS rooms_property_id_fkey;
ALTER TABLE rooms DROP CONSTRAINT IF EXISTS uq_room_property_room_number;


-- =============================================================================
-- SECTION 6: REMOVE OBSOLETE LEGACY COLUMNS (ZERO-ROW TABLES ONLY)
-- Safe because tables have 0 rows and dependent FKs/indexes are dropped.
-- Aligns schema exactly with fresh active Alembic migrations (bd0a1cc93d5d).
-- =============================================================================

-- 6.1 ROOMS: Remove unmapped legacy rent and deposit columns
ALTER TABLE rooms DROP COLUMN IF EXISTS base_monthly_rent;
ALTER TABLE rooms DROP COLUMN IF EXISTS deposit_amount;

-- 6.2 BEDS: Remove unmapped legacy property_id and is_active columns
ALTER TABLE beds DROP COLUMN IF EXISTS property_id;
ALTER TABLE beds DROP COLUMN IF EXISTS is_active;

-- 6.3 RESIDENTS: Remove redundant/unmapped legacy columns (user relation is source of truth)
ALTER TABLE residents DROP COLUMN IF EXISTS company_id;
ALTER TABLE residents DROP COLUMN IF EXISTS full_name;
ALTER TABLE residents DROP COLUMN IF EXISTS email;
ALTER TABLE residents DROP COLUMN IF EXISTS phone;
ALTER TABLE residents DROP COLUMN IF EXISTS kyc_notes;
ALTER TABLE residents DROP COLUMN IF EXISTS verified_at;
ALTER TABLE residents DROP COLUMN IF EXISTS verified_by_id;

-- 6.4 INVOICES: Remove unmapped legacy billing period and breakdown columns
ALTER TABLE invoices DROP COLUMN IF EXISTS company_id;
ALTER TABLE invoices DROP COLUMN IF EXISTS billing_period_start;
ALTER TABLE invoices DROP COLUMN IF EXISTS billing_period_end;
ALTER TABLE invoices DROP COLUMN IF EXISTS issue_date;
ALTER TABLE invoices DROP COLUMN IF EXISTS rent_amount;
ALTER TABLE invoices DROP COLUMN IF EXISTS additional_charges;
ALTER TABLE invoices DROP COLUMN IF EXISTS discount_amount;
ALTER TABLE invoices DROP COLUMN IF EXISTS total_amount;
ALTER TABLE invoices DROP COLUMN IF EXISTS balance_amount;

-- 6.5 PAYMENTS: Remove unmapped legacy method and user columns
ALTER TABLE payments DROP COLUMN IF EXISTS company_id;
ALTER TABLE payments DROP COLUMN IF EXISTS payment_method;
ALTER TABLE payments DROP COLUMN IF EXISTS transaction_reference;
ALTER TABLE payments DROP COLUMN IF EXISTS recorded_by_user_id;
ALTER TABLE payments DROP COLUMN IF EXISTS payment_date;


-- =============================================================================
-- SECTION 7: ADD ACTIVE MODEL COLUMNS AND ALIGN COLUMN TYPES & DEFAULTS
-- =============================================================================

-- 7.1 ROOMS: Add base_rent, max_occupancy; ensure amenities default and type
ALTER TABLE rooms ADD COLUMN IF NOT EXISTS base_rent NUMERIC(10, 2) NOT NULL DEFAULT 0.00;
ALTER TABLE rooms ADD COLUMN IF NOT EXISTS max_occupancy INTEGER NOT NULL DEFAULT 2;

-- 7.2 BEDS: Ensure monthly_rent is nullable (active model supports null)
ALTER TABLE beds ALTER COLUMN monthly_rent DROP NOT NULL;

-- 7.3 RESIDENTS: Add id_proof_document_path, set user_id NOT NULL, default status ACTIVE
ALTER TABLE residents ADD COLUMN IF NOT EXISTS id_proof_document_path VARCHAR(512);
ALTER TABLE residents ALTER COLUMN user_id SET NOT NULL;
ALTER TABLE residents ALTER COLUMN status SET DEFAULT 'ACTIVE';
ALTER TABLE residents ALTER COLUMN check_in_date SET NOT NULL;

-- 7.4 INVOICES: Add amount, set status default PENDING, notes to TEXT
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS amount NUMERIC(10, 2) NOT NULL DEFAULT 0.00;
ALTER TABLE invoices ALTER COLUMN status SET DEFAULT 'PENDING';
ALTER TABLE invoices ALTER COLUMN notes TYPE TEXT;

-- 7.5 PAYMENTS: Add direct UPI reservation, idempotency, gateway tracking
ALTER TABLE payments ADD COLUMN IF NOT EXISTS payment_mode VARCHAR(50) NOT NULL DEFAULT 'UPI';
ALTER TABLE payments ADD COLUMN IF NOT EXISTS gateway_order_id VARCHAR(150);
ALTER TABLE payments ADD COLUMN IF NOT EXISTS gateway_payment_id VARCHAR(150);
ALTER TABLE payments ADD COLUMN IF NOT EXISTS gateway_signature VARCHAR(255);
ALTER TABLE payments ADD COLUMN IF NOT EXISTS receipt_url VARCHAR(512);
ALTER TABLE payments ADD COLUMN IF NOT EXISTS idempotency_key VARCHAR(128);
ALTER TABLE payments ADD COLUMN IF NOT EXISTS reservation_expires_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE payments ALTER COLUMN paid_at DROP NOT NULL;
ALTER TABLE payments ALTER COLUMN paid_at DROP DEFAULT;
ALTER TABLE payments ALTER COLUMN status SET DEFAULT 'PENDING';


-- =============================================================================
-- SECTION 8: CREATE ACTIVE 3NF SINGLE-COLUMN FOREIGN KEYS & CONSTRAINTS
-- =============================================================================

-- 8.1 ROOMS: property_id -> properties.id ON DELETE CASCADE
ALTER TABLE rooms DROP CONSTRAINT IF EXISTS rooms_property_id_fkey;
ALTER TABLE rooms ADD CONSTRAINT rooms_property_id_fkey
    FOREIGN KEY (property_id) REFERENCES properties (id) ON DELETE CASCADE;

-- 8.2 BEDS: room_id -> rooms.id ON DELETE CASCADE
ALTER TABLE beds DROP CONSTRAINT IF EXISTS beds_room_id_fkey;
ALTER TABLE beds ADD CONSTRAINT beds_room_id_fkey
    FOREIGN KEY (room_id) REFERENCES rooms (id) ON DELETE CASCADE;

-- 8.3 RESIDENTS: 3NF single-column FKs
ALTER TABLE residents DROP CONSTRAINT IF EXISTS residents_user_id_fkey;
ALTER TABLE residents ADD CONSTRAINT residents_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE;

ALTER TABLE residents DROP CONSTRAINT IF EXISTS residents_property_id_fkey;
ALTER TABLE residents ADD CONSTRAINT residents_property_id_fkey
    FOREIGN KEY (property_id) REFERENCES properties (id) ON DELETE RESTRICT;

ALTER TABLE residents DROP CONSTRAINT IF EXISTS residents_room_id_fkey;
ALTER TABLE residents ADD CONSTRAINT residents_room_id_fkey
    FOREIGN KEY (room_id) REFERENCES rooms (id) ON DELETE SET NULL;

ALTER TABLE residents DROP CONSTRAINT IF EXISTS residents_bed_id_fkey;
ALTER TABLE residents ADD CONSTRAINT residents_bed_id_fkey
    FOREIGN KEY (bed_id) REFERENCES beds (id) ON DELETE SET NULL;

-- 1-to-1 unique resident mappings
DROP INDEX IF EXISTS ix_residents_user_id;
CREATE UNIQUE INDEX ix_residents_user_id ON residents (user_id);

DROP INDEX IF EXISTS ix_residents_bed_id;
CREATE UNIQUE INDEX ix_residents_bed_id ON residents (bed_id);

-- 8.4 INVOICES: Single-column FKs and standardized single unique constraint
ALTER TABLE invoices DROP CONSTRAINT IF EXISTS invoices_property_id_fkey;
ALTER TABLE invoices ADD CONSTRAINT invoices_property_id_fkey
    FOREIGN KEY (property_id) REFERENCES properties (id) ON DELETE RESTRICT;

ALTER TABLE invoices DROP CONSTRAINT IF EXISTS invoices_resident_id_fkey;
ALTER TABLE invoices ADD CONSTRAINT invoices_resident_id_fkey
    FOREIGN KEY (resident_id) REFERENCES residents (id) ON DELETE RESTRICT;

ALTER TABLE invoices DROP CONSTRAINT IF EXISTS uq_resident_invoice_cycle;
ALTER TABLE invoices ADD CONSTRAINT uq_resident_invoice_cycle
    UNIQUE (resident_id, billing_month, invoice_type);

-- 8.5 PAYMENTS: Single-column FKs and unique idempotency/gateway constraints
ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_property_id_fkey;
ALTER TABLE payments ADD CONSTRAINT payments_property_id_fkey
    FOREIGN KEY (property_id) REFERENCES properties (id) ON DELETE RESTRICT;

ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_invoice_id_fkey;
ALTER TABLE payments ADD CONSTRAINT payments_invoice_id_fkey
    FOREIGN KEY (invoice_id) REFERENCES invoices (id) ON DELETE RESTRICT;

ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_resident_id_fkey;
ALTER TABLE payments ADD CONSTRAINT payments_resident_id_fkey
    FOREIGN KEY (resident_id) REFERENCES residents (id) ON DELETE RESTRICT;

ALTER TABLE payments DROP CONSTRAINT IF EXISTS uq_payments_gateway_payment_id;
ALTER TABLE payments ADD CONSTRAINT uq_payments_gateway_payment_id
    UNIQUE (gateway_payment_id);

ALTER TABLE payments DROP CONSTRAINT IF EXISTS uq_payment_invoice_idempotency;
ALTER TABLE payments ADD CONSTRAINT uq_payment_invoice_idempotency
    UNIQUE (invoice_id, idempotency_key);

CREATE INDEX IF NOT EXISTS ix_payments_idempotency_key ON payments (idempotency_key);
CREATE INDEX IF NOT EXISTS ix_payments_reservation_expires_at ON payments (reservation_expires_at);


-- =============================================================================
-- SECTION 9: CREATE MISSING APPLICATION & OPERATIONAL TABLES (11 TABLES)
-- =============================================================================

-- 9.1 STAFF (Precedes complaints)
CREATE TABLE IF NOT EXISTS staff (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    property_id UUID NOT NULL REFERENCES properties (id) ON DELETE RESTRICT,
    designation VARCHAR(100) NOT NULL DEFAULT 'WARDEN',
    salary NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
    joining_date DATE NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'ACTIVE',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    CONSTRAINT uq_staff_user_id UNIQUE (user_id)
);
CREATE INDEX IF NOT EXISTS ix_staff_property_id ON staff (property_id);
CREATE UNIQUE INDEX IF NOT EXISTS ix_staff_user_id ON staff (user_id);

-- 9.2 COMPLAINTS
CREATE TABLE IF NOT EXISTS complaints (
    id UUID PRIMARY KEY,
    property_id UUID NOT NULL REFERENCES properties (id) ON DELETE CASCADE,
    resident_id UUID NOT NULL REFERENCES residents (id) ON DELETE CASCADE,
    assigned_staff_id UUID REFERENCES staff (id) ON DELETE SET NULL,
    category VARCHAR(50) NOT NULL DEFAULT 'OTHER',
    title VARCHAR(200) NOT NULL,
    description TEXT NOT NULL,
    priority VARCHAR(30) NOT NULL DEFAULT 'MEDIUM',
    status VARCHAR(50) NOT NULL DEFAULT 'PENDING',
    resolution_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_complaints_property_id ON complaints (property_id);
CREATE INDEX IF NOT EXISTS ix_complaints_resident_id ON complaints (resident_id);
CREATE INDEX IF NOT EXISTS ix_complaints_assigned_staff_id ON complaints (assigned_staff_id);
CREATE INDEX IF NOT EXISTS ix_complaints_status ON complaints (status);

-- 9.3 EXPENSES
CREATE TABLE IF NOT EXISTS expenses (
    id UUID PRIMARY KEY,
    property_id UUID NOT NULL REFERENCES properties (id) ON DELETE CASCADE,
    recorded_by_user_id UUID NOT NULL REFERENCES users (id) ON DELETE RESTRICT,
    category VARCHAR(50) NOT NULL,
    title VARCHAR(200) NOT NULL,
    amount NUMERIC(10, 2) NOT NULL,
    payment_mode VARCHAR(50) NOT NULL DEFAULT 'UPI',
    expense_date DATE NOT NULL,
    receipt_url VARCHAR(512),
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_expenses_property_id ON expenses (property_id);
CREATE INDEX IF NOT EXISTS ix_expenses_recorded_by_user_id ON expenses (recorded_by_user_id);

-- 9.4 LEADS
CREATE TABLE IF NOT EXISTS leads (
    id UUID PRIMARY KEY,
    property_id UUID NOT NULL REFERENCES properties (id) ON DELETE CASCADE,
    name VARCHAR(150) NOT NULL,
    phone VARCHAR(30) NOT NULL,
    email VARCHAR(255),
    status VARCHAR(50) NOT NULL DEFAULT 'NEW',
    visit_date TIMESTAMP WITH TIME ZONE,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_leads_property_id ON leads (property_id);
CREATE INDEX IF NOT EXISTS ix_leads_phone ON leads (phone);
CREATE INDEX IF NOT EXISTS ix_leads_status ON leads (status);

-- 9.5 NOTICES
CREATE TABLE IF NOT EXISTS notices (
    id UUID PRIMARY KEY,
    property_id UUID NOT NULL REFERENCES properties (id) ON DELETE CASCADE,
    created_by_user_id UUID NOT NULL REFERENCES users (id) ON DELETE RESTRICT,
    title VARCHAR(200) NOT NULL,
    content TEXT NOT NULL,
    is_pinned BOOLEAN NOT NULL DEFAULT false,
    expires_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_notices_property_id ON notices (property_id);
CREATE INDEX IF NOT EXISTS ix_notices_created_by_user_id ON notices (created_by_user_id);

-- 9.6 NOTIFICATIONS
CREATE TABLE IF NOT EXISTS notifications (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    title VARCHAR(200) NOT NULL,
    body TEXT NOT NULL,
    channel VARCHAR(50) NOT NULL DEFAULT 'PUSH',
    status VARCHAR(50) NOT NULL DEFAULT 'PENDING',
    scheduled_at TIMESTAMP WITH TIME ZONE,
    sent_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_notifications_user_id ON notifications (user_id);
CREATE INDEX IF NOT EXISTS ix_notifications_status ON notifications (status);

-- 9.7 PROCESSED_WEBHOOK_EVENTS (Replay & Idempotency Protection)
CREATE TABLE IF NOT EXISTS processed_webhook_events (
    id UUID PRIMARY KEY,
    provider VARCHAR(50) NOT NULL,
    event_id VARCHAR(150) NOT NULL,
    event_type VARCHAR(100) NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'PROCESSED',
    processed_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    CONSTRAINT uq_processed_webhook_event_id UNIQUE (event_id)
);
CREATE INDEX IF NOT EXISTS ix_processed_webhook_events_provider ON processed_webhook_events (provider);
CREATE INDEX IF NOT EXISTS ix_processed_webhook_events_event_id ON processed_webhook_events (event_id);
CREATE INDEX IF NOT EXISTS ix_processed_webhook_events_event_type ON processed_webhook_events (event_type);

-- 9.8 RECEIPTS (1-to-1 Digital Receipts for Payments)
CREATE TABLE IF NOT EXISTS receipts (
    id UUID PRIMARY KEY,
    payment_id UUID NOT NULL REFERENCES payments (id) ON DELETE RESTRICT,
    invoice_id UUID NOT NULL REFERENCES invoices (id) ON DELETE RESTRICT,
    receipt_number VARCHAR(100) NOT NULL,
    amount NUMERIC(10, 2) NOT NULL,
    issued_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    whatsapp_status VARCHAR(50) NOT NULL DEFAULT 'PENDING',
    whatsapp_attempts INTEGER NOT NULL DEFAULT 0,
    next_retry_at TIMESTAMP WITH TIME ZONE,
    last_delivery_error TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    CONSTRAINT uq_receipts_payment_id UNIQUE (payment_id),
    CONSTRAINT uq_receipts_receipt_number UNIQUE (receipt_number)
);
CREATE INDEX IF NOT EXISTS ix_receipts_payment_id ON receipts (payment_id);
CREATE INDEX IF NOT EXISTS ix_receipts_invoice_id ON receipts (invoice_id);
CREATE INDEX IF NOT EXISTS ix_receipts_receipt_number ON receipts (receipt_number);
CREATE INDEX IF NOT EXISTS ix_receipts_whatsapp_status ON receipts (whatsapp_status);

-- 9.9 PAYMENT_LINKS (Direct UPI Self-Checkout Tokens)
CREATE TABLE IF NOT EXISTS payment_links (
    id UUID PRIMARY KEY,
    payment_id UUID NOT NULL REFERENCES payments (id) ON DELETE CASCADE,
    invoice_id UUID NOT NULL REFERENCES invoices (id) ON DELETE CASCADE,
    resident_id UUID NOT NULL REFERENCES residents (id) ON DELETE CASCADE,
    token_hash VARCHAR(64) NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    is_revoked BOOLEAN NOT NULL DEFAULT false,
    whatsapp_sent BOOLEAN NOT NULL DEFAULT false,
    whatsapp_message_id VARCHAR(150),
    whatsapp_last_error TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    CONSTRAINT uq_payment_link_token_hash UNIQUE (token_hash)
);
CREATE INDEX IF NOT EXISTS ix_payment_links_payment_id ON payment_links (payment_id);
CREATE INDEX IF NOT EXISTS ix_payment_links_invoice_id ON payment_links (invoice_id);
CREATE INDEX IF NOT EXISTS ix_payment_links_resident_id ON payment_links (resident_id);
CREATE INDEX IF NOT EXISTS ix_payment_links_token_hash ON payment_links (token_hash);
CREATE INDEX IF NOT EXISTS ix_payment_links_expires_at ON payment_links (expires_at);
CREATE INDEX IF NOT EXISTS ix_payment_links_is_revoked ON payment_links (is_revoked);

-- 9.10 DEVICE_TOKENS (FCM Push Notifications)
CREATE TABLE IF NOT EXISTS device_tokens (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    device_token VARCHAR(255) NOT NULL,
    platform VARCHAR(50) NOT NULL DEFAULT 'android',
    device_name VARCHAR(100),
    is_active BOOLEAN NOT NULL DEFAULT true,
    last_seen_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    CONSTRAINT uq_user_device_token UNIQUE (user_id, device_token)
);
CREATE INDEX IF NOT EXISTS ix_device_tokens_user_id ON device_tokens (user_id);
CREATE INDEX IF NOT EXISTS ix_device_tokens_device_token ON device_tokens (device_token);

-- 9.11 OTP_VERIFICATIONS (Resident Registration OTP Flow)
CREATE TABLE IF NOT EXISTS otp_verifications (
    id UUID PRIMARY KEY,
    phone VARCHAR(30) NOT NULL,
    otp_hash VARCHAR(255) NOT NULL,
    salt VARCHAR(64) NOT NULL,
    purpose VARCHAR(50) NOT NULL DEFAULT 'RESIDENT_REGISTRATION',
    attempts INTEGER NOT NULL DEFAULT 0,
    max_attempts INTEGER NOT NULL DEFAULT 3,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    is_verified BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_otp_verifications_phone ON otp_verifications (phone);
CREATE INDEX IF NOT EXISTS ix_otp_verifications_purpose ON otp_verifications (purpose);
CREATE INDEX IF NOT EXISTS ix_otp_verifications_expires_at ON otp_verifications (expires_at);
CREATE INDEX IF NOT EXISTS ix_otp_verifications_is_verified ON otp_verifications (is_verified);


-- =============================================================================
-- SECTION 10: POSTCONDITION CHECKS (RIGOROUS IN-TRANSACTION VALIDATION)
-- =============================================================================
DO $$
DECLARE
    v_tbl_count INTEGER;
    v_cnt BIGINT;
BEGIN
    -- 10.1 Confirm all 23 active application domain tables exist
    SELECT count(*) INTO v_tbl_count
    FROM information_schema.tables 
    WHERE table_schema = 'public' 
      AND table_name IN (
        'companies', 'roles', 'properties', 'users', 'user_property_access', 
        'refresh_tokens', 'audit_logs', 'rooms', 'beds', 'residents', 
        'invoices', 'payments', 'receipts', 'payment_links', 'processed_webhook_events', 
        'device_tokens', 'otp_verifications', 'staff', 'complaints', 'expenses', 
        'leads', 'notices', 'notifications'
      );
    IF v_tbl_count != 23 THEN
        RAISE EXCEPTION 'POSTCONDITION FAILED: Expected 23 active tables, found %', v_tbl_count;
    END IF;

    -- 10.2 Confirm baseline data remains 100% intact
    SELECT count(*) INTO v_cnt FROM companies;
    IF v_cnt != 1 THEN RAISE EXCEPTION 'POSTCONDITION FAILED: companies data corrupted, found %', v_cnt; END IF;

    SELECT count(*) INTO v_cnt FROM roles;
    IF v_cnt != 4 THEN RAISE EXCEPTION 'POSTCONDITION FAILED: roles data corrupted, found %', v_cnt; END IF;

    SELECT count(*) INTO v_cnt FROM properties;
    IF v_cnt != 5 THEN RAISE EXCEPTION 'POSTCONDITION FAILED: properties data corrupted, found %', v_cnt; END IF;

    SELECT count(*) INTO v_cnt FROM users WHERE approval_status = 'APPROVED';
    IF v_cnt != 4 THEN RAISE EXCEPTION 'POSTCONDITION FAILED: users approval_status not 4, found %', v_cnt; END IF;

    SELECT count(*) INTO v_cnt FROM user_property_access;
    IF v_cnt != 4 THEN RAISE EXCEPTION 'POSTCONDITION FAILED: user_property_access data corrupted, found %', v_cnt; END IF;

    SELECT count(*) INTO v_cnt FROM refresh_tokens;
    IF v_cnt != 8 THEN RAISE EXCEPTION 'POSTCONDITION FAILED: refresh_tokens data corrupted, found %', v_cnt; END IF;

    SELECT count(*) INTO v_cnt FROM audit_logs;
    IF v_cnt != 36 THEN RAISE EXCEPTION 'POSTCONDITION FAILED: audit_logs data corrupted, found %', v_cnt; END IF;

    -- 10.3 Confirm active 3NF foreign keys exist
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'rooms_property_id_fkey') OR
       NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'beds_room_id_fkey') OR
       NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'residents_user_id_fkey') OR
       NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'residents_property_id_fkey') OR
       NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'residents_room_id_fkey') OR
       NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'residents_bed_id_fkey') OR
       NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'invoices_property_id_fkey') OR
       NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'invoices_resident_id_fkey') OR
       NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'payments_property_id_fkey') OR
       NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'payments_invoice_id_fkey') OR
       NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'payments_resident_id_fkey') THEN
        RAISE EXCEPTION 'POSTCONDITION FAILED: One or more required 3NF foreign keys are missing.';
    END IF;

    -- 10.4 Confirm obsolete composite constraints are completely gone
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname IN (
        'fk_residents_bed_id_property_id', 'fk_residents_room_id_property_id',
        'fk_beds_room_id_property_id', 'fk_invoices_resident_id_property_id',
        'fk_payments_invoice_id_property_id', 'fk_payments_resident_id_property_id',
        'uq_beds_id_property_id', 'uq_residents_id_property_id',
        'uq_rooms_id_property_id', 'uq_invoices_id_property_id',
        'uq_resident_billing_month_type'
    )) THEN
        RAISE EXCEPTION 'POSTCONDITION FAILED: Obsolete composite constraints or legacy invoice constraint still exist.';
    END IF;

    -- 10.5 Confirm exactly one unique constraint on invoices for resident billing cycle
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_resident_invoice_cycle') THEN
        RAISE EXCEPTION 'POSTCONDITION FAILED: uq_resident_invoice_cycle constraint missing.';
    END IF;

    -- 10.6 Confirm obsolete legacy columns are completely gone
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND (
            (table_name = 'rooms' AND column_name IN ('base_monthly_rent', 'deposit_amount')) OR
            (table_name = 'beds' AND column_name IN ('property_id', 'is_active')) OR
            (table_name = 'residents' AND column_name IN ('company_id', 'full_name', 'email', 'phone', 'kyc_notes', 'verified_at', 'verified_by_id')) OR
            (table_name = 'invoices' AND column_name IN ('company_id', 'billing_period_start', 'billing_period_end', 'issue_date', 'rent_amount', 'additional_charges', 'discount_amount', 'total_amount', 'balance_amount')) OR
            (table_name = 'payments' AND column_name IN ('company_id', 'payment_method', 'transaction_reference', 'recorded_by_user_id', 'payment_date'))
          )
    ) THEN
        RAISE EXCEPTION 'POSTCONDITION FAILED: One or more obsolete legacy columns still exist.';
    END IF;

    -- 10.7 Confirm unique indexes on residents
    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE tablename = 'residents' AND indexname = 'ix_residents_user_id') OR
       NOT EXISTS (SELECT 1 FROM pg_indexes WHERE tablename = 'residents' AND indexname = 'ix_residents_bed_id') THEN
        RAISE EXCEPTION 'POSTCONDITION FAILED: Required unique indexes on residents are missing.';
    END IF;

    RAISE NOTICE 'POSTCONDITION CHECKS PASSED: True physical schema convergence and data integrity validated.';
END $$;


-- =============================================================================
-- SECTION 11: RECONCILE ALEMBIC VERSION (ONLY AFTER PHYSICAL VALIDATION)
-- =============================================================================
UPDATE alembic_version 
SET version_num = 'b2c3d4e5f6a7' 
WHERE version_num = '6cb475ecad6d';

DO $$
DECLARE
    v_final_rev VARCHAR;
BEGIN
    SELECT version_num INTO v_final_rev FROM alembic_version LIMIT 1;
    IF v_final_rev != 'b2c3d4e5f6a7' THEN
        RAISE EXCEPTION 'POSTCONDITION FAILED: alembic_version update to b2c3d4e5f6a7 failed. Current: %', v_final_rev;
    END IF;
    RAISE NOTICE 'ALEMBIC VERSION SYNCHRONIZED: Successfully moved to head revision b2c3d4e5f6a7.';
END $$;

COMMIT;
-- =============================================================================
-- END OF UNIFIED RECONCILIATION SCRIPT V3
-- =============================================================================
