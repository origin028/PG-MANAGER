# Alembic Revision Graph Architecture & Reconciliation Strategy

## 1. Problem Statement: Why a Naive Merge Fails

In `pg_management`, the database reports:
```sql
SELECT version_num FROM alembic_version; -- '6cb475ecad6d'
```

The active backend tree (`pg-management-system/backend/migrations/versions/`) is structured as:
```
bd0a1cc93d5d (down_revision = None)
  ↓
f1c4a0e3d2b1 (add receipts)
  ↓
4c11d205aa12 (add payment reservations & idempotency)
  ↓
7c32e912ab01 (add processed webhook events)
  ↓
9a81b2c3d4e5 (add payment links)
  ↓
a1b2c3d4e5f6 (add device tokens)
  ↓
b2c3d4e5f6a7 (add resident approval & OTP - ACTIVE HEAD)
```

### The Fatal Collision of `bd0a1cc93d5d`:
`bd0a1cc93d5d` is a monolithic migration generated from an empty database. It includes:
1. `op.create_table('companies', ...)`
2. `op.create_table('roles', ...)`
3. `op.create_table('properties', ...)`
4. `op.create_table('users', ...)`
5. `op.create_table('audit_logs', ...)`
6. `op.create_table('refresh_tokens', ...)`
7. `op.create_table('rooms', ...)`
8. `op.create_table('beds', ...)`
9. `op.create_table('residents', ...)`
10. `op.create_table('invoices', ...)`
11. `op.create_table('payments', ...)`
12. `op.create_table('staff', ...)`
13. `op.create_table('complaints', ...)`
14. `op.create_table('expenses', ...)`
15. `op.create_table('leads', ...)`
16. `op.create_table('notices', ...)`
17. `op.create_table('notifications', ...)`

Tables 1 through 11 **already exist in `pg_management`** (created by legacy migrations `910643d8744a` through `6cb475ecad6d`).
Tables 12 through 17 **do not exist**.

If an Alembic merge revision has `down_revision = ("reconcile_branch", "b2c3d4e5f6a7")`:
To reach `b2c3d4e5f6a7`, Alembic is required by DAG rules to execute all unapplied ancestors of `b2c3d4e5f6a7`, starting at `bd0a1cc93d5d`. When `bd0a1cc93d5d` attempts to execute `op.create_table('companies')`, PostgreSQL aborts the transaction with `relation "companies" already exists`.

Furthermore, modifying `bd0a1cc93d5d` to have `down_revision = "6cb475ecad6d"` breaks any fresh database initialization (CI/CD pipelines, Docker environments, and local unit test suites) because `6cb475ecad6d` does not exist in `pg-management-system/backend/migrations/versions`. Alembic throws `Can't locate revision identified by '6cb475ecad6d'`.

---

## 2. Robust Reconciliation Architecture: Direct Atomic Transaction

To preserve clean database initializations and ensure zero runtime failures:

1. **Leave `bd0a1cc93d5d_initial_schema.py` intact (`down_revision = None`)**:
   - Fresh databases, SQLite test suites, and CI/CD pipelines continue building the schema from scratch without dependency on legacy migrations.
2. **Reconcile `pg_management` via Transactional DDL**:
   - Execute `02_reconcile_pg_management_ddl.sql` inside a single PostgreSQL `BEGIN ... COMMIT;` transaction block.
   - All 12 missing operational and payment tables are created.
   - Schema differences on `users`, `rooms`, `residents`, `invoices`, and `payments` are resolved idempotently.
   - `uq_resident_invoice_cycle` is created on `invoices`.
   - `check_in_date` on `residents` is preserved as `NOT NULL`.
3. **Atomic Head Synchronization**:
   - Inside the very same transaction block, update `alembic_version`:
     ```sql
     UPDATE alembic_version SET version_num = 'b2c3d4e5f6a7';
     ```
   - This atomically transitions `pg_management` from `6cb475ecad6d` directly to active head `b2c3d4e5f6a7`.
   - Any failure automatically rolls back the entire script, leaving existing data and `6cb475ecad6d` intact.
   - Future migrations applied via `alembic upgrade head` cleanly build upon `b2c3d4e5f6a7`.
