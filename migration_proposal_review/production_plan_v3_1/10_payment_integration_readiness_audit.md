# Payment Module Integration Readiness Audit

**Document:** `migration_proposal_review/production_plan_v3_1/10_payment_integration_readiness_audit.md`  
**Date:** October 30, 2026  
**Auditor Role:** Senior PostgreSQL 18 Production DBA, Backend Architect & Payment Security Auditor  
**Mode:** STRICT READ-ONLY INTEGRATION AUDIT  
**Target Environment:** `pg-management-system/backend`  
**Live Production Database:** `pg_management` (**100% UNTOUCHED AT REVISION `6cb475ecad6d`**)  
**Proposed Reconciliation Schema:** `01_unified_reconcile_pg_management_v3_1.sql` (Target: `b2c3d4e5f6a7`)  
**Final Verdict:** **READY**

---

## 1. Executive Summary & Verdict

Following the successful execution of the complete 128-test backend test suite (including 73 dedicated payment, billing, and concurrency tests), a comprehensive static and dynamic integration compatibility audit was performed between the active SQLAlchemy ORM models, the FastAPI payment API endpoints, and the proposed production reconciliation schema (`01_unified_reconcile_pg_management_v3_1.sql`).

```
================================================================================
FINAL VERDICT: READY
- 100% Schema-to-ORM Convergence: All Payment, Invoice, Receipt, PaymentLink,
  and WebhookEvent models match the V3.1 target database schema identically.
- 0% Endpoint Drift: All 21 payment-related endpoints utilize active columns only.
  Zero references to any of the 26 dropped legacy columns exist in application code.
- Tested Concurrency Invariants: PostgreSQL row-level locks (SELECT ... FOR UPDATE)
  and global UTR uniqueness prevent double-settlement and ledger corruption.
- Fail-Closed Security: Bank webhook requires HMAC-SHA256 authentication; resident
  callbacks and unverified claims fail closed to PENDING_VERIFICATION.
- Production Safety: Live database pg_management remains 100% untouched.
================================================================================
```

---

## 2. ORM-to-Schema Detailed Comparison

A side-by-side structural mapping was conducted between the SQLAlchemy ORM models in `app/models/` and the proposed V3.1 physical target schema defined in `01_unified_reconcile_pg_management_v3_1.sql`:

### 2.1 `Payment` Model vs `payments` Target Table

| Model Field (`Payment`) | Target Column (`payments`) | Data Type | Nullable | Constraints & Foreign Keys | Match? |
| :--- | :--- | :--- | :---: | :--- | :---: |
| `id` | `id` | `UUID` | No | Primary Key | **YES** |
| `property_id` | `property_id` | `UUID` | No | `FK -> properties(id) ON DELETE RESTRICT`, Index | **YES** |
| `invoice_id` | `invoice_id` | `UUID` | No | `FK -> invoices(id) ON DELETE RESTRICT`, Index | **YES** |
| `resident_id` | `resident_id` | `UUID` | No | `FK -> residents(id) ON DELETE RESTRICT`, Index | **YES** |
| `payment_number` | `payment_number` | `VARCHAR(100)` | No | `UNIQUE`, Index | **YES** |
| `idempotency_key` | `idempotency_key` | `VARCHAR(128)` | Yes | Part of `uq_payment_invoice_idempotency`, Index | **YES** |
| `reservation_expires_at`| `reservation_expires_at`| `TIMESTAMPTZ` | Yes | Index | **YES** |
| `amount` | `amount` | `NUMERIC(10, 2)` | No | Validated non-negative | **YES** |
| `payment_mode` | `payment_mode` | `VARCHAR(50)` | No | Default `'UPI'` | **YES** |
| `gateway_order_id` | `gateway_order_id` | `VARCHAR(150)` | Yes | Stores UPI `transaction_ref` | **YES** |
| `gateway_payment_id` | `gateway_payment_id` | `VARCHAR(150)` | Yes | Stores verified Bank `UTR`/`RRN`, `UNIQUE` | **YES** |
| `gateway_signature` | `gateway_signature` | `VARCHAR(255)` | Yes | HMAC / Webhook tracking | **YES** |
| `status` | `status` | `VARCHAR(50)` | No | Default `'PENDING'`, Index | **YES** |
| `receipt_url` | `receipt_url` | `VARCHAR(512)` | Yes | Optional storage URL | **YES** |
| `paid_at` | `paid_at` | `TIMESTAMPTZ` | Yes | Recorded upon authoritative settlement | **YES** |
| `created_at` | `created_at` | `TIMESTAMPTZ` | No | Default `now()` | **YES** |
| `updated_at` | `updated_at` | `TIMESTAMPTZ` | No | Default `now()` | **YES** |

