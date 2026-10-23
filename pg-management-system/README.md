# Origin PG Management System

A multi-property PG Management System designed for operators managing approximately 5–6 PG properties.

## Architecture Overview

The system consists of three client experiences sharing one unified backend API and a single PostgreSQL database:

1. **Admin Web Panel** (Flutter Web) — Full property, resident, financial, complaint, staff, and report management for owners and managers.
2. **Admin Mobile App** (Flutter Android) — Mobile-optimized operational companion for owners, property managers, and wardens/staff.
3. **Resident Mobile App** (Flutter Android) — Self-service app for paying guests (rent due, online payments, downloadable receipts, complaints, notices).
4. **Shared Backend API** (Python 3 / FastAPI) — Server-side business logic, role-based authorization, idempotency, audit trail, and integrations.
5. **Relational Database** (PostgreSQL 16+) — Strongly typed ACID ledger, foreign key constraints, and property-scoped isolation.

## Directory Structure

```text
pg-management-system/
├── backend/          # FastAPI backend application, PostgreSQL models, migrations, tests
├── docs/             # Product specifications, database schemas, API contracts, checklists
└── README.md         # This documentation file
```

## Quick Navigation

- [Backend Documentation & Setup Guide](backend/README.md)
- [Database Schema Reference](docs/database-schema.md)
- [API Contract for Flutter Development](docs/api-contract.md)
- [Testing & Quality Assurance Checklist](docs/testing-checklist.md)
