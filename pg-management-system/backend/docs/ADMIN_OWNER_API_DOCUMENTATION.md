# Origin PG Management System – Admin & Owner Web Panel API Documentation
**Version:** 2.0.0 | **API Prefix:** `/api/v1` | **Authentication:** Bearer JWT + 6-digit Super Key 2FA (Email SMTP)

---

## 1. Overview & Architecture
The Admin & Owner Web Panel backend provides enterprise-grade management capabilities for property owners, regional super administrators, and on-site property managers.
The system is built on **FastAPI**, **SQLAlchemy 2.x**, **PostgreSQL** (with in-memory SQLite support for tests), and **Pydantic v2 validation**.

### Key Architectural Standards
1. **Multi-Property Role Scoping**:
   - `SUPER_ADMIN` and `OWNER`: Global cross-property visibility across all properties in the company.
   - `PROPERTY_MANAGER`: Scoped strictly to assigned properties via `user_property_access`.
   - `RESIDENT`: Scoped strictly to individual resident stay records.
2. **Two-Factor Authentication (Super Key 2FA)**:
   - Administrative credentials undergo initial password verification (`POST /api/v1/auth/admin/login`).
   - A cryptographic, salted 6-digit Super Key OTP is generated with a 60-second cooldown and 10-minute TTL, dispatched via authenticated SMTP using professional SMART GROUP PG'S HTML templates.
   - Final JWT access tokens are only issued upon Super Key verification (`POST /api/v1/auth/admin/login/verify`).
3. **Financial Precision**:
   - All monetary amounts use PostgreSQL `NUMERIC(10, 2)` / Python `Decimal` to avoid floating-point rounding errors.
   - Offline collections, online gateway callbacks, and invoice balance updates are executed within atomic database transactions with row-level locking (`with_for_update()`).
4. **Audit Trail**:
   - Every administrative modification (invoice generation, offline rent collection, KYC verification, room/bed allocation, staff updates) is recorded in immutable `audit_logs`.

---

## 2. Authentication & 2FA Module

### 2.1 Admin Registration Request
- **Endpoint:** `POST /api/v1/auth/admin/register`
- **Access:** Public / Initial Admin setup
- **Request Body:**
  ```json
  {
    "full_name": "Rajesh Kumar",
    "email": "rajesh.admin@smartpg.com",
    "phone": "9876543210",
    "password": "SecurePassword@123",
    "company_name": "Smart PG Living Private Limited",
    "role": "SUPER_ADMIN"
  }
  ```
- **Response (200 OK):**
  ```json
  {
    "success": true,
    "message": "Super Key dispatched to registered email. Please verify to complete account registration.",
    "data": {
      "email": "rajesh.admin@smartpg.com",
      "masked_email": "r***n@smartpg.com",
      "cooldown_seconds": 60,
      "expires_in_minutes": 10
    }
  }
  ```

### 2.2 Admin Registration Verify
- **Endpoint:** `POST /api/v1/auth/admin/register/verify`
- **Request Body:**
  ```json
  {
    "email": "rajesh.admin@smartpg.com",
    "super_key": "489201"
  }
  ```
- **Response (201 Created):**
  ```json
  {
    "success": true,
    "message": "Admin registration verified and account activated successfully.",
    "data": {
      "access_token": "eyJhbGciOi...",
      "refresh_token": "eyJhbGciOi...",
      "token_type": "bearer",
      "user": {
        "id": "c1f7b3a2-...",
        "full_name": "Rajesh Kumar",
        "email": "rajesh.admin@smartpg.com",
        "phone": "9876543210",
        "role": "SUPER_ADMIN"
      }
    }
  }
  ```

### 2.3 Admin Login (Step 1: Credentials Check)
- **Endpoint:** `POST /api/v1/auth/admin/login`
- **Request Body:**
  ```json
  {
    "email": "rajesh.admin@smartpg.com",
    "password": "SecurePassword@123"
  }
  ```
