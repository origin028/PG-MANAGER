# PG Management System — Production Deployment Audit Report

**Date:** 2026-11-21  
**Project Root:** `D:\PG_Management`  
**Git Branch:** `main`  
**Git Remote:** `https://github.com/origin028/PG-MANAGER.git`  
**Target Environment:** Production Cloud (Render / Railway / Vercel / Android Release)

---

## 1. Executive Summary

A comprehensive architectural and deployment audit was conducted across the entire **PG Management System** repository. The system consists of:
1. **Unified Backend API:** FastAPI application running Python 3.12 with PostgreSQL (Psycopg 3) and SQLAlchemy 2.0 ORM.
2. **Admin Application:** Cross-platform Flutter application providing both **Admin Web** (to be hosted on Vercel) and **Admin Android APK**.
3. **Resident Mobile Application:** Flutter Android application providing **Resident Android APK** with UPI and self-service features.
4. **Relational Database:** PostgreSQL with Alembic migration version control.

All three core applications are fully functional, tests pass cleanly, and the codebase is ready for production containerization, cloud deployment, and signed APK generation.

---

## 2. Component Audit Matrix

| Component | Framework / Tech | Directory Location | Primary Entry Point | Production Target |
| :--- | :--- | :--- | :--- | :--- |
| **Backend API** | FastAPI 0.115+, Python 3.12, Uvicorn | `pg-management-system/backend` | `app.main:app` | Render / Cloud Container |
| **Database** | PostgreSQL, Psycopg 3, SQLAlchemy 2.0 | `pg-management-system/backend/migrations` | Head: `b8c9d0e1f2a3` | Managed Cloud PostgreSQL |
| **Admin Web App** | Flutter 3.47.4 (Web), GoRouter | `pg-management-system/admin_app` | `lib/main.dart` -> `web/` | Vercel (SPA Rewrite) |
| **Admin Android APK**| Flutter 3.47.4 (Android), Kotlin 1.9+ | `pg-management-system/admin_app` | `android/app/build.gradle.kts` | Release APK (`com.originpg.admin`) |
| **Resident Android APK**| Flutter 3.47.4 (Android), UPI Intents | `pg-management-system/resident_app` | `android/app/build.gradle.kts` | Release APK (`com.originpg.resident`) |

---

## 3. Backend Architecture Audit

### 3.1 Application Entry Point & Lifespan
- **File:** `pg-management-system/backend/app/main.py`
- **ASGI Instance:** `app = FastAPI(...)` exported as `app.main:app`.
- **Startup Command:** `uvicorn app.main:app --host 0.0.0.0 --port $PORT --workers 4 --proxy-headers --forwarded-allow-ips=*`
- **Lifecycle Management:** Uses modern `lifespan` context manager handling structured logging, startup checks, and graceful shutdown.

### 3.2 Database & Connection Pooling
- **ORM & Driver:** SQLAlchemy 2.0 with Psycopg 3 (`postgresql+psycopg://`).
- **Connection Pool Configuration (`app/db/session.py`):**
  - `pool_size = 10`
  - `max_overflow = 20`
  - `pool_timeout = 30` seconds
  - `pool_recycle = 1800` seconds (prevents stale connections dropped by cloud proxies)
  - `pool_pre_ping = True` (detects disconnected connections before checkout)
- **Database Safety Guard:** `enforce_test_database_safety` automatically redirects to `pg_management_test` only in development/test mode, guaranteeing production connections are never polluted by tests.

### 3.3 Alembic Migrations
- **Configuration:** `alembic.ini` and `migrations/env.py`.
- **Current Database Revision:** `b8c9d0e1f2a3` (head).
- **Target Head Revision:** `b8c9d0e1f2a3` (`add_company_bed_limit_and_bed_is_deleted`).
- **Migration Consistency:** Single linear history across 12 revisions with zero branch divergence and zero conflicts.

### 3.4 Health Check Endpoints
- `GET /api/v1/health`: Evaluates PostgreSQL ping (`SELECT 1`) and reports detailed status.
- `GET /api/v1/health/live`: Lightweight process liveness probe.
- `GET /api/v1/health/ready`: Database pool readiness probe for cloud load balancers.

### 3.5 Security, Authentication & Secrets
- **Admin Authentication:** Email and password with bcrypt encryption, direct JWT access tokens (60 min) and refresh tokens (30 days). Registration secured via `ADMIN_REGISTRATION_SUPER_KEY`.
- **Resident Authentication:** Mobile/Email lookup with 6-digit numeric OTP with 5-minute expiry, rate limiting, and brute-force protection.
- **Environment Secrets:** Handled strictly via Pydantic `BaseSettings` (`app/core/config.py`). Zero hardcoded secrets committed to version control.

### 3.6 Payment Gateways & UPI
- **Direct UPI Intent:** PhonePe, Google Pay, Paytm, and BHIM direct intent queries configured in `AndroidManifest.xml`.
- **Merchant Details:** VPA `9886699258-3@ybl` (SMART GROUP PG'S, Bank of Baroda).
- **Testing Verification:** Safe ₹1 test invoice endpoint (`POST /api/v1/payments/create-test-invoice`) enables real-money end-to-end payment verification in production.

---

## 4. Frontend & Mobile Apps Audit

### 4.1 API Base URL Configuration Strategy
Both `admin_app` and `resident_app` implement `ApiClient.baseUrl` utilizing Dart compile-time environment flags:
```dart
static const String _envBaseUrl = String.fromEnvironment('API_BASE_URL');
```
When building production targets, passing:
`--dart-define=API_BASE_URL=https://<production-backend-domain>/api/v1`
dynamically compiles the production HTTPS endpoint into the application binary, completely eliminating hardcoded localhost or private IP addresses.

### 4.2 Admin Web Application (Vercel)
- **Directory:** `pg-management-system/admin_app`
- **Single Page App Routing:** Utilizes `go_router`. To prevent 404 errors on deep linking or browser refresh on Vercel, a `vercel.json` rewrite rule routing `/(.*)` to `/index.html` is required.
- **CORS Prerequisite:** Backend `CORS_ORIGINS` must allow the Vercel deployment URL.

### 4.3 Android Release Signing
Both `admin_app` and `resident_app` have:
- `android/key.properties` configured.
- `android/app/upload-keystore.jks` in place.
- `build.gradle.kts` release signing configured to read `key.properties`.

