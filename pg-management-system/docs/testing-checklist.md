# PG Management System — Testing & QA Checklist

## 1. System Health & Infrastructure
- [ ] Database connection probe succeeds (`/api/v1/health`).
- [ ] PostgreSQL connection pool re-connects after transient interruptions (`pool_pre_ping=True`).
- [ ] CORS headers allow configured Flutter Web dev origins (`localhost:8080`, `localhost:3000`).

## 2. Authentication & Session Security
- [ ] Super Admin can log in using either email or mobile number with valid password.
- [ ] Property Manager can log in using credentials on Admin Web and Admin Mobile.
- [ ] Staff / Warden can log in on Admin Mobile.
- [ ] Resident can log in on Resident Android app.
- [ ] Resident is rejected with `403 Forbidden` if attempting to log in to `admin_web` or `admin_mobile`.
- [ ] Admin/Staff is rejected with `403 Forbidden` if attempting to log in to `resident_mobile`.
- [ ] Invalid passwords return `401 Unauthorized`.
- [ ] Inactive accounts are blocked from generating tokens.
- [ ] Refresh token flow issues a new valid access token.
- [ ] Logout revokes the refresh token; subsequent refresh attempts return `401 Unauthorized`.
- [ ] Password change invalidates all existing refresh tokens.

## 3. Property Scoping & Data Isolation
- [ ] Super Admin sees all 5–6 PG properties in portfolio.
- [ ] Property Manager sees only explicitly assigned properties.
- [ ] Staff sees only assigned properties.
- [ ] Attempting to access an unassigned property ID returns `403 Forbidden`.
- [ ] Residents can never access another resident's profile, KYC documents, or invoice ledger.

## 4. Bed Allocation & Concurrency (Phase 2)
- [ ] A bed cannot be assigned to more than one active resident simultaneously.
- [ ] Concurrent allocation requests for the same bed result in exactly one successful assignment and a clean conflict error (`409 Conflict`) for the other.
- [ ] Checkout settlement atomically updates resident status, releases the bed to `AVAILABLE`, and records settlement ledger.

## 5. Billing, Webhooks & Financial Integrity (Phase 3)
- [ ] Generating monthly invoices is repeat-safe (unique index on `resident_id + billing_month + invoice_type`).
- [ ] Payment gateway webhooks verify SHA256 HMAC signature before executing state changes.
- [ ] Duplicate webhook deliveries do not credit invoice balance more than once (idempotent processing).
- [ ] Money values use integer paise or fixed-precision decimals; floating-point math is strictly forbidden.
- [ ] Financial corrections use adjustment invoices or refunds rather than silent row deletions.

## 6. Audit & KYC Compliance
- [ ] KYC document links are private and expire within short timeframes (e.g., 15 minutes).
- [ ] Aadhaar and PAN numbers are masked (`XXXX-XXXX-1234`) in standard responses and logs.
- [ ] Sensitive actions (logins, rent modifications, refunds, bed allocations, KYC approvals) record immutable audit entries in `audit_logs`.
