# PG Management System — Comprehensive Backend & Architecture Audit Report

**Date:** October 30, 2026  
**Auditor:** Backend & Database Architecture Team  
**Project Location:** `D:\PG_Management\pg-management-system\backend`  
**API Prefix:** `/api/v1`  
**Framework Stack:** FastAPI, Python 3.12, SQLAlchemy 2.0, PostgreSQL 18.6, Alembic, Pydantic V2  

---

## 1. Executive Architecture Summary

An exhaustive structural inspection of the PG Management System backend was performed across all controllers, data access layers, database models, schemas, background tasks, and migration tracks. 

The application follows a modular Clean Architecture pattern:
- `app/api/v1/endpoints/`: HTTP route handlers and parameter validation.
- `app/models/`: SQLAlchemy 2.x declarative models inheriting from `Base`, `UUIDMixin`, and `TimestampMixin`.
- `app/schemas/`: Pydantic V2 request and response contracts enforcing strict types.
- `app/services/`: Core domain business logic, cryptographic signing, settlement workflows, and notifications.
- `app/repositories/`: Query encapsulation and data persistence operations.
- `app/integrations/`: Gateway abstractions (Razorpay, Direct UPI, WhatsApp Cloud API, FCM push).
- `app/core/`: Configuration, RBAC authorization matrices, security token utilities, and exceptions.
- `migrations/`: Alembic database version control and DDL version tracking.

---

## 2. Inventory of Existing API Endpoints

The backend currently registers 50+ route endpoints grouped under `/api/v1`:

### 2.1 Authentication & Profile (`/api/v1/auth`)
- `POST /auth/login`: Issues JWT access and refresh tokens.
- `POST /auth/refresh`: Rotates refresh tokens and issues fresh access tokens.
- `POST /auth/register/resident`: Self-registration for residents with mobile OTP verification initiation.
- `POST /auth/resident/verify-otp`: Confirms 6-digit OTP code, transitioning resident to `PENDING_APPROVAL`.
- `POST /auth/resident/resend-otp`: Rate-limited OTP resend with 60-second cooldown and attempt caps.
- `GET /auth/me`: Retrieves current authenticated user context and granted roles.

### 2.2 Properties, Rooms & Beds (`/api/v1/properties`, `/rooms`, `/beds`)
- `GET /properties`, `POST /properties`, `GET /properties/{id}`, `PUT /properties/{id}`: Property CRUD with company scoping.
- `GET /rooms`, `POST /rooms`, `GET /rooms/{id}`, `PUT /rooms/{id}`: Room inventory management.
- `GET /beds`, `POST /beds`, `GET /beds/{id}`, `PUT /beds/{id}`: Bed allocation and status tracking (`AVAILABLE`, `OCCUPIED`, `MAINTENANCE`).

### 2.3 Resident Management (`/api/v1/residents`)
- `GET /residents/me`: Resident profile, room/bed details, rent, and stay summary.
- `GET /residents`: Property-scoped resident directory with status filters.
- `GET /residents/pending-approvals`: Administrative queue of self-registered residents awaiting approval.
- `POST /residents/{id}/approve`: Approves registration, assigns room and bed with concurrency locks (`SELECT ... FOR UPDATE`), and activates account.
- `POST /residents/{id}/reject`: Rejects registration and records audit reason.

### 2.4 Invoice Management (`/api/v1/invoices`)
- `POST /invoices`: Administrative generation of rent/utility charges with billing cycle uniqueness constraint (`uq_resident_invoice_cycle`).
- `GET /invoices/my`: Resident list of outstanding and historical invoices.
- `GET /invoices/{id}`: Itemized invoice details, payment records, remaining balances, and receipts.
- `GET /invoices`: Property-level invoice listing with due date ordering.

