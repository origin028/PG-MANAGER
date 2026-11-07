# PG Management — Final Backend Audit Report

**Date:** 2026-10-25
**Scope:** Backend API at `D:\PG_Management`. Frontend contract compatibility, genuine gaps, migrations, tests, and remaining manual configuration.
**Approach:** Focused fixes only. No project rebuild, no unrelated features.

---

## 1. Safety and Environment

- The production/development database `pg_management` was **not** connected to, migrated, or modified.
- All PostgreSQL verification ran against `pg_management_test` only. The effective database name was confirmed before every command (`current_database() = pg_management_test`).
- The test database was returned to its seeded state after concurrency testing (`properties=5`, `users=4`, `residents=0`, `invoices=0`, `payments=0`).
- SQLAlchemy 2.0.43 is used because Windows Application Control blocks SQLAlchemy 2.1.6's compiled `_util_cy` DLL. This satisfies the declared `sqlalchemy>=2.0.30`.

---

## 2. Verified Endpoint Inventory

`app.openapi()` exposes **63 operations**:

| Area | Verified operations |
|---|---|
| Health / root | `GET /`, `GET /api/v1/health` |
| Auth | `POST /auth/login`, `POST /auth/refresh`, `POST /auth/logout`, `POST /auth/change-password`, `POST /auth/register`, `POST /auth/verify-otp`, `GET /auth/me` |
| Properties | `GET /properties`, `POST /properties`, `GET /properties/{id}`, `GET /properties/{id}/rooms`, `POST /properties/{id}/rooms`, `GET /properties/{id}/beds`, `GET /properties/{id}/dashboard` |
| Rooms | `GET /rooms`, `GET /rooms/{id}`, `PUT /rooms/{id}`, `GET /rooms/{id}/beds`, `POST /rooms/{id}/beds`, `PUT /rooms/{id}/beds/{bed_id}` |
| Beds | `GET /beds`, `GET /beds/{id}`, `PUT /beds/{id}`, `PATCH /beds/{id}/status` |
| Residents | `GET /residents`, `POST /residents`, `GET /residents/me`, `GET /residents/me/occupancy`, `GET /residents/{id}`, `PUT /residents/{id}`, `POST /residents/{id}/check-in`, `POST /residents/{id}/check-out`, `PATCH /residents/{id}/kyc`, `GET /residents/{id}/occupancy` |
| Invoices | `GET /invoices`, `POST /invoices`, `GET /invoices/summary`, `GET /invoices/me`, `GET /invoices/{id}`, `POST /invoices/{id}/issue`, `POST /invoices/{id}/cancel`, `POST /invoices/{id}/record-payment`, `PUT /invoices/{id}/adjust`, `GET /invoices/{id}/receipt` |
| Payments | `GET /payments`, `GET /payments/me`, `GET /payments/{id}`, `POST /payments`, `POST /payments/{id}/refund` |
| Users | `GET /users`, `POST /users`, `GET /users/{id}`, `POST /users/{id}/assign-properties` |
| Audit | `GET /audit-logs` |
| Complaints | `GET /complaints`, `POST /complaints`, `PUT /complaints/{id}` |
| Expenses | `GET /expenses`, `POST /expenses` |
| Staff | `GET /staff`, `POST /staff` |

The previously missing integration contract points — dashboard, receipt PDF, bank-transfer-to-UUID booking flow, and billing mutation routes — are present and tested.

---

## 3. Gaps Fixed