- **Response (200 OK):**
  ```json
  {
    "success": true,
    "message": "Super Key dispatched to registered email address.",
    "data": {
      "requires_2fa": true,
      "email": "rajesh.admin@smartpg.com",
      "masked_email": "r***n@smartpg.com",
      "cooldown_seconds": 60,
      "expires_in_minutes": 10
    }
  }
  ```

### 2.4 Admin Login Verify (Step 2: Super Key Verification & Token Issuance)
- **Endpoint:** `POST /api/v1/auth/admin/login/verify`
- **Request Body:**
  ```json
  {
    "email": "rajesh.admin@smartpg.com",
    "super_key": "489201"
  }
  ```
- **Response (200 OK):**
  ```json
  {
    "success": true,
    "message": "Two-factor authentication successful.",
    "data": {
      "access_token": "eyJhbGciOi...",
      "refresh_token": "eyJhbGciOi...",
      "token_type": "bearer",
      "user": {
        "id": "c1f7b3a2-...",
        "full_name": "Rajesh Kumar",
        "email": "rajesh.admin@smartpg.com",
        "role": "SUPER_ADMIN"
      }
    }
  }
  ```

---

## 3. Property Management Module

### 3.1 List Properties
- **Endpoint:** `GET /api/v1/properties`
- **Access:** `SUPER_ADMIN`, `ADMIN`, `OWNER`, `PROPERTY_MANAGER`
- **Query Params:** `city`, `is_active`, `search`
- **Response (200 OK):**
  ```json
  {
    "success": true,
    "message": "Retrieved 2 properties.",
    "data": [
      {
        "id": "e2a3b4c5-...",
        "name": "Smart Central Heights PG",
        "code": "SCH01",
        "property_type": "COLIVING",
        "city": "Bengaluru",
        "state": "Karnataka",
        "is_active": true,
        "total_floors": 4,
        "total_rooms": 12,
        "total_beds": 36,
        "occupied_beds": 28
      }
    ]
  }
  ```

### 3.2 Create Property
- **Endpoint:** `POST /api/v1/properties`
- **Access:** `SUPER_ADMIN`, `OWNER`
- **Request Body:**
  ```json
  {
    "name": "Smart Electronic City Branch",
    "code": "SEC02",
    "property_type": "MENS",
    "address_line1": "45 Neeladri Road, Electronic City Phase 1",
    "city": "Bengaluru",
    "state": "Karnataka",
    "pincode": "560100",
    "contact_phone": "9886699258",
    "contact_email": "ecity@smartpg.com",
    "total_floors": 3,
    "description": "Premium gents PG with high-speed WiFi and attached washrooms."
  }
  ```

### 3.3 Delegate Property Access
- **Endpoint:** `POST /api/v1/properties/{property_id}/access`
- **Access:** `SUPER_ADMIN`, `OWNER`
- **Request Body:**
  ```json
  {
    "user_id": "3b2a1c0d-..."
  }
  ```

---

## 4. Room & Floor Management Module

### 4.1 Add Room
- **Endpoint:** `POST /api/v1/rooms`
- **Access:** `SUPER_ADMIN`, `OWNER`, `PROPERTY_MANAGER`
- **Request Body:**
  ```json
  {
    "property_id": "e2a3b4c5-...",
    "room_number": "101",
    "floor": 1,
    "room_type": "DOUBLE",
    "base_monthly_rent": 8500.00,
    "deposit_amount": 17000.00
  }
  ```

### 4.2 Floor-Wise Room Grouping
- **Endpoint:** `GET /api/v1/rooms/floor-wise?property_id={property_id}`
- **Access:** `SUPER_ADMIN`, `OWNER`, `PROPERTY_MANAGER`
- **Response (200 OK):**
  ```json
  {
    "success": true,
    "message": "Floor-wise rooms retrieved successfully.",
    "data": {
      "property_id": "e2a3b4c5-...",
      "total_floors": 3,
      "floors": [
        {
          "floor_number": 1,
          "total_rooms": 4,
          "total_beds": 8,
          "occupied_beds": 6,
          "rooms": [
            {
              "id": "r101-...",
              "room_number": "101",
              "room_type": "DOUBLE",
              "beds": [
                {"id": "b1-...", "bed_number": "101-A", "status": "OCCUPIED", "resident_name": "Arjun Raman"},
                {"id": "b2-...", "bed_number": "101-B", "status": "AVAILABLE"}
              ]
            }
          ]
        }
      ]
    }
  }
  ```