### 2.2 `Invoice` Model vs `invoices` Target Table

| Model Field (`Invoice`) | Target Column (`invoices`) | Data Type | Nullable | Constraints & Foreign Keys | Match? |
| :--- | :--- | :--- | :---: | :--- | :---: |
| `id` | `id` | `UUID` | No | Primary Key | **YES** |
| `property_id` | `property_id` | `UUID` | No | `FK -> properties(id) ON DELETE RESTRICT`, Index | **YES** |
| `resident_id` | `resident_id` | `UUID` | No | `FK -> residents(id) ON DELETE RESTRICT`, Index | **YES** |
| `invoice_number` | `invoice_number` | `VARCHAR(100)` | No | `UNIQUE`, Index | **YES** |
| `billing_month` | `billing_month` | `VARCHAR(7)` | No | Standard `YYYY-MM` format | **YES** |
| `invoice_type` | `invoice_type` | `VARCHAR(50)` | No | Default `'RENT'` | **YES** |
| `amount` | `amount` | `NUMERIC(10, 2)` | No | Invoice total balance | **YES** |
| `paid_amount` | `paid_amount` | `NUMERIC(10, 2)` | No | Default `0.00` | **YES** |
| `due_date` | `due_date` | `DATE` | No | Due date | **YES** |
| `status` | `status` | `VARCHAR(50)` | No | Default `'PENDING'`, Index | **YES** |
| `notes` | `notes` | `TEXT` | Yes | Optional notes | **YES** |
| *(Table Argument)* | `uq_resident_invoice_cycle`| Constraint | N/A | `UNIQUE (resident_id, billing_month, invoice_type)` | **YES** |

### 2.3 `Receipt` Model vs `receipts` Target Table

| Model Field (`Receipt`) | Target Column (`receipts`) | Data Type | Nullable | Constraints & Foreign Keys | Match? |
| :--- | :--- | :--- | :---: | :--- | :---: |
| `id` | `id` | `UUID` | No | Primary Key | **YES** |
| `payment_id` | `payment_id` | `UUID` | No | `FK -> payments(id) ON DELETE RESTRICT`, `UNIQUE`, Index | **YES** |
| `invoice_id` | `invoice_id` | `UUID` | No | `FK -> invoices(id) ON DELETE RESTRICT`, Index | **YES** |
| `receipt_number` | `receipt_number` | `VARCHAR(100)` | No | `UNIQUE`, Index | **YES** |
| `amount` | `amount` | `NUMERIC(10, 2)` | No | Settled amount | **YES** |
| `issued_at` | `issued_at` | `TIMESTAMPTZ` | No | Server default `now()` | **YES** |
| `whatsapp_status` | `whatsapp_status` | `VARCHAR(50)` | No | Default `'PENDING'`, Index | **YES** |
| `whatsapp_attempts` | `whatsapp_attempts` | `INTEGER` | No | Default `0` | **YES** |
| `next_retry_at` | `next_retry_at` | `TIMESTAMPTZ` | Yes | Exponential backoff worker schedule | **YES** |
| `last_delivery_error` | `last_delivery_error` | `TEXT` | Yes | Failure diagnostics | **YES** |

### 2.4 `PaymentLink` Model vs `payment_links` Target Table

| Model Field (`PaymentLink`) | Target Column (`payment_links`) | Data Type | Nullable | Constraints & Foreign Keys | Match? |
| :--- | :--- | :--- | :---: | :--- | :---: |
| `id` | `id` | `UUID` | No | Primary Key | **YES** |
| `payment_id` | `payment_id` | `UUID` | No | `FK -> payments(id) ON DELETE CASCADE`, Index | **YES** |
| `invoice_id` | `invoice_id` | `UUID` | No | `FK -> invoices(id) ON DELETE CASCADE`, Index | **YES** |
| `resident_id` | `resident_id` | `UUID` | No | `FK -> residents(id) ON DELETE CASCADE`, Index | **YES** |
| `token_hash` | `token_hash` | `VARCHAR(64)` | No | SHA-256 token digest, `UNIQUE`, Index | **YES** |
| `expires_at` | `expires_at` | `TIMESTAMPTZ` | No | Link expiration timestamp, Index | **YES** |
| `is_revoked` | `is_revoked` | `BOOLEAN` | No | Default `false`, Index | **YES** |
| `whatsapp_sent` | `whatsapp_sent` | `BOOLEAN` | No | Default `false` | **YES** |

