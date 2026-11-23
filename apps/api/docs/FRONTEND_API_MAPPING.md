# PG Management System — Frontend to Backend API Mapping Specification

This document maps all frontend screens in the **Admin App** (Flutter Web/Desktop) and **Resident App** (Flutter Mobile) to their corresponding FastAPI backend endpoints (`http://localhost:8000/api/v1` or configured base URL).

---

## 1. Global & Architectural Standards

- **Base URL Configuration:** Passed via `--dart-define=API_BASE_URL=...`
  - Flutter Web / Chrome: `http://127.0.0.1:8000/api/v1`
  - Android Emulator: `http://10.0.2.2:8000/api/v1`
  - Physical Android Device: `http://<LAN_IP>:8000/api/v1`
- **Envelope Standard:** All responses use the unified API envelope:
  ```json
  {
    "success": true,
    "message": "Human readable message",
    "data": { ... }
  }
  ```
- **Error Standard:**
  ```json
  {
    "success": false,
    "error": {
      "code": "ERROR_CODE",
      "message": "Error details",
      "details": { ... }
    }
  }
  ```
- **Authentication Scheme:** `Authorization: Bearer <access_token>` in HTTP request headers.

---

## 2. Admin / Owner App Endpoint Mapping

| # | Admin App Screen | UI File Path | Backend Endpoint | HTTP Method | Request Payload / Query Params | Response Data Object |
|---|---|---|---|---|---|---|
| 1 | **Admin Login** | `features/auth/login_screen.dart` | `/api/v1/auth/admin/login` | `POST` | `{"email": "...", "password": "..."}` | `TokenResponse` (`access_token`, `refresh_token`, `user`) [Direct issuance; no 2FA] |
| 2 | **Register PG Owner** | `core/router/app_router.dart` | `/api/v1/auth/admin/register` | `POST` | `{"business_name": "...", "email": "...", "password": "...", "confirm_password": "...", "super_key": "..."}` | `APIResponse` (immediate activation with Common Super Key) |
| 3 | **Login Super Key (Legacy Compat)** | `core/services/admin_auth_service.dart` | `/api/v1/auth/admin/login/verify` | `POST` | `{"email": "...", "super_key": "..."}` | `TokenResponse` |
| 4 | **Register Verification (Legacy Compat)** | `core/services/admin_auth_service.dart` | `/api/v1/auth/admin/register/verify` | `POST` | `{"email": "...", "super_key": "..."}` | `TokenResponse` |
| 5 | **Header / Property Switcher** | `core/widgets/admin_layout.dart` | `/api/v1/properties` | `GET` | None | `List[PropertyRead]` |
| 6 | **Header Notifications** | `core/widgets/admin_layout.dart` | `/api/v1/notifications` | `GET` | `?unread_only=true` | `List[NotificationRead]` |
| 7 | **Executive Dashboard** | `features/dashboard/dashboard_screen.dart` | `/api/v1/reports/dashboard` | `GET` | `?property_id=<UUID>` | `DashboardReportResponse` (revenue, occupancy, beds, pending dues) |
| 8 | **Dashboard Notice Broadcast**| `features/dashboard/dashboard_screen.dart` | `/api/v1/notices` | `POST` | `{"property_id": "...", "title": "...", "message": "...", "priority": "NORMAL"}` | `NoticeRead` |
| 9 | **Properties List** | `features/properties/properties_screen.dart` | `/api/v1/properties` | `GET` | None | `List[PropertyRead]` |
| 10 | **Create Property** | `features/properties/property_form_dialog.dart` | `/api/v1/properties` | `POST` | `{"name": "...", "address": "...", "total_floors": 3, "description": "..."}` | `PropertyRead` |
| 11 | **Update Property** | `features/properties/property_form_dialog.dart` | `/api/v1/properties/{id}` | `PUT` | `PropertyUpdate` | `PropertyRead` |
| 12 | **Delete Property** | `features/properties/properties_screen.dart` | `/api/v1/properties/{id}` | `DELETE` | None | `{"success": true}` |
| 13 | **Rooms & Beds by Floor** | `features/rooms_beds/rooms_beds_screen.dart` | `/api/v1/rooms/property/{property_id}/floors` | `GET` | None | `List[FloorGroupResponse]` (rooms + beds breakdown) |
| 14 | **Create Room** | `features/rooms_beds/rooms_beds_screen.dart` | `/api/v1/rooms` | `POST` | `{"property_id": "...", "room_number": "101", "floor": 1, "room_type": "DOUBLE", "base_rent": 8000}` | `RoomRead` |
| 15 | **Create Bed** | `features/rooms_beds/rooms_beds_screen.dart` | `/api/v1/beds` | `POST` | `{"room_id": "...", "bed_number": "A", "monthly_rent": 8000}` | `BedRead` |
| 16 | **Residents List & KYC** | `features/residents/residents_screen.dart` | `/api/v1/residents` | `GET` | `?property_id=<UUID>&status=ALL` | `List[ResidentSummary]` |
| 17 | **Manual Resident Onboarding**| `features/residents/residents_screen.dart` | `/api/v1/residents/onboard` | `POST` | `AdminResidentOnboardRequest` (`full_name`, `phone`, `email`, `property_id`, `room_id`, `bed_id`, `monthly_rent`, `security_deposit`) | `ResidentDetailRead` |
| 18 | **Verify Resident KYC** | `features/residents/residents_screen.dart` | `/api/v1/residents/{id}/verify-kyc` | `POST` | None | `ResidentDetailRead` |
| 19 | **Reject Resident KYC** | `features/residents/residents_screen.dart` | `/api/v1/residents/{id}/reject-kyc` | `POST` | `{"notes": "..."}` | `ResidentDetailRead` |
| 20 | **Checkout Resident** | `features/residents/residents_screen.dart` | `/api/v1/residents/{id}/checkout` | `POST` | `{"damage_charges": 0, "damage_notes": ""}` | `ResidentCheckoutResponse` |
| 21 | **Invoices & Payments List** | `features/payments/payments_screen.dart` | `/api/v1/invoices` | `GET` | `?property_id=<UUID>` | `List[InvoiceRead]` |
| 22 | **Collect Rent (Offline)** | `features/payments/payments_screen.dart` | `/api/v1/payments/collect` | `POST` | `{"invoice_id": "...", "amount": 8000, "payment_mode": "CASH", "reference_number": "..."}` | `PaymentRead` + Receipt |
| 23 | **Expenses List** | `features/expenses/expenses_screen.dart` | `/api/v1/expenses` | `GET` | `?property_id=<UUID>` | `List[ExpenseRead]` |
| 24 | **Record Expense** | `features/expenses/expenses_screen.dart` | `/api/v1/expenses` | `POST` | `{"property_id": "...", "title": "...", "amount": 1200, "category": "ELECTRICITY", "payment_mode": "UPI", "expense_date": "2026-11-02"}` | `ExpenseRead` |
| 25 | **Staff List** | `features/staff/staff_screen.dart` | `/api/v1/staff` | `GET` | `?property_id=<UUID>` | `List[StaffRead]` |
| 26 | **Create Staff Member** | `features/staff/staff_screen.dart` | `/api/v1/staff` | `POST` | `{"property_id": "...", "name": "...", "role": "WARDEN", "phone": "...", "salary": 18000}` | `StaffRead` |
| 27 | **Weekly Food Menu** | `features/food_menu/food_menu_screen.dart` | `/api/v1/food-menus/property/{property_id}/weekly` | `GET` | None | `List[FoodMenuRead]` |
| 28 | **Update Meal Plan** | `features/food_menu/food_menu_screen.dart` | `/api/v1/food-menus` | `POST` | `{"property_id": "...", "day_of_week": "MONDAY", "meal_type": "BREAKFAST", "items": ["Idli", "Sambar"]}` | `FoodMenuRead` |
| 29 | **Complaints List** | `features/complaints/complaints_screen.dart` | `/api/v1/complaints` | `GET` | `?property_id=<UUID>` | `List[ComplaintRead]` |
| 30 | **Assign Complaint** | `features/complaints/complaints_screen.dart` | `/api/v1/complaints/{id}/assign` | `POST` | `{"staff_id": "<UUID>"}` | `ComplaintRead` |
| 31 | **Resolve Complaint** | `features/complaints/complaints_screen.dart` | `/api/v1/complaints/{id}/resolve` | `POST` | `{"resolution_notes": "Repaired"}` | `ComplaintRead` |
| 32 | **Leads CRM Pipeline** | `features/leads/leads_screen.dart` | `/api/v1/leads` | `GET` | `?property_id=<UUID>` | `List[LeadRead]` |
| 33 | **Create Lead** | `features/leads/leads_screen.dart` | `/api/v1/leads` | `POST` | `{"property_id": "...", "name": "...", "phone": "...", "source": "WALK_IN"}` | `LeadRead` |
| 34 | **Update Lead Status** | `features/leads/leads_screen.dart` | `/api/v1/leads/{id}` | `PATCH` | `{"status": "VISITED", "notes": "..."}` | `LeadRead` |
| 35 | **Financial & Occupancy Reports**| `features/reports/reports_screen.dart` | `/api/v1/reports/financial` | `GET` | `?property_id=<UUID>` | `FinancialReportResponse` |
| 36 | **Download Payments CSV** | `features/reports/reports_screen.dart` | `/api/v1/reports/payments/export` | `GET` | `?property_id=<UUID>` | `text/csv` attachment stream |
| 37 | **Download Occupancy CSV**| `features/reports/reports_screen.dart` | `/api/v1/reports/occupancy/export` | `GET` | `?property_id=<UUID>` | `text/csv` attachment stream |
| 38 | **Company Settings** | `features/settings/settings_screen.dart` | `/api/v1/settings/company` | `GET` / `PATCH` | `{"name": "...", "email": "...", "address": "..."}` | `CompanySettingsResponse` |
| 39 | **Subscription Plan & Limits** | `features/settings/settings_screen.dart` | `/api/v1/settings/subscription` | `GET` | None | `SubscriptionQuotaResponse` |