| # | Gap | Fix | Verified by |
|---|---|---|---|
| 1 | `POST /auth/register` used invalid `Company` fields, assigned the first role instead of `SUPER_ADMIN`, and accepted `super_key` without real OTP semantics. | Rewrote registration/verification: email normalization, explicit `SUPER_ADMIN` role, 8-character minimum password, SHA-256 OTP storage, constant-time comparison, configurable expiry and attempt limits, timezone-safe expiry, account activation on success, truthful `email_sent`. Removed duplicate shadow `login_new` route. | `test_register_verify_otp_flow_and_email_state`, `test_otp_expiry_and_attempt_limits`, existing auth tests |
| 2 | No downloadable receipt endpoint. | Added `GET /invoices/{id}/receipt` returning a real PDF (`%PDF-` signature, `Content-Disposition`, `Content-Length`) through dependency-free `pdf_service`. Authorization reuses invoice access rules. | `test_receipt_pdf_generation_and_authorization` |
| 3 | Dashboard read nonexistent `Invoice.balance_due` / `amount_paid` fields and did not enforce property scope. | Rewrote dashboard against `balance_amount` / `paid_amount`, added role restriction (`SUPER_ADMIN`, `PROPERTY_MANAGER`, `STAFF`) and `verify_property_access`. | `test_property_dashboard_metrics_and_scoping` |
| 4 | `PUT /rooms/{room_id}/beds/{bed_id}` ignored room ownership and allowed manual `OCCUPIED`. | Bed must belong to the room; property scope enforced; manual `OCCUPIED` rejected; status changes blocked while an active resident exists; inactive beds restricted to `MAINTENANCE`. | `test_bed_status_transitions_via_room_route` |
| 5 | Admission/check-in did not create the initial rent invoice. | Added idempotent `build_initial_rent_invoice()` per resident/month/RENT, generated on immediate admission and on check-in. Partial payments never mark invoices `PAID`. | `test_checkin_generates_single_initial_rent_invoice_and_blocks_duplicate_bed` |
| 6 | No invoice adjustment or invoice-scoped payment route. | Added `PUT /invoices/{id}/adjust` with row lock, paid-floor validation, cancellation guard, status recalculation, and audit trail; added `POST /invoices/{id}/record-payment` with partial/full settlement rules. | `test_invoice_adjustment_and_payment_transitions` |
| 7 | Complaints/expenses/staff endpoints were minimal company-wide stubs. | Reimplemented with validated payloads, company/property scoping, role checks, status normalization, persistence, and audit logging. | `test_complaints_scoping_workflow_and_rbac`, `test_expenses_persistence_validation_and_rbac`, `test_staff_persistence_validation_and_rbac` |
| 8 | Registration claimed OTP delivery without an email transport. | Added `email_service` using SMTP only when `EMAIL_ENABLED=true` and `SMTP_HOST`/`EMAIL_FROM` exist. Response reports the real delivery state; no fake sends. | `test_register_verify_otp_flow_and_email_state` |
| 9 | New operational models had no migration. | Added `alembic/versions/7d2e4f6a8b10_phase2d_operations_tables.py` for `otp_verifications`, `complaints`, `expenses`, `staff`. | `alembic upgrade head` on `pg_management_test`; schema inspection |
| 10 | PostgreSQL test suite hardcoded an obsolete Alembic revision, the wrong database name, and left ledger rows behind during concurrency cleanup. | Updated revision assertions to the new head, asserted `pg_management_test`, and rewrote cleanup in dependency order. Rewrote the legacy overpayment race to use committed fixtures with guaranteed cleanup. | `pytest tests_postgres` (49 passed) |

---

## 4. Migration Status

- Current head: **`7d2e4f6a8b10`** (`phase2d_operations_tables`, revises `6cb475ecad6d`).
- Applied on the confirmed test database: `alembic current` → `7d2e4f6a8b10 (head)`.
- Verified tables created: `otp_verifications`, `complaints`, `expenses`, `staff`.
- `pg_management` remains untouched; production rollout is a manual step.

---

## 5. Test Results

| Suite | Command | Result |
|---|---|---|
| SQLite unit/API suite | `python -m pytest -q` | **70 passed**, 12 warnings, 31.40s |
| PostgreSQL integration suite | `DATABASE_URL=…_test python -m pytest tests_postgres -q` | **49 passed**, 1 warning, 16.83s |
| Bytecode compilation | `python -m compileall -q app` | Passed |

### PostgreSQL concurrency evidence

- **Payment race:** two threads paid ₹6,000 against a ₹10,000 invoice → one `200`, one `409`; final `paid_amount=6000.00`, `balance_amount=4000.00`, `status=PARTIALLY_PAID`, exactly one payment row.
- **Bed allocation race:** two threads checked in different residents onto the same bed → one `200`, one `409`; bed `OCCUPIED`, exactly one `ACTIVE` resident on the bed.
- Result marker: `postgres_concurrency_check=PASS`.

The new SQLite tests live in `tests/test_final_gap_audit.py` (10 focused tests). The PostgreSQL suite also verifies composite foreign keys, unique billing constraints, refunds, and RBAC scoping.

---

## 6. Remaining Manual Configuration

1. **Database URL** — set a correctly URL-encoded `DATABASE_URL` for the target environment (a literal `@` in the password must be `%40`).
2. **JWT secret** — replace the placeholder `SECRET_KEY` with a strong 32+ character secret.
3. **SMTP / OTP delivery** — set `EMAIL_ENABLED=true`, `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD`, and `EMAIL_FROM`. Values are documented in `.env.example`. Live delivery is **not** verified because no SMTP credentials were available; registration remains functional and reports `email_sent=false` while disabled.
4. **CORS** — restrict `CORS_ORIGINS` to the actual web origins before production.
5. **Production migration** — after confirming the target database name, run `alembic upgrade head` to apply `7d2e4f6a8b10`.

---

## 7. Known Limitations / Decisions

- SMTP delivery was implemented but not exercised against a live mail server; tests assert only truthful reporting, not external delivery.
- Receipts are standards-compliant text PDFs generated without a third-party PDF dependency.
- Dashboard revenue growth returns `0.0` when the previous month has no revenue, avoiding division by zero; `revenue_this_month` remains exact.
- Partial payments leave invoices `PARTIALLY_PAID`; only a zero balance marks `PAID`.
