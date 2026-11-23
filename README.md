# Origin PG Management System

Software for running paying-guest (PG) properties: residents and online KYC, beds and rooms,
monthly rent, security deposits, expenses, complaints, food menu, announcements and
fingerprint-machine attendance. Used by the owner (admin app) and residents (resident app),
on the web (phone browser, installable) and as native apps, all against one API.

## Repository layout

```
apps/
  api/           FastAPI + PostgreSQL backend (the only backend)
  admin/         Flutter owner/admin app  (web + Android + iOS)     [frontend - pending design approval]
  resident/      Flutter resident app     (web + Android + iOS)     [frontend - pending design approval]
  checkout-web/  React payment-link page                            [payments untouched for now]
docs/            architecture.md, api-contract.md, database-schema.md, archive/ (old audit reports)
infra/           docker/ (local stack), render/ (deploy blueprint), vercel/ (web hosting config)
.github/         CI: lint, tests against Postgres, dependency audit
Makefile         common commands
```

## Run the backend locally

```bash
make setup      # venv + dependencies, copies apps/api/.env.example to .env
make db-up      # Postgres in Docker  (or use a local Postgres 16)
make migrate    # create the schema
make dev        # API on http://localhost:8000  (docs at /api/v1/docs in development)
make test       # full test suite (needs a Postgres database named pg_management_test)
```

In development the email provider is `MOCK`: OTP codes are printed in the API log.
`ENVIRONMENT` defaults to **production**; in production the API refuses to start without real
secrets (see `apps/api/.env.example`).

## Key rules implemented

- Rent only, no extra charges; one RENT invoice per resident per month, generated automatically.
- Security deposit ledger; on move-out **50% of the deposit is refunded** whatever the stay length
  (`DEPOSIT_REFUND_PERCENT`), unpaid dues/damages are taken from that share.
- Online KYC (Aadhaar + PAN, or passport) stored **encrypted at rest**, viewable only by the owning company.
- Fingerprint machine feeds `/api/v1/attendance/punches`; owners see who is in/out.

More: [docs/architecture.md](docs/architecture.md), [SECURITY.md](SECURITY.md).
