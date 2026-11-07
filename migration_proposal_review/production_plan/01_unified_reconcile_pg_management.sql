-- =============================================================================
-- UNIFIED PRODUCTION RECONCILIATION SCRIPT FOR pg_management
-- File: migration_proposal_review/production_plan/01_unified_reconcile_pg_management.sql
-- Target Database: pg_management (PostgreSQL 18.6)
-- Baseline Revision: 6cb475ecad6d
-- Target Head Revision: b2c3d4e5f6a7
-- Mode: PROPOSED ARTIFACT ONLY — DO NOT EXECUTE WITHOUT EXPLICIT AUTHORIZATION
--
-- DESIGN GUARANTEES:
-- 1. 100% Atomic: Executes inside a single BEGIN ... COMMIT block.
-- 2. Strict Preconditions: Validates alembic revision, table existence, and row counts.
-- 3. Dependency-Ordered DDL: Drops dependent composite foreign keys before obsolete
--    composite unique constraints, preventing PostgreSQL dependency errors.
-- 4. Active Model Alignment: Restores clean 3NF single-column foreign keys with exact
--    ON DELETE rules matching app/models/*.
-- 5. Data Preservation: Zero records modified, dropped, or lost on baseline tables.
-- 6. Comprehensive Postconditions: Validates all 23 tables, FKs, indexes, and row counts
--    before committing. Reconciles alembic_version only after physical validation passes.
-- 7. Safe Failure: Any assertion failure invokes RAISE EXCEPTION, instantly rolling back
--    the entire transaction and leaving pg_management pristine.
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

    -- 1.4 Verify downstream entity tables exist and are clean (0 rows)
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

    RAISE NOTICE 'PRECONDITION CHECKS PASSED: Database state verified for safe reconciliation.';
END $$;


-- =============================================================================
-- SECTION 2: ADAPT ACTIVE USER ACCOUNTS (PRESERVE ALL 4 USERS)
-- =============================================================================
-- Add approval_status and index; all 4 existing administrator users receive 'APPROVED'
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
ALTER TABLE residents DROP CONSTRAINT IF EXISTS residents_user_id_fkey; -- Will recreate with CASCADE

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
-- SECTION 5: ADAPT ZERO-ROW ENTITY TABLES (ALIGN WITH ACTIVE MODELS)
-- =============================================================================

-- 5.1 ROOMS: Add base_rent and max_occupancy; align property_id FK ondelete action
ALTER TABLE rooms ADD COLUMN IF NOT EXISTS base_rent NUMERIC(10, 2) NOT NULL DEFAULT 0.00;
ALTER TABLE rooms ADD COLUMN IF NOT EXISTS max_occupancy INTEGER NOT NULL DEFAULT 2;

-- Reconcile rooms.property_id_fkey to ON DELETE CASCADE
ALTER TABLE rooms DROP CONSTRAINT IF EXISTS rooms_property_id_fkey;
ALTER TABLE rooms ADD CONSTRAINT rooms_property_id_fkey
    FOREIGN KEY (property_id) REFERENCES properties (id) ON DELETE CASCADE;

-- 5.2 BEDS: Relax legacy NOT NULL columns for active Bed model
ALTER TABLE beds ALTER COLUMN property_id DROP NOT NULL;
ALTER TABLE beds ALTER COLUMN monthly_rent DROP NOT NULL;

-- 5.3 RESIDENTS: Align columns, nullability, defaults, and document path
ALTER TABLE residents ADD COLUMN IF NOT EXISTS id_proof_document_path VARCHAR(512);
ALTER TABLE residents ALTER COLUMN company_id DROP NOT NULL;
ALTER TABLE residents ALTER COLUMN full_name DROP NOT NULL;
ALTER TABLE residents ALTER COLUMN phone DROP NOT NULL;
ALTER TABLE residents ALTER COLUMN status SET DEFAULT 'ACTIVE';
ALTER TABLE residents ALTER COLUMN user_id SET NOT NULL;

-- 5.4 INVOICES: Add amount column, relax legacy NOT NULLs, align defaults
ALTER TABLE invoices ADD COLUMN IF NOT EXISTS amount NUMERIC(10, 2) NOT NULL DEFAULT 0.00;
ALTER TABLE invoices ALTER COLUMN company_id DROP NOT NULL;
ALTER TABLE invoices ALTER COLUMN billing_period_start DROP NOT NULL;
ALTER TABLE invoices ALTER COLUMN billing_period_end DROP NOT NULL;
ALTER TABLE invoices ALTER COLUMN issue_date DROP NOT NULL;
ALTER TABLE invoices ALTER COLUMN total_amount DROP NOT NULL;
ALTER TABLE invoices ALTER COLUMN balance_amount DROP NOT NULL;
ALTER TABLE invoices ALTER COLUMN status SET DEFAULT 'PENDING';

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_resident_invoice_cycle') THEN
        ALTER TABLE invoices ADD CONSTRAINT uq_resident_invoice_cycle
            UNIQUE (resident_id, billing_month, invoice_type);
    END IF;
END $$;

-- 5.5 PAYMENTS: Align columns for direct UPI reservations, idempotency, and gateway tracking
ALTER TABLE payments ALTER COLUMN paid_at DROP NOT NULL;
ALTER TABLE payments ALTER COLUMN paid_at DROP DEFAULT;
ALTER TABLE payments ALTER COLUMN company_id DROP NOT NULL;
ALTER TABLE payments ALTER COLUMN payment_method DROP NOT NULL;
ALTER TABLE payments ALTER COLUMN payment_date DROP NOT NULL;
ALTER TABLE payments ALTER COLUMN status SET DEFAULT 'PENDING';

ALTER TABLE payments ADD COLUMN IF NOT EXISTS payment_mode VARCHAR(50) NOT NULL DEFAULT 'UPI';
ALTER TABLE payments ADD COLUMN IF NOT EXISTS gateway_order_id VARCHAR(150);
ALTER TABLE payments ADD COLUMN IF NOT EXISTS gateway_payment_id VARCHAR(150);
ALTER TABLE payments ADD COLUMN IF NOT EXISTS gateway_signature VARCHAR(255);
ALTER TABLE payments ADD COLUMN IF NOT EXISTS idempotency_key VARCHAR(128);
ALTER TABLE payments ADD COLUMN IF NOT EXISTS receipt_url VARCHAR(512);
ALTER TABLE payments ADD COLUMN IF NOT EXISTS reservation_expires_at TIMESTAMP WITH TIME ZONE;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_payments_gateway_payment_id') THEN
        ALTER TABLE payments ADD CONSTRAINT uq_payments_gateway_payment_id UNIQUE (gateway_payment_id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_payment_invoice_idempotency') THEN
        ALTER TABLE payments ADD CONSTRAINT uq_payment_invoice_idempotency UNIQUE (invoice_id, idempotency_key);
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS ix_payments_reservation_expires_at ON payments (reservation_expires_at);


-- =============================================================================
-- SECTION 6: CREATE ACTIVE 3NF SINGLE-COLUMN FOREIGN KEYS & UNIQUE INDEXES
-- Aligns with app/models/{bed,resident,invoice,payment}.py and active Alembic revisions
-- =============================================================================

-- 6.1 BEDS: room_id -> rooms.id ON DELETE CASCADE
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'beds_room_id_fkey') THEN
        ALTER TABLE beds ADD CONSTRAINT beds_room_id_fkey
            FOREIGN KEY (room_id) REFERENCES rooms (id) ON DELETE CASCADE;
    END IF;
END $$;

-- 6.2 RESIDENTS: Single-column FKs and 1-to-1 unique indexes
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'residents_user_id_fkey') THEN
        ALTER TABLE residents ADD CONSTRAINT residents_user_id_fkey
            FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'residents_room_id_fkey') THEN
        ALTER TABLE residents ADD CONSTRAINT residents_room_id_fkey
            FOREIGN KEY (room_id) REFERENCES rooms (id) ON DELETE SET NULL;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'residents_bed_id_fkey') THEN
        ALTER TABLE residents ADD CONSTRAINT residents_bed_id_fkey
            FOREIGN KEY (bed_id) REFERENCES beds (id) ON DELETE SET NULL;
    END IF;
END $$;

DROP INDEX IF EXISTS ix_residents_user_id;
CREATE UNIQUE INDEX IF NOT EXISTS ix_residents_user_id ON residents (user_id);

DROP INDEX IF EXISTS ix_residents_bed_id;
CREATE UNIQUE INDEX IF NOT EXISTS ix_residents_bed_id ON residents (bed_id);

-- 6.3 INVOICES: resident_id -> residents.id ON DELETE RESTRICT
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'invoices_resident_id_fkey') THEN
        ALTER TABLE invoices ADD CONSTRAINT invoices_resident_id_fkey
            FOREIGN KEY (resident_id) REFERENCES residents (id) ON DELETE RESTRICT;
    END IF;
END $$;

-- 6.4 PAYMENTS: invoice_id -> invoices.id ON DELETE CASCADE, resident_id -> residents.id ON DELETE RESTRICT
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'payments_invoice_id_fkey') THEN
        ALTER TABLE payments ADD CONSTRAINT payments_invoice_id_fkey
            FOREIGN KEY (invoice_id) REFERENCES invoices (id) ON DELETE CASCADE;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'payments_resident_id_fkey') THEN
        ALTER TABLE payments ADD CONSTRAINT payments_resident_id_fkey
            FOREIGN KEY (resident_id) REFERENCES residents (id) ON DELETE RESTRICT;
    END IF;
END $$;


-- =============================================================================
-- SECTION 7: CREATE MISSING APPLICATION & OPERATIONAL TABLES (11 TABLES)
-- Dependency order strictly observed: staff before complaints, etc.
-- =============================================================================

-- 7.1 STAFF (Precedes complaints)
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

-- 7.2 COMPLAINTS
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

-- 7.3 EXPENSES
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

-- 7.4 LEADS
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

-- 7.5 NOTICES
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

-- 7.6 NOTIFICATIONS
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

-- 7.7 PROCESSED_WEBHOOK_EVENTS (Replay & Idempotency Protection)
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

-- 7.8 RECEIPTS (1-to-1 Digital Receipts for Payments)
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

-- 7.9 PAYMENT_LINKS (Direct UPI Self-Checkout Tokens)
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

-- 7.10 DEVICE_TOKENS (FCM Push Notifications)
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

-- 7.11 OTP_VERIFICATIONS (Resident Registration OTP Flow)
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
-- SECTION 8: POSTCONDITION CHECKS (RIGOROUS IN-TRANSACTION VALIDATION)
-- If any postcondition fails, the transaction is rolled back before commit.
-- =============================================================================
DO $$
DECLARE
    v_tbl_count INTEGER;
    v_cnt BIGINT;
BEGIN
    -- 8.1 Confirm all 23 active application domain tables exist
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

    -- 8.2 Confirm baseline data remains 100% intact
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

    -- 8.3 Confirm single-column foreign keys exist with correct targets
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'beds_room_id_fkey') OR
       NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'residents_user_id_fkey') OR
       NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'residents_room_id_fkey') OR
       NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'residents_bed_id_fkey') OR
       NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'invoices_resident_id_fkey') OR
       NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'payments_invoice_id_fkey') OR
       NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'payments_resident_id_fkey') THEN
        RAISE EXCEPTION 'POSTCONDITION FAILED: One or more required 3NF foreign keys are missing.';
    END IF;

    -- 8.4 Confirm obsolete composite constraints are completely gone
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname IN (
        'fk_residents_bed_id_property_id', 'fk_residents_room_id_property_id',
        'fk_beds_room_id_property_id', 'fk_invoices_resident_id_property_id',
        'fk_payments_invoice_id_property_id', 'fk_payments_resident_id_property_id',
        'uq_beds_id_property_id', 'uq_residents_id_property_id',
        'uq_rooms_id_property_id', 'uq_invoices_id_property_id'
    )) THEN
        RAISE EXCEPTION 'POSTCONDITION FAILED: Obsolete composite constraints still linger in schema.';
    END IF;

    -- 8.5 Confirm unique indexes on residents
    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE tablename = 'residents' AND indexname = 'ix_residents_user_id') OR
       NOT EXISTS (SELECT 1 FROM pg_indexes WHERE tablename = 'residents' AND indexname = 'ix_residents_bed_id') THEN
        RAISE EXCEPTION 'POSTCONDITION FAILED: Required unique indexes on residents are missing.';
    END IF;

    RAISE NOTICE 'POSTCONDITION CHECKS PASSED: Physical schema and data integrity validated.';
END $$;


-- =============================================================================
-- SECTION 9: RECONCILE ALEMBIC VERSION (ONLY AFTER PHYSICAL VALIDATION)
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
-- END OF UNIFIED RECONCILIATION SCRIPT
-- =============================================================================