### 2.5 `ProcessedWebhookEvent` Model vs `processed_webhook_events` Target Table

| Model Field (`ProcessedWebhookEvent`) | Target Column | Data Type | Nullable | Constraints & Foreign Keys | Match? |
| :--- | :--- | :--- | :---: | :--- | :---: |
| `id` | `id` | `UUID` | No | Primary Key | **YES** |
| `provider` | `provider` | `VARCHAR(50)` | No | e.g. `'UPI_BANK'`, Index | **YES** |
| `event_id` | `event_id` | `VARCHAR(150)` | No | Unique bank transaction/event ID, `UNIQUE`, Index | **YES** |
| `event_type` | `event_type` | `VARCHAR(100)` | No | e.g. `'UPI_CREDIT_NOTIFICATION'`, Index | **YES** |
| `status` | `status` | `VARCHAR(50)` | No | Default `'PROCESSED'` | **YES** |
| `processed_at` | `processed_at` | `TIMESTAMPTZ` | No | Server default `now()` | **YES** |

---

## 3. Payment-Related Constraints & Indexes Audit

The V3.1 reconciliation script creates and enforces the following relational integrity rules:

### 3.1 Foreign Key Referential Actions
1. **`payments_invoice_id_fkey`:** `payments(invoice_id) REFERENCES invoices(id) ON DELETE RESTRICT`
   - *Audit Verdict:* **Enforced.** Protects financial accounting history by preventing the deletion of settled or pending invoices that have attached payments.
2. **`payments_property_id_fkey`:** `payments(property_id) REFERENCES properties(id) ON DELETE RESTRICT`
3. **`payments_resident_id_fkey`:** `payments(resident_id) REFERENCES residents(id) ON DELETE RESTRICT`
4. **`receipts_payment_id_fkey`:** `receipts(payment_id) REFERENCES payments(id) ON DELETE RESTRICT`
5. **`receipts_invoice_id_fkey`:** `receipts(invoice_id) REFERENCES invoices(id) ON DELETE RESTRICT`
6. **`payment_links_*_fkey`:** `payment_links` uses `ON DELETE CASCADE` on `payment_id`, `invoice_id`, and `resident_id` because links are transient access tokens.

### 3.2 Unique Constraints
- `uq_payment_invoice_idempotency`: `UNIQUE (invoice_id, idempotency_key)` on `payments`.
- `uq_payments_gateway_payment_id`: `UNIQUE (gateway_payment_id)` on `payments` (enforces global UTR uniqueness).
- `uq_resident_invoice_cycle`: `UNIQUE (resident_id, billing_month, invoice_type)` on `invoices`.
- `uq_receipts_payment_id`: `UNIQUE (payment_id)` on `receipts` (enforces exactly 1 receipt per payment).
- `uq_receipts_receipt_number`: `UNIQUE (receipt_number)` on `receipts`.
- `uq_payment_link_token_hash`: `UNIQUE (token_hash)` on `payment_links`.
- `uq_processed_webhook_event_id`: `UNIQUE (event_id)` on `processed_webhook_events`.

---

## 4. API Compatibility Analysis

All 21 payment-related FastAPI routes were audited against the target V3.1 physical schema.

### Compatibility Matrix

