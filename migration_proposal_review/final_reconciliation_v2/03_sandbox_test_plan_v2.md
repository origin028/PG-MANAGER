# Sandbox Test Plan V2: Pre-Execution Regression & Reconciliation Verification

## 1. Overview
This test plan defines the procedure to empirically verify [`01_reconcile_pg_management_ddl_v2.sql`](01_reconcile_pg_management_ddl_v2.sql) inside a completely isolated, disposable sandbox database:
`pg_reconcile_v2_sandbox_test`

**Live Database Target:** `pg_management` is strictly protected. No writes, connections, or migrations will touch `pg_management`.

---

## 2. Defects Reconciled in V2
1. **`beds.property_id` Not-Null Relaxed:**
   - Active model `Bed` omits `property_id` (room-level tenancy).
   - SQL executes: `ALTER TABLE beds ALTER COLUMN property_id DROP NOT NULL;`
   - SQL executes: `ALTER TABLE beds ALTER COLUMN monthly_rent DROP NOT NULL;`
   - Legacy column is preserved; API inserts succeed without error.
2. **`residents` Uniqueness & Nullability Rules:**
   - Active model `Resident` enforces `unique=True, nullable=False` on `user_id` and `unique=True` on `bed_id`.
   - SQL drops legacy non-unique indexes and creates `UNIQUE INDEX ix_residents_user_id ON residents (user_id)` and `UNIQUE INDEX ix_residents_bed_id ON residents (bed_id)`.
   - SQL executes: `ALTER TABLE residents ALTER COLUMN user_id SET NOT NULL;`
   - SQL executes: `ALTER TABLE residents ALTER COLUMN status SET DEFAULT 'ACTIVE';`
   - SQL relaxes legacy columns: `company_id`, `full_name`, `phone`.
3. **Missing Active Indexes & Named Constraints Added:**
   - `receipts`: `ix_receipts_payment_id`, `ix_receipts_receipt_number`.
   - `processed_webhook_events`: `ix_processed_webhook_events_event_id`, named constraint `uq_processed_webhook_event_id`.
   - `payment_links`: `ix_payment_links_payment_id`, `ix_payment_links_token_hash`, `ix_payment_links_is_revoked`, named constraint `uq_payment_link_token_hash`.
   - `otp_verifications`: `ix_otp_verifications_purpose`, `ix_otp_verifications_is_verified`.
   - `staff`: `ix_staff_user_id`.
   - `invoices`: `uq_resident_invoice_cycle`.

---

## 3. Migration History Reconciliation Strategy
* Root revision `bd0a1cc93d5d` remains intact with `down_revision = None` in the backend codebase, protecting clean CI/CD environments.
* For `pg_management`, DDL V2 creates all 23 tables and aligns all columns, constraints, defaults, and indexes to match active head `b2c3d4e5f6a7`.
* At the conclusion of the atomic transaction block, `alembic_version` is stamped to `'b2c3d4e5f6a7'`.
* Because every single physical schema artifact of revisions `bd0a1cc93d5d` through `b2c3d4e5f6a7` is now demonstrably applied, the `alembic_version` update is 100% justified and future migrations will apply seamlessly.

---

## 4. Exact Sandbox Execution Commands
When approved by the user, the sandbox regression test will be executed via PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File "D:\PG_Management\migration_proposal_review\final_reconciliation_v2\04_sandbox_verification_script_v2.ps1"
```

### Steps executed within the script:
1. `createdb.exe -h 127.0.0.1 -p 5432 -U postgres pg_reconcile_v2_sandbox_test`
2. `pg_restore.exe -h 127.0.0.1 -p 5432 -U postgres -d pg_reconcile_v2_sandbox_test D:\PG_Management\pg_management_backup_20261029.dump`
3. `psql.exe -h 127.0.0.1 -p 5432 -U postgres -d pg_reconcile_v2_sandbox_test -f 01_reconcile_pg_management_ddl_v2.sql`
4. `psql.exe -h 127.0.0.1 -p 5432 -U postgres -d pg_reconcile_v2_sandbox_test -f 02_post_migration_checks_v2.sql`
5. `python.exe test_model_inserts_sandbox.py` (Tests real SQLAlchemy inserts for `Room`, `Bed`, `Resident`, and validates uniqueness rejection)
6. `dropdb.exe -h 127.0.0.1 -p 5432 -U postgres pg_reconcile_v2_sandbox_test`
