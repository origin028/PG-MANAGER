# Origin PG Management System – Admin & Owner Web Panel API Payload Examples
**Base URL:** `http://localhost:8000/api/v1` | **Headers:** `Content-Type: application/json`, `Authorization: Bearer <JWT>`

---

## 1. Authentication & 2FA Super Key

### 1.1 Admin Registration Request
```bash
curl -X POST "http://localhost:8000/api/v1/auth/admin/register" \
  -H "Content-Type: application/json" \
  -d '{
    "full_name": "Siddharth Rao",
    "email": "siddharth.admin@smartpg.com",
    "phone": "9876543210",
    "password": "AdminPassword@2026",
    "company_name": "Smart Living PG Group",
    "role": "SUPER_ADMIN"
  }'
```
**Response (200 OK):**
```json
{
  "success": true,
  "message": "Super Key dispatched to registered email. Please verify to complete account registration.",
  "data": {
    "email": "siddharth.admin@smartpg.com",
    "masked_email": "s***o@smartpg.com",
    "cooldown_seconds": 60,
    "expires_in_minutes": 10
  }
}
```

### 1.2 Admin Registration Verify
```bash
curl -X POST "http://localhost:8000/api/v1/auth/admin/register/verify" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "siddharth.admin@smartpg.com",
    "super_key": "654321"
  }'
```
**Response (201 Created):**
```json
{
  "success": true,
  "message": "Admin registration verified and account activated successfully.",
  "data": {
    "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "token_type": "bearer",
    "user": {
      "id": "e4f8a120-10ad-4672-88ec-a309f425c041",
      "full_name": "Siddharth Rao",
      "email": "siddharth.admin@smartpg.com",
      "phone": "9876543210",
      "role": "SUPER_ADMIN"
    }
  }
}
```

### 1.3 Admin Login (Step 1: Credentials Check)
```bash
curl -X POST "http://localhost:8000/api/v1/auth/admin/login" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "siddharth.admin@smartpg.com",
    "password": "AdminPassword@2026"
  }'
```
**Response (200 OK):**
```json
{
  "success": true,
  "message": "Super Key dispatched to registered email address.",
  "data": {
    "requires_2fa": true,
    "email": "siddharth.admin@smartpg.com",
    "masked_email": "s***o@smartpg.com",
    "cooldown_seconds": 60,
    "expires_in_minutes": 10
  }
}
```

### 1.4 Admin Login Verify (Step 2: 2FA Super Key Verification)
```bash
curl -X POST "http://localhost:8000/api/v1/auth/admin/login/verify" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "siddharth.admin@smartpg.com",
    "super_key": "654321"
  }'
```
**Response (200 OK):**
```json
{
  "success": true,
  "message": "Two-factor authentication successful.",
  "data": {
    "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "token_type": "bearer",
    "user": {
      "id": "e4f8a120-10ad-4672-88ec-a309f425c041",
      "full_name": "Siddharth Rao",
      "email": "siddharth.admin@smartpg.com",
      "role": "SUPER_ADMIN"
    }
  }
}
```

---

## 2. Property Management

### 2.1 Create Property
```bash
curl -X POST "http://localhost:8000/api/v1/properties" \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Smart Central Heights PG",
    "code": "SCH01",
    "property_type": "COLIVING",
    "address_line1": "100 Technology Park Road",
    "city": "Bengaluru",
    "state": "Karnataka",
    "pincode": "560100",
    "contact_phone": "9886699258",
    "contact_email": "central@smartpg.com",
    "total_floors": 4,
    "description": "Premium luxury PG accommodation."
  }'
```
**Response (201 Created):**
```json
{
  "success": true,
  "message": "Property 'Smart Central Heights PG' created successfully.",
  "data": {
    "id": "b1a2c3d4-e5f6-4789-0123-456789abcdef",
    "company_id": "c1d2e3f4-...",
    "name": "Smart Central Heights PG",
    "code": "SCH01",
    "property_type": "COLIVING",
    "city": "Bengaluru",
    "state": "Karnataka",
    "pincode": "560100",
    "total_floors": 4,
    "is_active": true
  }
}
```

### 2.2 Delegate Property Access
```bash
curl -X POST "http://localhost:8000/api/v1/properties/b1a2c3d4-e5f6-4789-0123-456789abcdef/access" \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "7a8b9c0d-1e2f-3456-7890-abcdef123456"
  }'
```
**Response (200 OK):**
```json
{
  "success": true,
  "message": "Property access granted to user 'Ramesh Manager'.",
  "data": {
    "property_id": "b1a2c3d4-e5f6-4789-0123-456789abcdef",
    "user_id": "7a8b9c0d-1e2f-3456-7890-abcdef123456"
  }
}
```

---

## 3. Rooms & Floor Grouping

