# PG Management System — Flutter Resident Mobile App Integration Setup Guide

## 1. Overview
The `resident_app` is a cross-platform Flutter application (Android, iOS, Web) designed for PG residents. It integrates directly with the PG Management System backend (`/api/v1`) for OTP-based passwordless authentication, real-time stay tracking, invoice breakdown, rent payments (UPI intent & demo payments), complaint tracking with multipart photo upload, weekly food menus, digital receipts, and property contact access.

---

## 2. Architecture & Core Network Layer

```text
resident_app/
├── lib/
│   ├── main.dart                                # Initializes TokenStorage and ThemeNotifier
│   ├── core/
│   │   ├── network/
│   │   │   ├── api_client.dart                  # Base HTTP client with multi-platform URL auto-detection
│   │   │   ├── api_exception.dart               # Structured exception handler
│   │   │   └── token_storage.dart               # Secure storage for JWT access token and user credentials
│   │   ├── services/
│   │   │   ├── resident_auth_service.dart       # OTP Request, OTP Verify, Logout, Me
│   │   │   ├── resident_api_service.dart        # 22 resident endpoints (dashboard, stay, bills, UPI, complaints)
│   │   │   └── payment_verification_service.dart # Payment state machine & polling helper
│   │   ├── data/
│   │   │   └── app_data.dart                    # AppState cache and persistent offline fallback
│   │   └── router/
│   │       └── app_router.dart                  # GoRouter with authentication guards
│   └── features/                                # Screen modules wired to ResidentApiService
```

### Multi-Platform Base URL Auto-Detection
`ApiClient` automatically determines the appropriate host based on runtime target:
- **Flutter Web / Desktop:** Defaults to `http://127.0.0.1:8000/api/v1`
- **Android Emulator:** Defaults to `http://10.0.2.2:8000/api/v1`
- **Physical Device:** Overridden using `--dart-define`:
```bash
# Physical Android / iOS device over local Wi-Fi:
flutter run --dart-define=API_BASE_URL=http://192.168.1.15:8000/api/v1

# Android Emulator:
flutter run -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1

# Flutter Web (Chrome):
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1
```

---

## 3. Resident Authentication Flow (Phone + Email OTP)

1. **Request OTP (`POST /api/v1/auth/resident/login/otp-request`):**
   - Resident enters their registered 10-digit phone number.
   - The backend validates the resident record, generates a secure 6-digit OTP, and dispatches it to their registered email address via SMTP.
   - The response returns `{"email_masked": "r***@originpg.com"}`.
   - The UI displays the masked email so the resident knows where to check for the code.
2. **Verify OTP (`POST /api/v1/auth/resident/login/otp-verify`):**
   - Resident submits phone and the 6-digit OTP.
   - Backend returns the JWT access token and user profile.
   - The token is securely saved in `TokenStorage`.
   - The resident is transitioned into `/home`.

---

## 4. Screen-to-API Mapping Summary

| Screen | File Path | Integrated Endpoint | Method |
|---|---|---|---|
| **Resident Login** | `features/auth/login_screen.dart` | `/auth/resident/login/otp-request`<br>`/auth/resident/login/otp-verify` | `POST`<br>`POST` |
| **Home Dashboard** | `features/home/home_screen.dart` | `/resident/dashboard` | `GET` |
| **Invoices & Bills** | `features/payments/payments_screen.dart` | `/resident/invoices`<br>`/resident/payments` | `GET`<br>`GET` |
| **Rent Payment** | `features/payments/rent_payment_screen.dart` | `/payments/requests` (UPI)<br>`/payments/demo/pay` (Demo Pay) | `POST`<br>`POST` |
| **Payment Status** | `features/payments/payment_status_screen.dart` | `/payments/requests/{id}` | `GET` |
| **Receipt Screen** | `features/payments/receipt_screen.dart` | `/resident/invoices/{id}` | `GET` |
| **Weekly Food Menu**| `features/food_menu/food_menu_screen.dart` | `/resident/food-menu` | `GET` |
| **Complaints List** | `features/complaints/complaints_screen.dart`<br>`all_complaints_screen.dart` | `/resident/complaints` | `GET` |
| **Raise Complaint** | `features/complaints/raise_complaint_screen.dart` | `/resident/complaints`<br>`/resident/complaints/upload-photo` | `POST`<br>`POST (multipart)` |
| **Resident Profile** | `features/profile/profile_screen.dart` | `/resident/profile` | `GET` |
| **Property Details**| `features/profile/property_details_screen.dart` | `/resident/property` | `GET` |
| **Call Management** | `features/profile/call_management_screen.dart` | `/resident/property-contacts` | `GET` |
| **Settings & Logout**| `features/profile/settings_screen.dart` | `/resident/settings`<br>`/auth/logout` | `GET`, `PATCH`<br>`POST` |
| **Notices** | `features/notices/notices_screen.dart` | `/notices` | `GET` |

---

## 5. Complaint Category Normalization
When a resident selects a category on `raise_complaint_screen.dart`, the client automatically normalizes the UI selection into one of the backend enum values:
- `Plumbing` / `Water Supply` $\to$ `PLUMBING`
- `Electrical` / `AC/Heater` / `Geyser` $\to$ `ELECTRICAL`
- `Wi-Fi/Internet` $\to$ `WIFI`
- `Housekeeping` / `Pest Control` $\to$ `CLEANING`
- `Food/Mess` $\to$ `FOOD`
- `Furniture` $\to$ `CARPENTRY`
- `Other` / `Noise` / `Security` / `Laundry` $\to$ `OTHER`

---

## 6. Running the Tests & Static Analysis

```bash
cd D:/PG_Management/pg-management-system/resident_app

# Run static analysis
flutter analyze

# Run all test suites
flutter test --concurrency=1
```