---

## 5. Bed Allocation Module

### 5.1 Add Bed
- **Endpoint:** `POST /api/v1/beds`
- **Request Body:**
  ```json
  {
    "room_id": "r101-...",
    "property_id": "e2a3b4c5-...",
    "bed_number": "101-C",
    "monthly_rent": 8500.00
  }
  ```
- **Validation**: Enforces room maximum occupancy limit; rejects excess allocations.

---

## 6. Resident Onboarding & KYC Module

### 6.1 Manual Resident Onboarding
- **Endpoint:** `POST /api/v1/residents`
- **Access:** `SUPER_ADMIN`, `OWNER`, `PROPERTY_MANAGER`
- **Request Body:**
  ```json
  {
    "property_id": "e2a3b4c5-...",
    "room_id": "r101-...",
    "bed_id": "b2-...",
    "full_name": "Aditya Roy",
    "phone": "9812345678",
    "email": "aditya.roy@example.com",
    "check_in_date": "2026-11-01",
    "monthly_rent": 8500.00,
    "security_deposit": 17000.00,
    "kyc_document_type": "AADHAAR",
    "kyc_document_number": "567890123456"
  }
  ```
- **Behavior**: Atomically creates User account, Resident profile, claims Bed (`status="OCCUPIED"`), and masks KYC number (`XXXXXXXX3456`).

### 6.2 Verify Resident KYC
- **Endpoint:** `POST /api/v1/residents/{resident_id}/kyc/verify`
- **Response (200 OK):** Updates resident `kyc_status="VERIFIED"`.

---

## 7. Rent Invoicing & Offline Collection Module

### 7.1 Create Rent Invoice
- **Endpoint:** `POST /api/v1/invoices`
- **Request Body:**
  ```json
  {
    "property_id": "e2a3b4c5-...",
    "resident_id": "res-123-...",
    "billing_month": "2026-11",
    "invoice_type": "RENT",
    "amount": 8500.00,
    "due_date": "2026-11-05",
    "notes": "November 2026 Rent"
  }
  ```

### 7.2 Collect Rent Offline (Cash / Bank Transfer / UPI / Cheque)
- **Endpoint:** `POST /api/v1/payments/collect`
- **Access:** `SUPER_ADMIN`, `OWNER`, `PROPERTY_MANAGER`
- **Request Body:**
  ```json
  {
    "property_id": "e2a3b4c5-...",
    "resident_id": "res-123-...",
    "invoice_id": "inv-123-...",
    "collect_amount": 8500.00,
    "payment_mode": "CASH",
    "transaction_reference": "CASH-REC-NOV01",
    "notes": "Full rent settled in cash"
  }
  ```
- **Response (201 Created):**
  ```json
  {
    "success": true,
    "message": "Rent collected successfully.",
    "data": {
      "payment_id": "pay-...",
      "payment_number": "PAY-COL-20261102-...",
      "invoice_id": "inv-...",
      "amount": 8500.00,
      "payment_mode": "CASH",
      "status": "SUCCESS",
      "receipt_id": "rct-...",
      "receipt_number": "RCT-COL-20261102-...",
      "invoice_status": "PAID",
      "invoice_paid_amount": 8500.00,
      "remaining_balance": 0.00
    }
  }
  ```

---

## 8. Operational Expense Ledger

### 8.1 Record Expense
- **Endpoint:** `POST /api/v1/expenses`
- **Request Body:**
  ```json
  {
    "property_id": "e2a3b4c5-...",
    "category": "UTILITIES",
    "title": "Electricity Bill - BESCOM",
    "amount": 6250.00,
    "method": "UPI",
    "date": "2026-11-02",
    "notes": "October meter power bill"
  }
  ```

### 8.2 List & Filter Expenses
- **Endpoint:** `GET /api/v1/expenses?property_id={property_id}&category=UTILITIES`
- **Response (200 OK):** Returns items list, `total_amount`, and `count`.

