-- =============================================================================
-- RECONCILIATION V2: FULL PHYSICAL SCHEMA RECONCILIATION FOR pg_management
-- Generated: 2026-10-29
-- Target Database: pg_management (PostgreSQL 18.6)
-- Active Backend Head: b2c3d4e5f6a7
-- NOTE: THIS SCRIPT IS TRANSACTIONAL AND IDEMPOTENT.
-- All operations run inside BEGIN ... COMMIT.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. ADAPT EXISTING TABLES CONTAINING LIVE BUSINESS DATA
-- -----------------------------------------------------------------------------

-- USERS: Add approval_status and index (existing 4 users receive 'APPROVED')
ALTER TABLE users ADD COLUMN IF NOT EXISTS approval_status VARCHAR(50) DEFAULT 'APPROVED' NOT NULL;
CREATE INDEX IF NOT EXISTS ix_users_approval_status ON users (approval_status);

-- COMPANIES, ROLES, PROPERTIES, USER_PROPERTY_ACCESS, REFRESH_TOKENS, AUDIT_LOGS:
-- Fully aligned with active models. All 55 existing rows are untouched.


-- -----------------------------------------------------------------------------
-- 2. ADAPT ZERO-ROW ENTITY TABLES (SAFE STRUCTURAL ALIGNMENT)
-- -----------------------------------------------------------------------------

-- ROOMS (0 rows): Add base_rent and max_occupancy
ALTER TABLE rooms ADD COLUMN IF NOT EXISTS base_rent NUMERIC(10, 2) NOT NULL DEFAULT 0.00;
ALTER TABLE rooms ADD COLUMN IF NOT EXISTS max_occupancy INTEGER NOT NULL DEFAULT 2;

-- BEDS (0 rows): Relax legacy-only NOT NULL columns for active model inserts
ALTER TABLE beds ALTER COLUMN property_id DROP NOT NULL;
ALTER TABLE beds ALTER COLUMN monthly_rent DROP NOT NULL;

-- RESIDENTS (0 rows): Align nullability, defaults, document path, and unique constraints
ALTER TABLE residents ADD COLUMN IF NOT EXISTS id_proof_document_path VARCHAR(512);
ALTER TABLE residents ALTER COLUMN company_id DROP NOT NULL;
ALTER TABLE residents ALTER COLUMN full_name DROP NOT NULL;
ALTER TABLE residents ALTER COLUMN phone DROP NOT NULL;
ALTER TABLE residents ALTER COLUMN status SET DEFAULT 'ACTIVE';
ALTER TABLE residents ALTER COLUMN user_id SET NOT NULL;

-- Residents Uniqueness: Enforce 1-to-1 resident-user and 1-to-1 resident-bed mapping
DROP INDEX IF EXISTS ix_residents_user_id;
CREATE UNIQUE INDEX IF NOT EXISTS ix_residents_user_id ON residents (user_id);

DROP INDEX IF EXISTS ix_residents_bed_id;
CREATE UNIQUE INDEX IF NOT EXISTS ix_residents_bed_id ON residents (bed_id);

-- INVOICES (0 rows): Add amount, align defaults, drop legacy NOT NULLs, enforce billing cycle constraint
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
        ALTER TABLE invoices ADD CONSTRAINT uq_resident_invoice_cycle UNIQUE (resident_id, billing_month, invoice_type);
    END IF;
END $$;

-- PAYMENTS (0 rows): Add UPI reservation, idempotency, gateway tracking, and constraints
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


-- -----------------------------------------------------------------------------
-- 3. CREATE MISSING OPERATIONAL TABLES (FOREIGN-KEY ORDER AWARE)
-- -----------------------------------------------------------------------------

-- A. STAFF (Precedes complaints due to FK dependency)
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

-- B. COMPLAINTS (References properties, residents, and staff)
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

-- C. EXPENSES (References properties, users)
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

-- D. LEADS (References properties)
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

-- E. NOTICES (References properties, users)
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

-- F. NOTIFICATIONS (References users)
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


-- -----------------------------------------------------------------------------
-- 4. CREATE MISSING PAYMENT, RECEIPT, TOKEN & OTP TABLES (WITH ALL INDEXES)
-- -----------------------------------------------------------------------------

-- G. PROCESSED_WEBHOOK_EVENTS (Replay & Idempotency Protection)
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

-- H. RECEIPTS (Digital Payment Receipts with 1-to-1 Payment Constraint)
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

-- I. PAYMENT_LINKS (Opaque Checkout Tokens)
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

-- J. DEVICE_TOKENS (FCM Push Notifications)
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

-- K. OTP_VERIFICATIONS (Resident Registration OTP Flow)
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


-- -----------------------------------------------------------------------------
-- 5. SYNCHRONIZE ALEMBIC VERSION ATOMICALLY TO ACTIVE HEAD
-- -----------------------------------------------------------------------------
UPDATE alembic_version SET version_num = 'b2c3d4e5f6a7';

COMMIT;