---

## 3. Resident App Endpoint Mapping

| # | Resident App Screen | UI File Path | Backend Endpoint | HTTP Method | Request Payload / Query Params | Response Data Object |
|---|---|---|---|---|---|---|
| 1 | **Login (Request Email OTP)** | `features/auth/login_screen.dart` | `/api/v1/auth/resident/login/otp/request` | `POST` | `{"phone": "9867634364"}` | `OTPResponse` (`email_masked`, `expires_in_seconds`, `cooldown_seconds`) |
| 2 | **Login (Verify Email OTP)** | `features/auth/login_screen.dart` | `/api/v1/auth/resident/login/otp/verify` | `POST` | `{"phone": "9867634364", "otp": "123456"}` | `TokenResponse` (`access_token`, `refresh_token`, `user`) |
| 3 | **Home Dashboard** | `features/home/home_screen.dart` | `/api/v1/resident/dashboard` | `GET` | None | `ResidentDashboardResponse` (stay details, rent due, next due date, notices, payments) |
| 4 | **Food Menu (Weekly Tab)** | `features/food_menu/food_menu_screen.dart`| `/api/v1/resident/food-menu` | `GET` | None | `FoodMenuWeeklyResponse` (Monday–Sunday, Breakfast, Lunch, Dinner) |
| 5 | **Rent & Payments Tab** | `features/payments/payments_screen.dart` | `/api/v1/resident/invoices` | `GET` | None | `List[ResidentInvoiceListItem]` |
| 6 | **Payment History Ledger** | `features/payments/payments_screen.dart` | `/api/v1/resident/payments` | `GET` | None | `List[ResidentPaymentHistoryItem]` |
| 7 | **Invoice Breakdown** | `features/payments/rent_payment_screen.dart`| `/api/v1/resident/invoices/{invoice_id}` | `GET` | None | `ResidentInvoiceDetailResponse` |
| 8 | **Demo Rent Payment (Dev)** | `features/payments/rent_payment_screen.dart`| `/api/v1/payments/demo/pay` | `POST` | `{"invoice_id": "...", "amount": 8000, "payment_method": "UPI", "idempotency_key": "..."}` | `PaymentRead` + Receipt |
| 9 | **UPI Intent Initiation** | `features/payments/rent_payment_screen.dart`| `/api/v1/payments/requests` | `POST` | `{"invoice_id": "...", "amount": 8000, "vpa": "..."}` | `PaymentRequestResponse` (`upi_intent_url`, `request_id`) |
| 10 | **UPI Verification Status**| `features/payments/payment_status_screen.dart`| `/api/v1/payments/requests/{request_id}` | `GET` | None | `{"status": "COMPLETED", "payment_id": "..."}` |
| 11 | **Payment Receipt Details** | `features/payments/receipt_screen.dart` | `/api/v1/resident/invoices/{invoice_id}` | `GET` | None | `ResidentInvoiceDetailResponse` (`receipts`) |
| 12 | **Complaints Summary & List**| `features/complaints/complaints_screen.dart`| `/api/v1/resident/complaints` | `GET` | None | `List[ResidentComplaintRead]` |
| 13 | **All Complaints Screen** | `features/complaints/all_complaints_screen.dart`| `/api/v1/resident/complaints`| `GET` | None | `List[ResidentComplaintRead]` |
| 14 | **Upload Complaint Photo** | `features/complaints/raise_complaint_screen.dart`| `/api/v1/resident/complaints/upload-photo` | `POST` | `multipart/form-data` (`photo`) | `{"photo_path": "...", "filename": "..."}` |
| 15 | **Submit Complaint** | `features/complaints/raise_complaint_screen.dart`| `/api/v1/resident/complaints` | `POST` | `ResidentComplaintCreate` (`title`, `category`, `description`, `priority`, `photo_url`) | `ResidentComplaintRead` |
| 16 | **Resident Profile** | `features/profile/profile_screen.dart` | `/api/v1/resident/profile` | `GET` | None | `ResidentProfileFullRead` (personal info, masked KYC, stay details) |
| 17 | **Property Details** | `features/profile/property_details_screen.dart`| `/api/v1/resident/property` | `GET` | None | `ResidentPropertyDetailsResponse` (address, room, bed, amenities, rules) |
| 18 | **Property Contacts** | `features/profile/call_management_screen.dart`| `/api/v1/resident/property-contacts` | `GET` | None | `PropertyContactsResponse` (manager, warden, caretaker, security) |
| 19 | **Rent & Deposit Terms** | `features/profile/rent_deposit_screen.dart`| `/api/v1/resident/profile` | `GET` | None | Rent & deposit terms from `ResidentProfileFullRead` |
| 20 | **Notices Screen** | `features/notices/notices_screen.dart` | `/api/v1/resident/dashboard` or `/api/v1/notices` | `GET` | None | `List[ResidentNoticeItem]` |
| 21 | **App Settings** | `features/profile/settings_screen.dart` | `/api/v1/resident/settings` | `GET` | None | `ResidentSettingsRead` |
| 22 | **Update App Settings** | `features/profile/settings_screen.dart` | `/api/v1/resident/settings` | `PATCH` | `ResidentSettingsUpdate` (`dark_mode`, `language`, `push_notifications_enabled`, etc.) | `ResidentSettingsRead` |