---

## 9. Staff Management Module

### 9.1 Create Staff
- **Endpoint:** `POST /api/v1/staff`
- **Request Body:**
  ```json
  {
    "property_id": "e2a3b4c5-...",
    "name": "Suresh Gowda",
    "role": "WARDEN",
    "phone": "9845012345",
    "email": "suresh.warden@smartpg.com",
    "salary": 24000.00,
    "joining_date": "2026-08-01",
    "availability_hours": "8:00 AM - 8:00 PM",
    "is_emergency_contact": true
  }
  ```

---

## 10. Weekly Food Menu Management

### 10.1 Create Weekly Menu Item
- **Endpoint:** `POST /api/v1/food-menus`
- **Request Body:**
  ```json
  {
    "property_id": "e2a3b4c5-...",
    "day_of_week": "MONDAY",
    "meal_type": "BREAKFAST",
    "start_time": "07:30 AM",
    "end_time": "09:30 AM",
    "dishes": ["Idli", "Vada", "Sambar", "Coconut Chutney", "Filter Coffee"]
  }
  ```
- **Validation**: Enforces unique `(property_id, day_of_week, meal_type)` constraint.

---

## 11. Maintenance & Complaints Module

### 11.1 Assign Complaint to Staff
- **Endpoint:** `POST /api/v1/complaints/{complaint_id}/assign`
- **Request Body:**
  ```json
  {
    "assigned_staff_id": "staff-123-..."
  }
  ```
- **Behavior**: Transitions complaint to `ASSIGNED` and dispatches in-app notification to the resident.

### 11.2 Resolve Complaint
- **Endpoint:** `POST /api/v1/complaints/{complaint_id}/resolve`
- **Request Body:**
  ```json
  {
    "resolution_notes": "Plumber replaced the faucet washer. Leak resolved.",
    "status": "RESOLVED"
  }
  ```

---

## 12. Leads / Prospective Tenant CRM

### 12.1 Create Lead & Pipeline Stage
- **Endpoint:** `POST /api/v1/leads`
- **Request Body:**
  ```json
  {
    "property_id": "e2a3b4c5-...",
    "name": "Meera Nair",
    "phone": "9900112233",
    "email": "meera.nair@example.com",
    "source": "WEBSITE",
    "requirement": "Single sharing AC with work desk"
  }
  ```
- **Pipeline Transitions**: `NEW` $\to$ `CONTACTED` $\to$ `VISIT_SCHEDULED` $\to$ `BOOKED` / `LOST`.

---

## 13. Executive Reports & CSV Exports

### 13.1 Executive Dashboard
- **Endpoint:** `GET /api/v1/reports/dashboard?property_id={property_id}`
- **Metrics Computed:**
  - `total_properties`, `total_residents`, `active_residents`
  - `total_beds`, `occupied_beds`, `vacant_beds`, `occupancy_rate_percent`
  - `gross_collections`, `total_expenses`, `net_operating_profit`
  - `pending_rent`, `open_complaints`

### 13.2 Financial Analytics Report
- **Endpoint:** `GET /api/v1/reports/financial?date_from=2026-11-01&date_to=2026-11-30`
- **Net Operating Profit Formula:**
  $$\text{Net Operating Profit} = \sum \text{Gross Collections (SUCCESS / PAID)} - \sum \text{Operational Expenses}$$

### 13.3 CSV Data Exports
- `GET /api/v1/reports/payments/export`: Generates downloadable `payments_report.csv`.
- `GET /api/v1/reports/occupancy/export`: Generates downloadable `occupancy_report.csv` with bed-level status.

---

## 14. Company Settings & Subscription Quotas

### 14.1 Enterprise Profile & Limits
- **Endpoint:** `GET /api/v1/settings/subscription`
- **Response (200 OK):**
  ```json
  {
    "success": true,
    "data": {
      "plan": "ENTERPRISE",
      "status": "ACTIVE",
      "active_properties": 4,
      "active_residents": 128,
      "limits": {
        "max_properties": 50,
        "max_residents": 5000
      }
    }
  }
  ```