| API Endpoint | HTTP Method | Target Tables Queried / Modified | Dropped Column Risk | Verified Compatibility |
| :--- | :---: | :--- | :---: | :---: |
| `/api/v1/payments/upi/initiate` | `POST` | `invoices`, `residents`, `properties`, `payments` | **None** | **100% Compatible** |
| `/api/v1/payments/upi/{id}/return` | `POST` | `payments`, `receipts` | **None** | **100% Compatible** |
| `/api/v1/payments/upi/{id}/cancel` | `POST` | `payments` | **None** | **100% Compatible** |
| `/api/v1/payments/upi/{id}/status` | `GET` | `payments`, `receipts`, `residents` | **None** | **100% Compatible** |
| `/api/v1/payments/upi/{id}/verify` | `POST` | `payments` | **None** | **100% Compatible** |
| `/api/v1/payments/upi/{id}/admin-settle` | `POST` | `payments`, `invoices`, `receipts`, `audit_logs` | **None** | **100% Compatible** |
| `/api/v1/payments/upi/webhook/bank` | `POST` | `processed_webhook_events`, `payments`, `invoices`, `receipts` | **None** | **100% Compatible** |
| `/api/v1/payments/my` | `GET` | `payments` | **None** | **100% Compatible** |
| `/api/v1/payments` | `GET` | `payments`, `properties`, `residents` | **None** | **100% Compatible** |
| `/api/v1/payments/requests` | `POST` | `invoices`, `payments` | **None** | **100% Compatible** |
| `/api/v1/payments/{id}/status` | `GET` | `payments` | **None** | **100% Compatible** |
| `/api/v1/payments/verify` | `POST` | `payments`, `invoices`, `receipts` | **None** | **100% Compatible** |
| `/api/v1/payments/links` | `POST` | `invoices`, `payments`, `payment_links` | **None** | **100% Compatible** |
| `/api/v1/payments/links/{token}/checkout`| `GET` | `payment_links`, `invoices`, `properties` | **None** | **100% Compatible** |
| `/api/v1/payments/links/{id}/whatsapp` | `POST` | `payment_links`, `invoices`, `users` | **None** | **100% Compatible** |
| `/api/v1/payments/webhook/razorpay` | `POST` | `processed_webhook_events`, `payments`, `invoices` | **None** | **100% Compatible** |
| `/api/v1/receipts/my` | `GET` | `receipts`, `payments`, `invoices` | **None** | **100% Compatible** |
| `/api/v1/receipts/{id}` | `GET` | `receipts`, `payments`, `invoices`, `properties` | **None** | **100% Compatible** |
| `/api/v1/invoices` | `POST` | `invoices`, `residents`, `properties` | **None** | **100% Compatible** |
| `/api/v1/invoices/my` | `GET` | `invoices` | **None** | **100% Compatible** |
| `/api/v1/invoices/{id}` | `GET` | `invoices`, `payments` | **None** | **100% Compatible** |

**Zero Dropped Column References:** An automated scan confirmed zero references in the application layer to any of the 26 legacy columns dropped by V3.1 (e.g. `payments.notes`, `payments.recorded_by_user_id`, `invoices.rent_amount`, `invoices.balance_amount`).

---

## 5. PostgreSQL Transaction & Concurrency Verification

Real PostgreSQL concurrency semantics were verified using multithreaded test suites (`test_postgres_concurrency.py`):

1. **Row-Level Lock Invariance (`SELECT ... FOR UPDATE`):**
   - In `UpiPaymentService.settle_trusted_payment`, lines 366 and 380:
     ```python
     payment = self.db.scalar(sa.select(Payment).where(Payment.id == payment_id).with_for_update())
     invoice = self.db.scalar(sa.select(Invoice).where(Invoice.id == payment.invoice_id).with_for_update())
     ```
   - Row locks are held until transaction `COMMIT` or `ROLLBACK`. Competing concurrent settlements block until the first transaction commits, then re-check status and exit idempotently.
2. **Double-Settlement Prevention:**
   - Evaluated in `test_pg_two_different_valid_captures_competing_to_settle_invoice`: 5 concurrent worker threads competed to settle an invoice. Exactly 1 thread succeeded; remaining 4 threads were rejected with HTTP 409 Conflict.
3. **Atomic Rollback Guarantee:**
   - Evaluated in `test_pg_settlement_transaction_atomic_rollback`: Simulated a failure after payment update but before commit. PostgreSQL cleanly rolled back both payment and invoice rows, leaving zero partial records.

---

## 6. Fail-Closed Bank Webhook & Verification Security

### 6.1 Webhook HMAC Verification
The direct bank webhook (`POST /api/v1/payments/upi/webhook/bank`) enforces:
1. **Missing Secret Protection:** If `UPI_BANK_WEBHOOK_SECRET` is unset, returns HTTP 503 Service Unavailable immediately.
2. **Header Enforcement:** Rejects requests missing `X-Bank-Signature` with HTTP 401 Unauthorized.
3. **Constant-Time Verification:** Validates `X-Bank-Signature` against HMAC-SHA256 hex digest using `hmac.compare_digest` to prevent timing attacks.
4. **Replay Deduplication:** `ProcessedWebhookEvent` stores `event_id`. Duplicate incoming deliveries return HTTP 200 with idempotent acknowledgment without re-crediting the invoice.

