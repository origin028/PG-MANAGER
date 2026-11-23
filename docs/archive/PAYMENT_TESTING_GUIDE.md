# PG Management System — Verified Payment Testing Guide

**Document:** `PAYMENT_TESTING_GUIDE.md`  
**Target Environment:** Local Development & Test Database  
**Verified Active Database:** PostgreSQL 18.6 `pg_management_test` (Revision: `b2c3d4e5f6a7`)  
**Production Live Database:** `pg_management` (Preserved Untouched at Revision `6cb475ecad6d`)  
**Backend Framework:** FastAPI, Python 3.12, SQLAlchemy 2.0, Psycopg 3  
**Active Swagger URL:** [http://127.0.0.1:8010/docs](http://127.0.0.1:8010/docs) (or [http://127.0.0.1:8010/api/v1/docs](http://127.0.0.1:8010/api/v1/docs))  
**API Health Check:** [http://127.0.0.1:8010/api/v1/health](http://127.0.0.1:8010/api/v1/health)  

---

## 1. Verified PostgreSQL Table Architecture

The test database `pg_management_test` contains all **22 public tables** fully reconciled with the modern FastAPI backend:

| Required Table | Verification Status | Primary Foreign Keys / Constraints |
|---|---|---|
| **`receipts`** | **VERIFIED PRESENT** | `payment_id` (FK $\rightarrow$ `payments.id`, UNIQUE), `invoice_id` (FK $\rightarrow$ `invoices.id`), `receipt_number` (UNIQUE) |
| **`payment_reservations`** | **VERIFIED PRESENT** | `invoice_id` (FK $\rightarrow$ `invoices.id`), `resident_id`, `payment_id`, `idempotency_key` (UNIQUE) |
| **`processed_webhook_events`** | **VERIFIED PRESENT** | `event_id` (UNIQUE), `provider`, `event_type`, `status` |
| **`payment_links`** | **VERIFIED PRESENT** | `payment_id` (FK $\rightarrow$ `payments.id`), `invoice_id`, `resident_id`, `token_hash` (UNIQUE) |
| **`payments`** | **VERIFIED RECONCILED** | `payment_mode`, `idempotency_key`, `reservation_expires_at`, `gateway_order_id`, `gateway_payment_id`, `uq_payment_invoice_idempotency` |
| **`invoices`** | **VERIFIED RECONCILED** | `amount` (NUMERIC 10,2), `paid_amount`, `uq_resident_invoice_cycle` (`resident_id`, `billing_month`, `invoice_type`) |
| **`users`** | **VERIFIED RECONCILED** | `approval_status` (DEFAULT `'APPROVED'`), `email`, `phone`, `role_id` |

---

## 2. Server Startup Commands

### Step 1: Open PowerShell and Navigate to the Backend
```powershell
Set-Location D:\PG_Management\pg-management-system\backend
```

### Step 2: Start the FastAPI Server on Port 8010
```powershell
D:\PG_Management\.venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8010 --reload
```

*Expected Terminal Output:*
```text
INFO:     Started server process [PID]
INFO:     Waiting for application startup.
2026-10-30 16:14:00,897 - pg_management - INFO - Starting PG Management System API v1.0.0 [development]
INFO:     Application startup complete.
INFO:     Uvicorn running on http://127.0.0.1:8010 (Press CTRL+C to quit)
```

### Step 3: Verify Health in PowerShell
```powershell
curl.exe -s http://127.0.0.1:8010/api/v1/health
```
*Expected JSON Output:*
```json
{
  "success": true,
  "message": "System health status.",
  "data": {
    "status": "online",
    "database": "healthy",
    "environment": "development",
    "version": "1.0.0"
  }
}
```

---

## 3. Swagger UI Interactive Testing

Open [http://127.0.0.1:8010/docs](http://127.0.0.1:8010/docs) in your browser.

### Authentication (Bearer Token)
To test administrative and resident endpoints in Swagger:
1. In Swagger UI, expand **`POST /api/v1/auth/login`**.
2. Click **Try it out** and enter:
   ```json
   {
     "identifier": "admin@originpg.com",
     "password": "Admin@123456",
     "client_type": "admin_web"
   }
   ```
3. Click **Execute** (`HTTP 200 OK`).
4. Copy the `access_token` from the response.
5. Click the green **Authorize** button at the top of Swagger UI and enter `Bearer <your_token>`.

---

## 4. End-to-End Payment Scenarios

### Scenario A: Instant Demo Online Payment
Use this to test the complete online payment flow without external gateway credentials.

- **Endpoint:** `POST /api/v1/payments/demo/pay`
- **Request Headers:**
  - `Content-Type: application/json`
  - `Authorization: Bearer <TOKEN>`
- **Request Body:**
```json
{
  "invoice_id": "<INVOICE_UUID>",
  "amount": 7500.00,
  "payment_mode": "DEMO_ONLINE",
  "notes": "Testing instant demo settlement"
}
```
- **Expected Response (`HTTP 200 OK`):**
```json
{
  "success": true,
  "message": "Demo payment processed and receipt generated successfully.",
  "data": {
    "payment_id": "8ef1eb41-7f51-4d21-9185-aeab035f60cc",
    "payment_number": "PAY-DEMO-6F2475C9623F43",
    "invoice_id": "<INVOICE_UUID>",
    "amount": 7500.0,
    "status": "PAID",
    "paid_at": "2026-10-30T16:18:30.139119+05:30",
    "receipt_id": "121ead95-5740-49b7-8b9e-dff2898965b6",
    "receipt_number": "RCT-DEMO-20261030-293954FF",
    "invoice_status": "PAID",
    "paid_amount": 7500.0,
    "remaining_balance": 0.0
  }
}
```

---

### Scenario B: Front-Desk Manual Cash Payment
Use this when front-desk staff collects physical cash or direct counter UPI.

- **Endpoint:** `POST /api/v1/payments/manual`
- **Request Body:**
```json
{
  "invoice_id": "<INVOICE_UUID>",
  "amount": 8000.00,
  "payment_method": "CASH",
  "notes": "Received cash at front desk"
}
```
- **Expected Response (`HTTP 201 Created`):**
```json
{
  "success": true,
  "message": "Manual payment recorded and receipt issued successfully.",
  "data": {
    "payment_id": "...",
    "receipt_id": "...",
    "receipt_number": "RCT-MANUAL-...",
    "invoice_status": "PAID",
    "remaining_balance": 0.0
  }
}
```

---

### Scenario C: Download Branded PDF Receipt
Download the clean binary PDF 1.4 receipt generated with zero external binary dependencies.

- **Endpoint:** `GET /api/v1/receipts/{receipt_id}/pdf`
- **PowerShell Download Command:**
```powershell
curl.exe -H "Authorization: Bearer <TOKEN>" -o receipt.pdf "http://127.0.0.1:8010/api/v1/receipts/<receipt_id>/pdf"
```
- **Verification:**
```powershell
Get-Item .\receipt.pdf | Select-Object Name, Length
```
The file starts with `%PDF-1.4` and includes invoice number, resident name, amount paid, and transaction reference.

---

### Scenario D: Duplicate Payment Prevention
Attempting to pay an already settled invoice returns `HTTP 409 Conflict`:

- **Request Body:** Same payload as Scenario A
- **Expected Response (`HTTP 409 Conflict`):**
```json
{
  "success": false,
  "error": {
    "code": "CONFLICT",
    "message": "Invoice is not eligible for payment (current status: 'PAID').",
    "details": null
  }
}
```

---

### Scenario E: Resident Checkout & Deposit Settlement
When a resident checks out:
- Checks unpaid invoices.
- Deducts unpaid balances from security deposit if requested.
- Releases bed status from `OCCUPIED` to `AVAILABLE`.
- Updates resident status to `CHECKED_OUT`.

- **Endpoint:** `POST /api/v1/residents/{resident_id}/checkout`
- **Request Body:**
```json
{
  "deduct_from_deposit": true,
  "notes": "Full settlement on departure"
}
```
- **Expected Response (`HTTP 200 OK`):**
```json
{
  "success": true,
  "message": "Resident checked out successfully.",
  "data": {
    "resident_id": "<RESIDENT_UUID>",
    "resident_status": "CHECKED_OUT",
    "bed_released": true,
    "unpaid_invoices_settled": 0,
    "deposit_deduction": 0.0,
    "deposit_refund": 15000.0,
    "receipt_id": "<RECEIPT_UUID>"
  }
}
```

---

## 5. Actual PostgreSQL Verification Results

The test execution script (`scratch/execute_demo_payment_workflow.py`) verified against live PostgreSQL:

1. **Precondition:** Programmatic check confirmed `current_database() = 'pg_management_test'`.
2. **Setup:** Created dedicated resident user and invoice `INV-TEST-EE310321` for INR 7500.00.
3. **Execution:** `POST /api/v1/payments/demo/pay` returned `HTTP 200 OK` in 27ms.
4. **PostgreSQL Invoices Table:** `status='PAID'`, `paid_amount=7500.00`, `remaining_balance=0.00`.
5. **PostgreSQL Payments Table:** Recorded `payment_number='PAY-DEMO-6F2475C9623F43'`, `status='PAID'`.
6. **PostgreSQL Receipts Table:** Persisted `receipt_number='RCT-DEMO-20261030-293954FF'`, `amount=7500.00`.
7. **PDF Stream:** Downloaded 2,181 bytes binary stream starting with `%PDF-1.4`.
8. **Duplicate Protection:** Immediate retry returned `HTTP 409 Conflict` rejecting duplicate submission.
9. **Production Isolation:** `pg_management` independently verified: revision `6cb475ecad6d`, 13 tables, 63 records (100% untouched).

---

## 6. Known Production Boundaries & Remaining Limitations

1. **Production Live Database Gate:**
   - Production database `pg_management` is deliberately kept at revision `6cb475ecad6d` until explicit user deployment authorization.
   - The production plan `migration_proposal_review/production_plan_v3_1/01_unified_reconcile_pg_management_v3_1.sql` contains the audited script ready for production execution.
2. **WhatsApp Cloud Notification Delivery:**
   - Receipts are issued with `whatsapp_status = 'PENDING'`. In local development, outbound WhatsApp messages remain safely enqueued until live Meta Cloud API access tokens are configured.
3. **Direct UPI Production Flow:**
   - UPI VPA `9886699258-3@ybl`, Payee `SMART GROUP PG'S`, MCC `5411` are hardcoded in the payment configuration and reserved for real UPI QR transactions.
