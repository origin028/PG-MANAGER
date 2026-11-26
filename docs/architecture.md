# Architecture

**Scale target:** up to ~800 residents, 4 properties, one owner organisation. One API instance, one Postgres.

```
Phone browser / installed app  ->  HTTPS  ->  FastAPI (apps/api)  ->  PostgreSQL
(Expo app: apps/mobile)                          |        |-> encrypted KYC files (private bucket)
Fingerprint bridge  -- X-Device-Key -->          |        |-> SMTP (OTP, reminders)
Scheduler    ->  python -m app.tasks.run  ------>+
```

## Backend (`apps/api/app`)
- `api/v1/endpoints/` thin HTTP layer; `services/` business logic; `repositories/` data access;
  `models/` SQLAlchemy; `schemas/` Pydantic; `core/` settings, security, crypto, rate limit, middleware;
  `integrations/` email (SMTP), payment gateway, storage; `tasks/` scheduled jobs.
- Tenancy: every resource belongs to a `company`; property access is checked by `verify_property_access`.
- Migrations: one Alembic chain in `migrations/`, applied as a release step (`alembic upgrade head`),
  never at app start. CI fails if models and migrations diverge.

## Data rules
- Money: `NUMERIC(10,2)` / `Decimal`, rounded half-up to paise.
- Deposit: append-only `deposit_ledger` (RECEIVED, FORFEITED, DEDUCTED, REFUNDED); balance = sum.
- Invoices: unique per (resident, month, type), so jobs are idempotent.

## Two ways to use it (phone or app)
One Expo app (`apps/mobile`) serves owners, residents and kitchen staff. It builds for the **web**
(any phone browser, deployed on Vercel) and **native** iOS/Android (EAS Build) from one codebase,
calling the same API. No separate mobile backend. The older Flutter apps (`apps/admin`, `apps/resident`)
are superseded and not deployed.

## Decisions
1. Stay on PostgreSQL (relational money rules); not Firestore.
2. Single process + cron jobs instead of Celery/Redis (sized for this load).
3. SMTP for email (Gmail/Workspace), one provider.
4. KYC on an encrypted persistent disk now; object storage (R2/S3) behind `integrations/storage.py` if volume grows.
