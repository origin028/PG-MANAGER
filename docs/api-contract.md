# Shared Backend API Contract

This document provides the complete integration specification for Flutter frontend developers working on:
1. **Admin Web Panel** (`client_type: "admin_web"`)
2. **Admin Mobile Application** (`client_type: "admin_mobile"`)
3. **Resident Mobile Application** (`client_type: "resident_mobile"`)

---

## 1. Protocols & Standards

- **Base URL Prefix**: `/api/v1`
- **Data Serialization**: `application/json`
- **Authentication**: `Authorization: Bearer <access_token>`
- **Property Context Header**: `X-Property-Id: <uuid>` (used by Admin clients when switching between properties)
- **DateTime Format**: ISO 8601 UTC (`YYYY-MM-DDTHH:MM:SS.mmmmmmZ`)

---

## 2. Standard Envelope Formats

### Success Envelope (`200 OK`, `201 Created`)
```json
{
  "success": true,
  "message": "Operation completed successfully.",
  "data": { ... },
  "timestamp": "2026-10-23T14:00:00Z"
}
```

### Paginated Envelope
```json
{
  "success": true,
  "message": "Items retrieved successfully.",
  "data": {
    "items": [ ... ],
    "total": 45,
    "page": 1,
    "page_size": 20,
    "total_pages": 3
  },
  "timestamp": "2026-10-23T14:00:00Z"
}
```

### Error Envelope (`400`, `401`, `403`, `404`, `409`, `422`, `500`)
```json
{
  "success": false,
  "error": {
    "code": "PERMISSION_DENIED",
    "message": "Residents cannot access the Admin panel.",
    "details": null
  },
  "timestamp": "2026-10-23T14:00:00Z"
}
```

---

## 3. Core Endpoint Groups

| Module | Route Prefix | Primary Roles | Purpose |
| :--- | :--- | :--- | :--- |
| **Health** | `GET /api/v1/health` | Public | System status and database ping |
| **Auth** | `/api/v1/auth/*` | Public / Authenticated | Login, token refresh, logout, profile |
| **Users** | `/api/v1/users/*` | Super Admin, Manager | User listing, staff creation, property assignment |
| **Properties** | `/api/v1/properties/*` | All Authenticated | Property list, details, creation |
| **Rooms** | `/api/v1/rooms/*` | Admin, Staff | Floor plans, room types, pricing |
| **Beds** | `/api/v1/beds/*` | Admin, Staff | Bed statuses, atomic allocation & release |
| **Residents** | `/api/v1/residents/*` | Admin, Staff, Resident | Onboarding, KYC verification, checkout settlement |
| **Invoices** | `/api/v1/invoices/*` | Admin, Staff, Resident | Monthly billing generation, rent ledger |
| **Payments** | `/api/v1/payments/*` | Admin, Staff, Resident | Gateway order creation, webhook verification, cash receipting |
| **Complaints** | `/api/v1/complaints/*` | All | Complaint filing, assignment, progress updates |
| **Expenses** | `/api/v1/expenses/*` | Admin, Manager | Expense vouchers and category tracking |
| **Staff** | `/api/v1/staff/*` | Super Admin, Manager | Staff directory, roster, salary records |
| **Leads** | `/api/v1/leads/*` | Admin, Manager | Inquiries, visits, lead-to-resident conversion |
| **Notices** | `/api/v1/notices/*` | All | Broadcast board announcements |
| **Notifications** | `/api/v1/notifications/*`| All | Notification inbox and preferences |
| **Reports** | `/api/v1/reports/*` | Super Admin, Manager | Occupancy, collection efficiency, revenue vs expense |
| **Audit Logs** | `/api/v1/audit-logs/*` | Super Admin | Immutable operational audit trail |
