# PG Management System — Flutter Admin / Owner Web Panel Integration Setup Guide

## 1. Overview
The `admin_app` is a Flutter Web & Desktop management dashboard for PG Owners, Property Managers, and Super Administrators. It integrates with the FastAPI backend at `/api/v1` to perform complete administrative operations across properties, rooms, beds, resident onboarding, KYC verification, offline & online payment tracking, financial reporting, maintenance complaints, staff, leads, food menus, and system settings.

---

## 2. Architecture & Core Network Layer

```text
admin_app/
├── lib/
│   ├── main.dart                                # Initializes TokenStorage and app state
│   ├── core/
│   │   ├── network/
│   │   │   ├── api_client.dart                  # Base HTTP client with JWT interceptor & auto-URL
│   │   │   ├── api_exception.dart               # Structured exception hierarchy (400, 401, 403, 404, 409, 500)
│   │   │   └── token_storage.dart               # Persistent JWT token and user profile storage
│   │   ├── services/
│   │   │   ├── admin_auth_service.dart          # Login (Super Key 2FA), Register, Logout, Me
│   │   │   └── admin_api_service.dart           # Typed API service wrapping all 39 admin endpoints
│   │   ├── data/
│   │   │   └── app_data.dart                    # Reactive AppState with ValueNotifier for property switching
│   │   ├── router/
│   │   │   └── app_router.dart                  # GoRouter configuration with auth splash checking
│   │   └── widgets/
│   │       └── admin_layout.dart                # Global responsive scaffold with dynamic property selector
│   └── features/                                # Screen modules wired to AdminApiService
```

### Base URL Configuration
The API base URL is configurable at build or run time via `--dart-define`:
```bash
# Flutter Web (Chrome)
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1

# Flutter Desktop (Windows)
flutter run -d windows --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1
```
If not specified, `ApiClient` automatically defaults to `http://127.0.0.1:8000/api/v1` when running on Flutter Web or Desktop.

---

## 3. Authentication: Common Super Key Registration & Pure Email+Password Login

The Admin Web Panel implements a streamlined and secure authentication architecture:
1. **PG Owner Registration (`POST /api/v1/auth/admin/register`):**
   - User inputs Business Name, Email, Password, Confirm Password, and the Origin Company Common Super Key.
   - The backend validates the Common Super Key against the server environment configuration (`ADMIN_REGISTRATION_SUPER_KEY`) using constant-time comparison (`secrets.compare_digest`).
   - If valid, the backend immediately creates and activates the Company and Super Admin User (`is_active=True`, `is_verified=True`, `approval_status="APPROVED"`). No email OTP is required.
2. **Admin Login (`POST /api/v1/auth/admin/login`):**
   - User inputs Email and Password only.
   - Upon credentials validation, the backend directly returns JWT access and refresh tokens (`TokenResponse`).
   - No 2FA Super Key or OTP prompt is presented during login.
   - Tokens are saved in `TokenStorage` and the administrator is redirected immediately to `/dashboard`.
3. **Property Scoping & Context:**
   - On dashboard initialization, `AdminApiService.getProperties()` is invoked.
   - All properties are populated into `AppData.properties` and the top bar property switcher.
   - Switching the property notifies all active screens via `AppData.selectedPropertyIdNotifier`, seamlessly re-fetching property-scoped data.

---

## 4. Screen-to-API Mapping Summary

| Screen | File Path | Integrated Endpoint | Method |
|---|---|---|---|
| **Admin Login & 2FA** | `features/auth/login_screen.dart` | `/auth/login`<br>`/auth/verify-super-key` | `POST`<br>`POST` |
| **Owner Registration** | `core/router/app_router.dart` | `/auth/register`<br>`/auth/verify-register-super-key` | `POST`<br>`POST` |
| **Dashboard** | `features/dashboard/dashboard_screen.dart` | `/reports/dashboard`<br>`/residents`<br>`/notices` | `GET`<br>`GET`<br>`POST` |
| **Properties** | `features/properties/properties_screen.dart`<br>`property_form_dialog.dart` | `/properties`<br>`/properties/{id}` | `GET`, `POST`<br>`PUT`, `DELETE` |
| **Rooms & Beds** | `features/rooms_beds/rooms_beds_screen.dart` | `/rooms/property/{id}/floors`<br>`/rooms`<br>`/beds` | `GET`<br>`POST`, `DELETE`<br>`POST`, `DELETE` |
| **Residents & KYC** | `features/residents/residents_screen.dart` | `/residents`<br>`/residents/onboard`<br>`/residents/{id}/verify-kyc`<br>`/residents/{id}/reject-kyc`<br>`/residents/{id}/checkout` | `GET`<br>`POST`<br>`POST`<br>`POST`<br>`POST` |
| **Payments** | `features/payments/payments_screen.dart` | `/invoices`<br>`/payments/collect` | `GET`<br>`POST` |
| **Complaints** | `features/complaints/complaints_screen.dart` | `/complaints`<br>`/complaints/{id}/assign`<br>`/complaints/{id}/resolve` | `GET`<br>`POST`<br>`POST` |
| **Expenses** | `features/expenses/expenses_screen.dart` | `/expenses`<br>`/expenses` | `GET`<br>`POST` |
| **Staff** | `features/staff/staff_screen.dart` | `/staff`<br>`/staff` | `GET`<br>`POST` |
| **Food Menu** | `features/food_menu/food_menu_screen.dart` | `/food-menu/weekly`<br>`/food-menu` | `GET`<br>`POST` |
| **Leads** | `features/leads/leads_screen.dart` | `/leads`<br>`/leads` | `GET`<br>`POST` |
| **Financial Reports** | `features/reports/reports_screen.dart` | `/reports/financial`<br>`/reports/occupancy` | `GET`<br>`GET` |
| **Settings** | `features/settings/settings_screen.dart` | `/settings/company`<br>`/settings/subscription` | `GET`, `PATCH`<br>`GET` |
| **Notifications** | `core/widgets/admin_layout.dart` | `/notifications`<br>`/notifications/read-all` | `GET`<br>`POST` |

---

## 5. Running the Tests & Static Analysis

```bash
cd D:/PG_Management/pg-management-system/admin_app

# Run static analysis
flutter analyze

# Run all test suites
flutter test --concurrency=1
```
