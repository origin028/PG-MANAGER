# Origin PG Management System

A multi-property PG Management System designed for operators managing approximately 5–6 PG properties.

## Architecture Overview

The system architecture consists of unified client experiences sharing one FastAPI backend API and PostgreSQL database:

### Client Applications
1. **Admin Web Panel** (Flutter Web) — Full property, resident, financial, complaint, staff, and report management for owners and managers.
2. **Admin Mobile App** (Flutter Android) — Mobile-optimized operational companion for owners, property managers, and wardens/staff.
3. **Resident Mobile App** (Flutter Android) — Dedicated self-service app for paying guests (rent due, payment history, downloadable receipts, complaints, notices).
4. **Resident Web Checkout Portal** (`frontend/` — React 18 / Vite 6) — Lightweight, responsive zero-install web checkout portal for payment links sent via WhatsApp (`/pay/:token`). Allows residents to review rent breakdown and pay securely via Razorpay on any mobile browser without requiring app installation. In deployments using relative API URLs, the reverse proxy must route `/api` requests to the FastAPI backend.

### Server & Storage
5. **Shared Backend API** (`backend/` — Python 3.12 / FastAPI) — High-performance REST API, role-based authorization, payment reservation/idempotency, webhook verification, receipt outbox, and integrations.
6. **Relational Database** (PostgreSQL 16+) — Strongly typed ACID ledger, foreign key constraints, and property-scoped isolation.

## Directory Structure

```text
pg-management-system/
├── backend/          # FastAPI backend application, PostgreSQL models, migrations, tests
├── frontend/         # React/Vite zero-install resident web checkout application for payment links
├── docs/             # Product specifications, database schemas, API contracts, checklists
└── README.md         # This documentation file
```

## Quick Navigation

- [Backend Documentation & Setup Guide](backend/README.md)
- [Database Schema Reference](docs/database-schema.md)
- [API Contract for Flutter Development](docs/api-contract.md)
- [Testing & Quality Assurance Checklist](docs/testing-checklist.md)
