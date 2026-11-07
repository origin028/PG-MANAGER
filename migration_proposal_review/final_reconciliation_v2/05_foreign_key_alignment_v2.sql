-- =============================================================================
-- CORRECTION: FOREIGN KEY ALIGNMENT FOR pg_management RECONCILIATION
-- Target Database: Disposable Sandbox / pg_management (PostgreSQL 18.6)
-- Revision: b2c3d4e5f6a7
-- Description: Reconciles legacy composite foreign keys with active models
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- PRECONDITIONS CHECK
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    -- Verify tables exist
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'residents') THEN
        RAISE EXCEPTION 'Precondition Failed: Table "residents" does not exist.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'beds') THEN
        RAISE EXCEPTION 'Precondition Failed: Table "beds" does not exist.';
    END IF;
END $$;


-- -----------------------------------------------------------------------------
-- 1. DROP LEGACY COMPOSITE FOREIGN KEYS ON RESIDENTS FIRST
-- (Must precede dropping uq_beds_id_property_id due to foreign key dependency)
-- -----------------------------------------------------------------------------
ALTER TABLE residents DROP CONSTRAINT IF EXISTS fk_residents_bed_id_property_id;
ALTER TABLE residents DROP CONSTRAINT IF EXISTS fk_residents_room_id_property_id;
ALTER TABLE residents DROP CONSTRAINT IF EXISTS residents_user_id_fkey;

-- -----------------------------------------------------------------------------
-- 2. RECONCILE BEDS CONSTRAINTS & FOREIGN KEYS
-- Align with app/models/bed.py: room_id -> rooms.id ON DELETE CASCADE
-- -----------------------------------------------------------------------------
ALTER TABLE beds DROP CONSTRAINT IF EXISTS fk_beds_room_id_property_id;
ALTER TABLE beds DROP CONSTRAINT IF EXISTS uq_beds_id_property_id;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'beds_room_id_fkey') THEN
        ALTER TABLE beds ADD CONSTRAINT beds_room_id_fkey
            FOREIGN KEY (room_id) REFERENCES rooms (id) ON DELETE CASCADE;
    END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 3. ADD ACTIVE SINGLE-COLUMN FOREIGN KEYS ON RESIDENTS
-- Align with app/models/resident.py:
--   bed_id -> beds.id ON DELETE SET NULL
--   room_id -> rooms.id ON DELETE SET NULL
--   user_id -> users.id ON DELETE CASCADE
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'residents_bed_id_fkey') THEN
        ALTER TABLE residents ADD CONSTRAINT residents_bed_id_fkey
            FOREIGN KEY (bed_id) REFERENCES beds (id) ON DELETE SET NULL;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'residents_room_id_fkey') THEN
        ALTER TABLE residents ADD CONSTRAINT residents_room_id_fkey
            FOREIGN KEY (room_id) REFERENCES rooms (id) ON DELETE SET NULL;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'residents_user_id_fkey') THEN
        ALTER TABLE residents ADD CONSTRAINT residents_user_id_fkey
            FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE;
    END IF;
END $$;


-- -----------------------------------------------------------------------------
-- POSTCONDITIONS CHECK
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    -- Verify single-column FKs exist
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'residents_bed_id_fkey') THEN
        RAISE EXCEPTION 'Postcondition Failed: residents_bed_id_fkey not created.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'residents_room_id_fkey') THEN
        RAISE EXCEPTION 'Postcondition Failed: residents_room_id_fkey not created.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'residents_user_id_fkey') THEN
        RAISE EXCEPTION 'Postcondition Failed: residents_user_id_fkey not created.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'beds_room_id_fkey') THEN
        RAISE EXCEPTION 'Postcondition Failed: beds_room_id_fkey not created.';
    END IF;
END $$;

COMMIT;