### 3.1 Create Room
```bash
curl -X POST "http://localhost:8000/api/v1/rooms" \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "property_id": "b1a2c3d4-e5f6-4789-0123-456789abcdef",
    "room_number": "101",
    "floor": 1,
    "room_type": "DOUBLE",
    "base_monthly_rent": 8500.00,
    "deposit_amount": 17000.00
  }'
```

### 3.2 View Floor-Wise Rooms
```bash
curl -X GET "http://localhost:8000/api/v1/rooms/floor-wise?property_id=b1a2c3d4-e5f6-4789-0123-456789abcdef" \
  -H "Authorization: Bearer <TOKEN>"
```
**Response (200 OK):**
```json
{
  "success": true,
  "message": "Floor-wise rooms retrieved successfully.",
  "data": {
    "property_id": "b1a2c3d4-e5f6-4789-0123-456789abcdef",
    "total_floors": 1,
    "floors": [
      {
        "floor_number": 1,
        "total_rooms": 1,
        "total_beds": 2,
        "occupied_beds": 1,
        "rooms": [
          {
            "id": "r101-...",
            "room_number": "101",
            "room_type": "DOUBLE",
            "beds": [
              {"id": "b1-...", "bed_number": "101-A", "status": "OCCUPIED", "resident_name": "Aditya Roy"},
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

## 4. Bed Allocation

### 4.1 Create Bed
```bash
curl -X POST "http://localhost:8000/api/v1/beds" \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "room_id": "r101-...",
    "property_id": "b1a2c3d4-e5f6-4789-0123-456789abcdef",
    "bed_number": "101-A",
    "monthly_rent": 8500.00
  }'
```

---

## 5. Resident Onboarding & KYC

### 5.1 Manual Resident Onboarding
```bash
curl -X POST "http://localhost:8000/api/v1/residents" \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "property_id": "b1a2c3d4-e5f6-4789-0123-456789abcdef",
    "room_id": "r101-...",
    "bed_id": "b1-...",
    "full_name": "Aditya Roy",
    "email": "aditya.roy@example.com",
    "phone": "9812345678",
    "check_in_date": "2026-11-01",
    "monthly_rent": 8500.00,
    "security_deposit": 17000.00,
    "kyc_document_type": "AADHAAR",
    "kyc_document_number": "123456789012"
  }'
```
**Response (201 Created):**
```json
{
  "success": true,
  "message": "Resident 'Aditya Roy' successfully onboarded.",
  "data": {
    "id": "res-9001-...",
    "full_name": "Aditya Roy",
    "phone": "9812345678",
    "email": "aditya.roy@example.com",
    "property_name": "Smart Central Heights PG",
    "room_number": "101",
    "bed_number": "101-A",
    "check_in_date": "2026-11-01",
    "monthly_rent": 8500.00,
    "security_deposit": 17000.00,
    "status": "ACTIVE",
    "kyc_status": "PENDING",
    "id_proof_type": "AADHAAR",
    "kyc_document_number": "XXXXXXXX9012"
  }
}
```

### 5.2 Verify KYC
```bash
curl -X POST "http://localhost:8000/api/v1/residents/res-9001-.../kyc/verify" \
  -H "Authorization: Bearer <TOKEN>"
```

---

## 6. Rent Invoicing & Offline Collection

### 6.1 Create Monthly Rent Invoice
```bash
curl -X POST "http://localhost:8000/api/v1/invoices" \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "property_id": "b1a2c3d4-e5f6-4789-0123-456789abcdef",
    "resident_id": "res-9001-...",
    "billing_month": "2026-11",
    "invoice_type": "RENT",
    "amount": 8500.00,
    "due_date": "2026-11-05",
    "notes": "November 2026 Monthly Rent"
  }'
```

### 6.2 Collect Offline Payment
```bash
curl -X POST "http://localhost:8000/api/v1/payments/collect" \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "property_id": "b1a2c3d4-e5f6-4789-0123-456789abcdef",
    "resident_id": "res-9001-...",
    "invoice_id": "inv-5001-...",
    "collect_amount": 8500.00,
    "payment_mode": "CASH",
    "transaction_reference": "CASH-REC-001",
    "notes": "Settled in full via cash"
  }'
```
**Response (201 Created):**
```json
{
  "success": true,
  "message": "Rent collected successfully.",
  "data": {
    "payment_id": "pay-8001-...",
    "payment_number": "PAY-COL-20261102-A1B2C3D4",
    "invoice_id": "inv-5001-...",
    "amount": 8500.00,
    "payment_mode": "CASH",
    "status": "SUCCESS",
    "receipt_id": "rct-2001-...",
    "receipt_number": "RCT-COL-20261102-E5F6G7H8",
    "invoice_status": "PAID",
    "invoice_paid_amount": 8500.00,
    "remaining_balance": 0.00
  }
}
```

---

## 7. Operational Expense Ledger

### 7.1 Record Expense
```bash
curl -X POST "http://localhost:8000/api/v1/expenses" \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "property_id": "b1a2c3d4-e5f6-4789-0123-456789abcdef",
    "category": "UTILITIES",
    "title": "BESCOM Electricity Bill",
    "amount": 5400.00,
    "method": "UPI",
    "date": "2026-11-02",
    "notes": "Meter bill for block A"
  }'
