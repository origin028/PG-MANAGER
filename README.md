# Origin PG Management System — Shared Backend API

Production-ready backend API and database architecture for managing 5–6 PG properties across:
- **Admin Web Panel** (Flutter Web)
- **Admin Mobile App** (Flutter Android)
- **Resident Mobile App** (Flutter Android)

---

## 1. Approved Architecture & Tech Stack

| Component | Technology | Version | Purpose |
| :--- | :--- | :--- | :--- |
| **Language** | Python | 3.12+ | Core runtime |
| **Web Framework**| FastAPI | 0.115+ | High-performance asynchronous REST API |
| **Database** | PostgreSQL | 16+ | ACID relational storage, multi-tenancy & audit trails |
| **DB Driver** | Psycopg 3 | 3.2+ | Native high-efficiency PostgreSQL binary driver |
| **ORM** | SQLAlchemy | 2.0+ | Modern typed mapping (`Mapped`, `mapped_column`) |
| **Migrations** | Alembic | 1.13+ | Version-controlled schema migrations |
| **Validation** | Pydantic & Pydantic-Settings | 2.8+ | Strongly-typed payload & configuration validation |
| **Security** | PyJWT & Bcrypt | 2.9+, 4.0+ | JWT tokens, refresh rotation, and 12-round bcrypt hashing |

---

## 2. Phase 1 Deliverables Summary (23–24 October)

- [x] **API Skeleton & Versioning**: `/api/v1` structured with modular routing, middleware, CORS, logging, and unified JSON response envelopes.
- [x] **Database Schema & Migrations**: Configured Alembic with `001_initial_auth_and_properties` migration for:
  - `companies`
  - `roles`
  - `properties` (multi-property foundation supporting 5–6 properties)
  - `users`
  - `user_property_access` (junction table for scoped property permissions)
  - `refresh_tokens` (secure rotation & revocation blacklist)
  - `audit_logs` (security and sensitive action tracking)
- [x] **Authentication & Client Isolation**:
  - JWT Access Token (60 mins) & Refresh Token (30 days).
  - Multi-client role verification: `admin_web`, `admin_mobile`, `resident_mobile`.
  - Residents are blocked from Admin experiences (`403 Forbidden`).
  - Admins are blocked from Resident mobile app (`403 Forbidden`).
- [x] **Property-Level Permissions**:
  - Super Admin has portfolio-wide access across all properties.
  - Property Managers & Staff are scoped strictly to their assigned properties.
- [x] **Database Seeder**: Realistic initial data creating Origin company, 4 roles, 5 PG properties in Bangalore, and 4 test accounts ready for immediate frontend testing.
- [x] **Frontend API Contract**: Complete documentation in `API_CONTRACT_PHASE1.md`.
- [x] **Automated Pytest Suite**: 26 unit and integration tests passing at 100%.

---

## 3. Quickstart & Local Setup

### 3.1 Prerequisites
- Python 3.12+ installed
- PostgreSQL (or local SQLite for zero-config testing)

### 3.2 Virtual Environment & Dependencies
```powershell
# Create virtual environment
python -m venv .venv

# Activate virtual environment
.\.venv\Scripts\Activate.ps1

# Install requirements
pip install -r requirements.txt
```

### 3.3 Configure Environment Variables
Copy `.env.example` to `.env`:
```powershell
Copy-Item .env.example .env
```

For PostgreSQL with Psycopg 3:
```env
DATABASE_URL=postgresql+psycopg://postgres:postgres@localhost:5432/pg_management_db
```

For SQLite local development:
```env
DATABASE_URL=sqlite:///./pg_management.db
```

### 3.4 Run Database Migrations & Seeder
```powershell
# Run Alembic migrations
alembic upgrade head

# Seed Company, Roles, 5 Properties, and Test Users
python -m app.db.seed
```

### 3.5 Start the Development Server
```powershell
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

- API Base: `http://localhost:8000/api/v1`
- Swagger UI: `http://localhost:8000/api/v1/docs`
- ReDoc: `http://localhost:8000/api/v1/redoc`

### 3.6 Run the Test Suite
```powershell
pytest -v
```

---

## 4. Seeded Test Credentials

| Role | Email / Phone | Password | Target Flutter Client | Accessible Properties |
| :--- | :--- | :--- | :--- | :--- |
| **Super Admin** | `admin@originpg.com` / `9876543210` | `Admin@123456` | Admin Web / Admin Android | All 5 PG properties |
| **Property Manager** | `manager@originpg.com` / `9876543211` | `Manager@123456` | Admin Web / Admin Android | Koramangala, HSR Layout |
| **Staff / Warden** | `staff@originpg.com` / `9876543212` | `Staff@123456` | Admin Android / Admin Web | Koramangala |
| **Resident** | `resident@originpg.com` / `9876543213` | `Resident@123456` | Resident Android ONLY | Koramangala |

---

## 5. Project Directory Structure

```text
PG_Management/
├── .env.example              # Template environment configuration
├── .env                      # Active environment configuration
├── .gitignore                # Git ignore rules
├── alembic.ini               # Alembic migration configuration
├── requirements.txt          # Python dependency specifications
├── pytest.ini                # Pytest configuration
├── README.md                 # Project & architecture guide
├── API_CONTRACT_PHASE1.md    # Frontend Flutter contract documentation
├── alembic/
│   ├── env.py                # Alembic migration environment with SQLAlchemy 2.0
│   └── versions/             # Migration version files
├── app/
│   ├── main.py               # FastAPI entrypoint, middleware & exception handlers
│   ├── core/
│   │   ├── config.py         # App settings via pydantic-settings
│   │   ├── security.py       # Bcrypt hashing & PyJWT token management
│   │   ├── exceptions.py     # Custom error hierarchy
│   │   └── logging.py        # Centralized logging
│   ├── db/
│   │   ├── base.py           # DeclarativeBase, UUIDMixin, TimestampMixin
│   │   ├── session.py        # SQLAlchemy 2.0 Engine & SessionLocal
│   │   └── seed.py           # Data seeder for Phase 1
│   ├── models/
│   │   ├── company.py        # Company entity
│   │   ├── role.py           # Role & permissions
│   │   ├── property.py       # PG Property entity (portfolio of 5-6 properties)
│   │   ├── user.py           # User, UserPropertyAccess, RefreshToken
│   │   └── audit_log.py      # Audit log entity
│   ├── schemas/
│   │   ├── common.py         # Standard API response envelope & pagination
│   │   ├── auth.py           # Login, token response, password change schemas
│   │   ├── user.py           # User profiles & creation schemas
│   │   ├── property.py       # Property summaries & detail schemas
│   │   ├── role.py           # Role schemas
│   │   └── audit.py          # Audit log schemas
│   ├── services/
│   │   ├── auth_service.py   # Auth, client validation & token lifecycle
│   │   ├── user_service.py   # User management
│   │   ├── property_service.py# Property scoping & access rules
│   │   └── audit_service.py  # Audit logging service
│   └── api/
│       ├── deps.py           # FastAPI dependencies (auth, roles, property scoping)
│       └── v1/
│           ├── router.py     # Aggregated v1 router
│           └── endpoints/    # health, auth, properties, users, audit-logs
└── tests/
    ├── conftest.py           # Test fixtures & in-memory test database
    ├── test_health.py        # Health endpoint tests
    ├── test_auth.py          # Authentication & client validation tests
    ├── test_roles_and_scopes.py # RBAC & property scoping tests
    └── test_audit_logs.py    # Audit logging tests
```