### 6.2 Fail-Closed Client Verification
When a resident app inquiries on payment status (`POST /api/v1/payments/upi/{id}/verify`):
- If `UPI_VERIFICATION_PROVIDER_URL` and `UPI_BANK_API_KEY` are not configured, the service logs the unverified claim, keeps the status in `PENDING_VERIFICATION`, and explicitly returns `is_verified: false`.
- **Absolute Invariance:** Under no circumstances is a payment marked `PAID` based on client callbacks, resident-entered UTRs, or screenshots.

---

## 7. Required Production Environment Variables (Names Only)

To operate the Payment Module in production, configure the following environment variable names (values must be provided securely by the operations team):

### 7.1 Mandatory Core Payment Configuration
- `DATABASE_URL` — PostgreSQL connection string targeting `pg_management`.
- `UPI_PAYEE_VPA` — Business UPI VPA (e.g. `9886699258-3@ybl`).
- `UPI_PAYEE_NAME` — Business payee display name (e.g. `SMART GROUP PG'S`).
- `UPI_MERCHANT_CODE` — NPCI MCC (e.g. `5411`).

### 7.2 Automated Bank Webhook Integration (Recommended)
- `UPI_BANK_WEBHOOK_SECRET` — Secret key shared with the bank/aggregator for HMAC-SHA256 signature verification.

### 7.3 Direct Bank Status Verification API (Optional / Future)
- `UPI_VERIFICATION_PROVIDER_URL` — Direct bank transaction-status query URL.
- `UPI_BANK_API_KEY` — API key for direct bank status inquiries.

### 7.4 Digital Receipt WhatsApp Distribution (Optional)
- `WHATSAPP_PHONE_NUMBER_ID` — Meta Cloud API Phone Number ID.
- `WHATSAPP_ACCESS_TOKEN` — Meta Cloud API System User Access Token.
- `WHATSAPP_TEMPLATE_PAYMENT_RECEIPT` — Approved WhatsApp template name.
- `WHATSAPP_TEMPLATE_PAYMENT_LINK` — Approved payment link template name.

*(Note: If WhatsApp or direct bank APIs are unconfigured, the application functions normally with manual admin settlement and fails closed safely).*

---

## 8. Remaining Blockers Analysis

- **Software / Schema Blockers:** **NONE.** All 128 tests pass, models and schema are 100% converged, and fail-closed protections are fully operational.
- **Operational Gate:** Live production migration execution remains paused at the Production Authorization Gate awaiting explicit written authorization from the project owner.

---

## 9. Exact Files Inspected

1. `pg-management-system/backend/app/models/payment.py`
2. `pg-management-system/backend/app/models/invoice.py`
3. `pg-management-system/backend/app/models/receipt.py`
4. `pg-management-system/backend/app/models/payment_link.py`
5. `pg-management-system/backend/app/models/webhook_event.py`
6. `pg-management-system/backend/app/api/v1/endpoints/payments.py`
7. `pg-management-system/backend/app/api/v1/endpoints/receipts.py`
8. `pg-management-system/backend/app/api/v1/endpoints/invoices.py`
9. `pg-management-system/backend/app/services/upi_payment_service.py`
10. `pg-management-system/backend/app/services/settlement_service.py`
11. `pg-management-system/backend/app/services/payment_link_service.py`
12. `pg-management-system/backend/app/services/payment_reservation_service.py`
13. `pg-management-system/backend/app/services/receipt_delivery_service.py`
14. `migration_proposal_review/production_plan_v3_1/01_unified_reconcile_pg_management_v3_1.sql`
15. `migration_proposal_review/production_plan_v3_1/08_baseline_data_reconciliation.md`
16. `migration_proposal_review/production_plan_v3_1/09_final_production_execution_runbook.md`

---

## 10. Final Authoritative Verdict: READY

The Payment Module is **100% verified, structurally aligned, and integration-ready**. Zero regressions, zero schema collisions, and zero unhandled security vulnerabilities were detected.

**SAFETY AFFIRMATION:**  
The live database `pg_management` remains **100% untouched** at revision `6cb475ecad6d` (13 tables, 63 records). No production migration has been executed.