```

---

## 8. Staff Management

### 8.1 Create Staff
```bash
curl -X POST "http://localhost:8000/api/v1/staff" \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "property_id": "b1a2c3d4-e5f6-4789-0123-456789abcdef",
    "name": "Manjunath K",
    "role": "SECURITY",
    "phone": "9877112233",
    "email": "manju.sec@smartpg.com",
    "salary": 18000.00,
    "joining_date": "2026-06-01",
    "is_emergency_contact": true
  }'
```

---

## 9. Weekly Food Menu

### 9.1 Create Menu Item
```bash
curl -X POST "http://localhost:8000/api/v1/food-menus" \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "property_id": "b1a2c3d4-e5f6-4789-0123-456789abcdef",
    "day_of_week": "THURSDAY",
    "meal_type": "DINNER",
    "start_time": "08:00 PM",
    "end_time": "10:00 PM",
    "dishes": ["Chapati", "Dal Tadka", "Aloo Gobi", "Jeera Rice", "Gulab Jamun"]
  }'
```

---

## 10. Maintenance & Complaints

### 10.1 Assign Staff
```bash
curl -X POST "http://localhost:8000/api/v1/complaints/cmp-1001-.../assign" \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "assigned_staff_id": "staff-3001-..."
  }'
```

### 10.2 Resolve Complaint
```bash
curl -X POST "http://localhost:8000/api/v1/complaints/cmp-1001-.../resolve" \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "resolution_notes": "Wi-Fi access point firmware updated and tested.",
    "status": "RESOLVED"
  }'
```

---

## 11. Prospective Tenant Leads / CRM

### 11.1 Create Lead
```bash
curl -X POST "http://localhost:8000/api/v1/leads" \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "property_id": "b1a2c3d4-e5f6-4789-0123-456789abcdef",
    "name": "Kavya Murthy",
    "phone": "9988112244",
    "email": "kavya.m@example.com",
    "source": "WALK_IN",
    "requirement": "Single room with attached bath"
  }'
```

### 11.2 Advance Pipeline Stage
```bash
curl -X PATCH "http://localhost:8000/api/v1/leads/lead-4001-..." \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "status": "VISIT_SCHEDULED",
    "visit_date": "2026-11-05T11:00:00Z",
    "notes": "Confirmed visit for Thursday 11 AM"
  }'
```

---

## 12. Notices & Broadcasts

### 12.1 Publish Notice
```bash
curl -X POST "http://localhost:8000/api/v1/notices" \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "property_id": "b1a2c3d4-e5f6-4789-0123-456789abcdef",
    "title": "Scheduled Water Tank Cleaning",
    "content": "Water tank cleaning will take place tomorrow from 10:00 AM to 02:00 PM. Please store sufficient water.",
    "is_pinned": true
  }'
```

---

## 13. Reports, Analytics & CSV Exports

### 13.1 Executive Dashboard
```bash
curl -X GET "http://localhost:8000/api/v1/reports/dashboard?property_id=b1a2c3d4-e5f6-4789-0123-456789abcdef" \
  -H "Authorization: Bearer <TOKEN>"
```

### 13.2 Payments CSV Export
```bash
curl -X GET "http://localhost:8000/api/v1/reports/payments/export?property_id=b1a2c3d4-e5f6-4789-0123-456789abcdef" \
  -H "Authorization: Bearer <TOKEN>" \
  -o payments_report.csv
```

### 13.3 Occupancy CSV Export
```bash
curl -X GET "http://localhost:8000/api/v1/reports/occupancy/export?property_id=b1a2c3d4-e5f6-4789-0123-456789abcdef" \
  -H "Authorization: Bearer <TOKEN>" \
  -o occupancy_report.csv
```

---

## 14. Company Settings & Quotas

### 14.1 Inspect Subscription Quotas
```bash
curl -X GET "http://localhost:8000/api/v1/settings/subscription" \
  -H "Authorization: Bearer <TOKEN>"
```
**Response (200 OK):**
```json
{
  "success": true,
  "message": "Subscription details retrieved successfully.",
  "data": {
    "plan": "ENTERPRISE",
    "status": "ACTIVE",
    "active_properties": 4,
    "active_residents": 128,
    "limits": {
      "max_properties": 50,
      "max_residents": 5000
    },
    "features": [
      "Online & Offline Rent Collection",
      "Super Key 2FA Authentication",
      "Resident Mobile App & KYC Onboarding",
      "Room & Bed Allocation Management",
      "Maintenance & Complaint Tracking",
      "Operational Expense Ledger",
      "Staff Management",
      "Weekly Food Menu Management",
      "Financial & Occupancy CSV Reporting",
      "Audit Logging & Security Verification"
    ]
  }
}
```
