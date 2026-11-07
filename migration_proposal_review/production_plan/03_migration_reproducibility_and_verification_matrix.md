# PG Management — Migration Reproducibility & Schema Alignment Matrix

**Document:** `migration_proposal_review/production_plan/03_migration_reproducibility_and_verification_matrix.md`  
**Status:** READ-ONLY AUDIT & ARCHITECTURAL VERIFICATION  

---

## 1. Dual Migration Path Architecture

```
Path A: Fresh Deployment (CI/CD, Docker, Staging)
[Empty Database] 
  ──> alembic upgrade head 
  ──> Revisions: bd0a1cc93d5d -> f1c4a0e3d2b1 -> 4c11d205aa12 -> 7c32e912ab01 -> 9a81b2c3d4e5 -> a1b2c3d4e5f6 -> b2c3d4e5f6a7
  ──> Physical Schema Head (23 Tables, 3NF Foreign Keys, 0 Composite Constraints)

Path B: Live Database Reconciliation (pg_management)
[Legacy Database @ 6cb475ecad6d] (55 Baseline Rows + 36 Audit Logs Preserved)
  ──> 01_unified_reconcile_pg_management.sql (Atomic Transaction)
  ──> Preconditions Checked -> Composite FKs Dropped -> 3NF FKs Added -> 11 Tables Created -> Postconditions Validated
  ──> alembic_version updated to b2c3d4e5f6a7
  ──> Physical Schema Head (Identical Schema & Invariants)

Convergence: Future Migrations (Phase 3+)
Both paths converge at revision b2c3d4e5f6a7.
Future migrations (down_revision = 'b2c3d4e5f6a7') apply identically to both fresh and reconciled databases.
```

---

## 2. Structural Alignment Comparison Matrix

| Component | Legacy Database (`6cb475ecad6d`) | Active Backend Models / Head (`b2c3d4e5f6a7`) | Unified Reconciliation Script Action |
| :--- | :--- | :--- | :--- |
| **`alembic_version`** | `6cb475ecad6d` | `b2c3d4e5f6a7` | Synchronized to `b2c3d4e5f6a7` post-validation |
| **Total Domain Tables** | 12 tables | 23 tables | 11 missing tables created with exact indexes |
| **`users.approval_status`** | Missing | `VARCHAR(50) DEFAULT 'APPROVED'` | Added; existing 4 users backfilled `APPROVED` |
| **`rooms.base_rent`** | Legacy `base_monthly_rent` only | `NUMERIC(10, 2) DEFAULT 0.00` | Added column `base_rent` |
| **`rooms.max_occupancy`**| Missing | `INTEGER DEFAULT 2` | Added column `max_occupancy` |
| **`beds.property_id`** | `NOT NULL` | `NULLABLE` (active model omits property_id) | Column relaxed to `DROP NOT NULL` |
| **`beds.monthly_rent`** | `NOT NULL` | `NULLABLE` | Column relaxed to `DROP NOT NULL` |
| **`beds` FK to Room** | Composite `(room_id, property_id)` | Single-column `room_id -> rooms.id` (CASCADE) | Replaced with `beds_room_id_fkey` |
| **`beds` Unique** | `uq_beds_id_property_id` | Standard PK `id` + `uq_bed_room_bed_number` | Obsolete composite constraint dropped |
| **`residents.bed_id` FK**| Composite `(bed_id, property_id)` | Single-column `bed_id -> beds.id` (SET NULL) | Replaced with `residents_bed_id_fkey` |
| **`residents.room_id` FK**| Composite `(room_id, property_id)`| Single-column `room_id -> rooms.id` (SET NULL)| Replaced with `residents_room_id_fkey` |
| **`residents.user_id` FK**| `ON DELETE SET NULL` | `ON DELETE CASCADE` | Recreated with `ON DELETE CASCADE` |
| **`residents` Uniqueness**| Non-unique indexes | 1-to-1 Unique: `user_id` and `bed_id` | `ix_residents_user_id` & `ix_residents_bed_id` UNIQUE |
| **`invoices` FK to Resident**| Composite `(resident_id, property_id)` | Single-column `resident_id -> residents.id` | Replaced with `invoices_resident_id_fkey` |
| **`payments` FK to Invoice**| Composite `(invoice_id, property_id)` | Single-column `invoice_id -> invoices.id` (CASCADE)| Replaced with `payments_invoice_id_fkey` |
| **`payments` FK to Resident**| Composite `(resident_id, property_id)`| Single-column `resident_id -> residents.id` | Replaced with `payments_resident_id_fkey` |
| **`payments` UPI Fields** | Missing reservation/gateway cols | `gateway_order_id`, `idempotency_key`, etc. | Added all 7 direct UPI columns & indexes |

---

## 3. Autogenerate & Future Migration Predictability

Because `01_unified_reconcile_pg_management.sql` aligns the live PostgreSQL schema exactly with SQLAlchemy's `Base.metadata`:
1. **Zero Schema Drift:** Running `alembic revision --autogenerate` against the reconciled database detects zero unmanaged changes.
2. **Deterministic Foreign Keys:** Active models query single columns (`bed.room_id`, `resident.bed_id`, `resident.room_id`). No model writes `bed.property_id`. Eliminating composite foreign keys guarantees model inserts will never fail with foreign key reference mismatch errors.
3. **Reproducibility Verified:** Proven in sandbox regression tests where active SQLAlchemy model inserts for `Property`, `Room`, `Bed`, `User`, and `Resident` passed without constraint violation.
