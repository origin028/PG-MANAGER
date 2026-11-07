# PG Management — Decision Record: User Approval Status Logic

**Document:** `migration_proposal_review/production_plan_v3_1/04_approval_status_decision_v3_1.md`  
**Feature:** Multi-Tier Account Approval & Resident Onboarding Authorization  
**Live Target:** `pg_management.users`  
**Decision:** **ADMINS/STAFF 'APPROVED', UNALLOCATED RESIDENT 'PENDING_APPROVAL'**  
**Status:** ARCHITECTURAL DECISION RECORD & ACCESS CONTROL AUDIT  

---

## 1. Problem Statement & Background

The live database `pg_management` contains 4 pre-seeded user accounts:
1. `admin@originpg.com` (Role: `SUPER_ADMIN`, Name: `Rajesh Kumar`)
2. `manager@originpg.com` (Role: `PROPERTY_MANAGER`, Name: `Suresh Nair`)
3. `staff@originpg.com` (Role: `STAFF`, Name: `Anil Sharma`)
4. `resident@originpg.com` (Role: `RESIDENT`, Name: `Rohan Deshmukh`)

However, the `residents` table in `pg_management` currently contains **0 records**. 
Although `resident@originpg.com` was seeded into the `users` table with the `RESIDENT` role, no corresponding `Resident` profile was ever created, and no room or bed was allocated to this user.

In active Alembic migration `b2c3d4e5f6a7_add_resident_approval_and_otp.py`, the system introduced `users.approval_status` (`APPROVED`, `PENDING_APPROVAL`, `REJECTED`) to gate resident mobile onboarding.

This decision record defines the exact SQL and lifecycle behavior for all user categories.

---

## 2. Multi-Tier Approval State Analysis

### 2.1 Administrative Accounts (SUPER_ADMIN, PROPERTY_MANAGER, STAFF)
- **Role & Scope:** Platform operations, property oversight, room/bed configuration, invoice settlement.
- **Resident Profile Requirement:** None. Administrative staff are not tenants and do not occupy beds.
- **Intended State:** **`approval_status = 'APPROVED'`**
- **Justification:** Administrative users require active approval status to authenticate, generate JWT access tokens, and access operational endpoints.

### 2.2 Unallocated Seed Resident (`resident@originpg.com`)
- **Role & Scope:** Resident mobile tenant.
- **Current Data State:** `users` row exists, but **0 rows exist in `residents` table**. No property assignment, room assignment, or bed assignment exists.
- **Intended State:** **`approval_status = 'PENDING_APPROVAL'`**
- **Justification:**
  1. A resident who has not been approved and assigned a room/bed is, by business definition, in a pending onboarding state.
  2. Marking the account `PENDING_APPROVAL` aligns database state with business reality.
  3. Fail-Closed Security: Even if `approval_status` were `APPROVED`, all resident-scoped endpoints (`/residents/me`, `/invoices/my-invoices`) query `Resident.user_id == current_user.id` and immediately return HTTP 403 `PermissionDeniedError("Resident profile not found or inactive")`. Marking the user `PENDING_APPROVAL` provides defense-in-depth at the authentication level as well.

### 2.3 Newly Registered Residents
- **Self-Registration Flow:** When a prospect self-registers via `POST /api/v1/auth/register-resident` ([app/api/v1/endpoints/auth.py#L223](file:///D:/PG_Management/pg-management-system/backend/app/api/v1/endpoints/auth.py#L223)):
  - Creates `User` with `approval_status = "PENDING_APPROVAL"`.
  - Creates `Resident` with `status = "PENDING_APPROVAL"`, `room_id = None`, `bed_id = None`.
- **Approval Flow:** Property Manager reviews `GET /api/v1/residents/pending-approvals` and calls `POST /api/v1/residents/{id}/approve` with room/bed selection:
  - Updates `user.approval_status = "APPROVED"`.
  - Updates `resident.status = "ACTIVE"`, assigning `room_id` and `bed_id`.

---

## 3. Exact V3.1 Migration SQL Implementation

To implement this logic transparently without silent side effects, [`01_unified_reconcile_pg_management_v3_1.sql`](file:///D:/PG_Management/migration_proposal_review/production_plan_v3_1/01_unified_reconcile_pg_management_v3_1.sql) executes the following two-step sequence:

```sql
-- Step 2.1: Add approval_status column with default 'APPROVED' for administrative continuity
ALTER TABLE users ADD COLUMN IF NOT EXISTS approval_status VARCHAR(50) DEFAULT 'APPROVED' NOT NULL;
CREATE INDEX IF NOT EXISTS ix_users_approval_status ON users (approval_status);

-- Step 2.2: Specifically update the unallocated resident seed account to PENDING_APPROVAL
-- Only targets users with role 'RESIDENT' who have no corresponding row in residents table
UPDATE users 
SET approval_status = 'PENDING_APPROVAL' 
WHERE id IN (
    SELECT u.id 
    FROM users u 
    JOIN roles r ON u.role_id = r.id 
    LEFT JOIN residents res ON u.id = res.user_id 
    WHERE r.name = 'RESIDENT' AND res.id IS NULL
);
```

### Post-Migration Assertion Verification (Section 10)
```sql
-- Assert user approval counts: exactly 3 APPROVED (admins/staff) and 1 PENDING_APPROVAL (seed resident)
SELECT count(*) INTO v_appr_cnt FROM users WHERE approval_status = 'APPROVED';
IF v_appr_cnt != 3 THEN 
    RAISE EXCEPTION 'POSTCONDITION FAILED: Expected 3 APPROVED users (admins/staff), found %', v_appr_cnt; 
END IF;

SELECT count(*) INTO v_pend_cnt FROM users WHERE approval_status = 'PENDING_APPROVAL';
IF v_pend_cnt != 1 THEN 
    RAISE EXCEPTION 'POSTCONDITION FAILED: Expected 1 PENDING_APPROVAL user (seed resident), found %', v_pend_cnt; 
END IF;
```

---

## 4. Empirical Sandbox Verification

In `pg_reconcile_v3_1_sandbox_test`, this migration was executed and verified:

```
approval_status  | user_count 
------------------+------------
 APPROVED         |          3
 PENDING_APPROVAL |          1
(2 rows)

         email         | approval_status  |    role_name     
-----------------------+------------------+------------------
 manager@originpg.com  | APPROVED         | PROPERTY_MANAGER
 resident@originpg.com | PENDING_APPROVAL | RESIDENT
 staff@originpg.com    | APPROVED         | STAFF
 admin@originpg.com    | APPROVED         | SUPER_ADMIN
(4 rows)
```

Both postcondition checks passed with Exit Code 0.