### 2.5 Payment Management (`/api/v1/payments`)
- `POST /payments/requests`: Initiates online payment order with 15-minute balance reservation and idempotency locks.
- `GET /payments/{id}/status`: Authoritative status query.
- `POST /payments/verify`: Verifies gateway signature and reconciles settlement.
- `GET /payments/my`: Resident payment history.
- `GET /payments`: Administrative payment ledger with pagination.
- `POST /payments/links`: Generates opaque payment links for invoices.
- `GET /payments/links/{token}/checkout`: Public checkout presentation query.
- `POST /payments/links/{id}/whatsapp`: Dispatches payment link via WhatsApp.
- `POST /payments/webhook/razorpay`: Razorpay webhook receiver with HMAC signature verification.
- `POST /payments/upi/initiate`: Direct UPI deep link generation (GPay, PhonePe) with fixed VPA and MCC.
- `POST /payments/upi/{id}/return`: Fail-closed client return (`PENDING_VERIFICATION`).
- `POST /payments/upi/{id}/cancel`: Cancellation of unverified payments.
- `GET /payments/upi/{id}/status`: Authoritative status query for UPI payments.
- `POST /payments/upi/{id}/verify`: Client inquiry query.
- `POST /payments/upi/{id}/admin-settle`: Authoritative property manager statement reconciliation.
- `POST /payments/upi/webhook/bank`: HMAC-SHA256 authenticated direct bank webhook.

### 2.6 Digital Receipts (`/api/v1/receipts`)
- `GET /receipts/my`: Resident digital receipts list.
- `GET /receipts/{id}`: Authoritative receipt detail view.

### 2.7 Operations & Support
- `/complaints`: Resident ticketing and maintenance workflow.
- `/expenses`: Property expense tracking.
- `/staff`: Property staff management.
- `/notices`: Announcements and circulars.
- `/leads`: Inquiries and prospective resident tracking.
- `/audit-logs`: Immutable administrative audit logs.
- `/reports`: Occupancy and revenue analytics.

---

## 3. Inventory of SQLAlchemy Models

All models reside in `app/models/` and bind to declarative `Base`:

| Model Name | Table Name | Key Attributes | Relationships |
| :--- | :--- | :--- | :--- |
| `User` | `users` | `id`, `company_id`, `role_id`, `email`, `phone`, `full_name`, `password_hash`, `approval_status`, `is_active` | `role`, `company`, `resident`, `property_access` |
| `Role` | `roles` | `id`, `name`, `display_name`, `permissions` (JSON) | `users` |
| `UserPropertyAccess` | `user_property_access` | `user_id`, `property_id` | `user`, `property` |
| `Company` | `companies` | `id`, `name`, `code`, `email`, `phone`, `is_active` | `properties`, `users` |
| `Property` | `properties` | `id`, `company_id`, `name`, `code`, `address_line1`, `city` | `company`, `rooms`, `residents` |
| `Room` | `rooms` | `id`, `property_id`, `room_number`, `floor_number`, `room_type` | `property`, `beds` |
| `Bed` | `beds` | `id`, `room_id`, `bed_number`, `status` (`AVAILABLE`, `OCCUPIED`, `MAINTENANCE`) | `room`, `residents` |
| `Resident` | `residents` | `id`, `user_id`, `property_id`, `room_id`, `bed_id`, `monthly_rent`, `security_deposit`, `status` | `user`, `property`, `room`, `bed`, `invoices`, `payments` |
| `Invoice` | `invoices` | `id`, `property_id`, `resident_id`, `invoice_number`, `billing_month`, `invoice_type`, `amount`, `paid_amount`, `due_date`, `status` | `resident`, `payments` |
| `Payment` | `payments` | `id`, `property_id`, `invoice_id`, `resident_id`, `payment_number`, `amount`, `payment_mode`, `gateway_order_id`, `gateway_payment_id`, `status` | `invoice`, `resident` |
| `Receipt` | `receipts` | `id`, `payment_id`, `invoice_id`, `receipt_number`, `amount`, `issued_at`, `whatsapp_status` | `payment_id` (FK), `invoice_id` (FK) |
| `PaymentLink` | `payment_links` | `id`, `payment_id`, `invoice_id`, `resident_id`, `token_hash`, `expires_at`, `is_revoked` | `payment`, `invoice` |
| `ProcessedWebhookEvent`| `processed_webhook_events` | `id`, `provider`, `event_id`, `event_type`, `status` | Global deduplication log |
| `DeviceToken` | `device_tokens` | `id`, `user_id`, `fcm_token`, `device_type`, `is_active` | `user` |
| `OtpVerification` | `otp_verifications` | `id`, `phone`, `otp_hash`, `purpose`, `expires_at`, `attempts` | Independent phone verification |

---

## 4. Gaps and Incomplete Functionality Identified

### Gap 1: Payment Gateway MOCK/DEMO Mode for Local Testing
- **Observation:** `app/integrations/payment_gateway.py` strictly instantiated `RazorpayGateway` requiring valid `key_id` and `key_secret`. When running locally without paid Razorpay credentials, `POST /api/v1/payments/requests` raised HTTP 503 Service Unavailable ("Online payment gateway is not configured").
- **Requirement:** Implement a complete `MockPaymentGateway` adhering to `PaymentGatewayInterface` that generates simulated orders (`order_mock_...`), verifies signatures deterministically, and allows local developers and automated tests to execute full payment flows without external gateway accounts.

### Gap 2: Manual Payment Recording (Cash / Cheque / Bank Transfer)
- **Observation:** Property managers and staff frequently receive rent via cash, bank transfer, or card POS terminal at the front desk. While database columns and enums supported `CASH` and `BANK_TRANSFER`, no API endpoint existed for staff to manually record cash payments and issue an immediate receipt.
- **Requirement:** Implement `POST /api/v1/payments/manual` with strict RBAC (`SUPER_ADMIN`, `PROPERTY_MANAGER`, `STAFF`), property validation, invoice balance check, row locks (`with_for_update`), and automatic receipt generation.

### Gap 3: Digital Receipt PDF Generation & Download
- **Observation:** Receipts existed as database records and JSON API responses, but residents and managers had no API endpoint to download standard-compliant PDF receipts.
- **Requirement:** Implement dependency-free PDF generation in `app/services/pdf_service.py` and expose `GET /api/v1/receipts/{id}/pdf` and `GET /api/v1/invoices/{id}/pdf` returning `application/pdf` streams.

### Gap 4: Resident Checkout and Financial Settlement Workflow
- **Observation:** Resident registration and approval were implemented, but there was no endpoint or business workflow for resident check-out, deposit refund calculation, dues settlement, and bed release.
- **Requirement:** Implement `POST /api/v1/residents/{id}/checkout` enforcing financial checks (unpaid invoices must be settled or deducted from deposit), updating resident status to `CHECKED_OUT`, and releasing the bed to `AVAILABLE` status.

### Gap 5: Explicit ORM Relationships on `Receipt`
- **Observation:** `Receipt` model held `payment_id` and `invoice_id` foreign keys, but lacked SQLAlchemy `relationship("Payment")` and `relationship("Invoice")`, complicating eager-loaded receipt exports.
- **Requirement:** Add explicit relationships linking `Receipt` to `Payment` and `Invoice`.

---

## 5. Security & RBAC Evaluation

- **Role Matrix:**
  - `SUPER_ADMIN`: Cross-property access across the company.
  - `PROPERTY_MANAGER`: Restricted to properties assigned via `user_property_access`.
  - `STAFF`: Operational access limited to permitted functions.
  - `RESIDENT`: Read-only access to their own profile, invoices, payments, and receipts.
- **Row-Level Concurrency:** Multi-threaded double-settlement protection validated using PostgreSQL `SELECT ... FOR UPDATE` row locks.
- **Fail-Closed Banking Boundary:** Client callbacks and screenshots never mark payments `PAID`.

---

## 6. Audit Verdict

The backend has a solid architectural foundation. Implementing the MOCK payment gateway, manual cash settlement endpoint, downloadable PDF receipt endpoints, resident checkout settlement, and Alembic migration reconciliation will make the payment module 100% production-ready and fully testable in Swagger UI.
