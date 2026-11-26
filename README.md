# Origin Living · PG Management Platform

[![CI](https://github.com/origin028/PG-MANAGER/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/origin028/PG-MANAGER/actions/workflows/ci.yml)
[![Deploy API](https://github.com/origin028/PG-MANAGER/actions/workflows/deploy-api.yml/badge.svg)](https://github.com/origin028/PG-MANAGER/actions/workflows/deploy-api.yml)

Software for running paying-guest (PG) homes: residents and online KYC, rooms and beds, monthly rent,
security deposits, expenses, complaints, food menu and meal passes, announcements and attendance.
One app serves owners, residents and kitchen staff on iOS, Android and the web, all against a single API.

## Contents

- [Features](#features)
- [Architecture](#architecture)
- [Repository layout](#repository-layout)
- [Getting started](#getting-started)
- [Quality checks](#quality-checks)
- [CI/CD](#cicd)
- [Configuration](#configuration)
- [Deployment](#deployment)
- [Contributing](#contributing)
- [Security](#security)

## Features

| Owner | Resident | Kitchen |
|---|---|---|
| Dashboard across multiple PGs: occupancy, rent collected, items needing attention | Rent due countdown, pay by UPI, receipts | Today's menu and headcount |
| Add residents (they finish their own details and KYC); approvals with KYC review | Self sign-up via a PG's join QR code | Meal pass scanning |
| Rooms and beds, with free / full filters | Food menu with "now serving / up next" | |
| Dues with WhatsApp reminders and calls; confirm UPI payments by UTR | Report issues with photos and track status | |
| Expenses, finance reports, staff, leads, complaints, announcements | Deposit and stay details, announcements | |
| Automatic monthly invoices, rent reminders, KYC deadlines | Email/mobile sign-in, OTP password setup | |

Business rules worth knowing:

- One RENT invoice per resident per month, generated automatically; jobs are idempotent.
- Security deposit is an append-only ledger. On move-out **50% is refunded** (`DEPOSIT_REFUND_PERCENT`),
  less unpaid dues or damages.
- KYC documents are **encrypted at rest** and visible only to the owning company.
- If KYC is not verified by the deadline (default 7 days), the resident's access pauses automatically.

## Architecture

```
 iOS / Android / web app (apps/mobile)  ─┐
 Landing website (apps/web)             ─┼─ HTTPS ─▶  FastAPI (apps/api) ─▶ PostgreSQL 16
 Payment page (apps/checkout-web)       ─┘                  │
                                                            ├─▶ Encrypted file storage (KYC, photos)
 Scheduler ─▶ monthly invoices · reminders · KYC deadlines ─┤
                                                            └─▶ SMTP email · Expo push notifications
```

| Layer | Technology |
|---|---|
| API | Python 3.14, FastAPI, SQLAlchemy 2, Alembic, Pydantic |
| Database | PostgreSQL 16 |
| App | Expo SDK 58, React Native 0.88, expo-router, TypeScript |
| Landing site | Next.js 16, Tailwind CSS 4 |
| Hosting | Google Cloud Run + Cloud SQL (API), Vercel (websites) |

More detail: [docs/architecture.md](docs/architecture.md), [docs/api-contract.md](docs/api-contract.md),
[docs/database-schema.md](docs/database-schema.md).

## Repository layout

```
apps/
  api/            FastAPI backend: the only backend
  mobile/         Expo app for owners, residents and kitchen (iOS, Android, web)
  web/            Next.js landing website and enquiry form
  checkout-web/   React payment-link page
  admin/          Legacy Flutter owner app (superseded by apps/mobile, not deployed)
  resident/       Legacy Flutter resident app (superseded by apps/mobile, not deployed)
packages/
  api-client/     Typed API client generated from docs/openapi.json
docs/             Deployment guide, architecture, API contract, database schema
infra/
  docker/         Local PostgreSQL (docker compose)
  firebase/       One-shot Google Cloud setup and deploy script
  render/         Alternative Render blueprint
.github/          CI, API deployment, Dependabot, PR template
Makefile          Common commands
```

## Getting started

**Prerequisites:** Python 3.12+, Node.js 22, Docker (or a local PostgreSQL 16).

```bash
# 1. Backend
make setup        # virtualenv + dependencies; copies apps/api/.env.example to apps/api/.env
make db-up        # PostgreSQL in Docker
make migrate      # create the schema
make dev          # API on http://localhost:8000 (Swagger at /api/v1/docs)

# 2. App (new terminal)
cd apps/mobile && npm install && cd ../..
make app          # press w for web, i for the iOS simulator, or scan the QR with Expo Go
```

In development the email provider is `MOCK`: OTP codes are printed in the API log.
To try the app with sample data, seed the local demo database:

```bash
cd apps/api && .venv/bin/python scripts/seed_demo_pg_data.py && .venv/bin/python scripts/seed_demo_extras.py
```

Demo logins (local only; the seed scripts refuse to run in production):

| Role | Login | Password |
|---|---|---|
| Owner | `admin` | `admin` |
| Resident | `0000000000` | `0000000000` |
| Kitchen | `kitchen` | `kitchen` |

Landing website: `npm install && npm run dev -w @pg/web` (http://localhost:3000).

## Quality checks

```bash
make check        # everything CI runs, in one command
```

| Command | What it does |
|---|---|
| `make lint` | Ruff static checks on the API |
| `make test` | API test suite against PostgreSQL (~440 tests, includes migration drift check) |
| `make audit` | Known-vulnerability scan of Python dependencies |
| `make app-check` | App typecheck, lint and production web build |
| `make web-check` | Landing site lint and production build |
| `make checkout-check` | Payment page tests and build |

## CI/CD

| Workflow | Trigger | What it does |
|---|---|---|
| [`ci.yml`](.github/workflows/ci.yml) | Every pull request and push to `main` | API lint, tests on PostgreSQL 16, dependency audit, Docker image build; app typecheck, lint, web build; landing site build; payment page tests. Pull requests run only the parts that changed. `CI passed` is the single required check. |
| [`deploy-api.yml`](.github/workflows/deploy-api.yml) | CI green on `main`, or manual | Builds the API image, pushes it to Artifact Registry, runs migrations, deploys Cloud Run, updates scheduled jobs, then smoke-tests `/api/v1/health`. Inactive until the GCP variables below are set. |
| Vercel Git integration | Every push | Preview deployment for each pull request, production deployment from `main` for `apps/mobile` and `apps/web`. |
| [Dependabot](.github/dependabot.yml) | Weekly / monthly | Grouped dependency updates for Python, npm, Docker and GitHub Actions. |

**Enabling API deployment.** Run `infra/firebase/deploy.sh` once to create the Google Cloud resources, then
add these repository variables (Settings → Secrets and variables → Actions → Variables):

| Variable | Example |
|---|---|
| `GCP_PROJECT` | `originpg` |
| `GCP_REGION` | `asia-south1` |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | `projects/123/locations/global/workloadIdentityPools/github/providers/github` |
| `GCP_DEPLOY_SERVICE_ACCOUNT` | `deployer@originpg.iam.gserviceaccount.com` |

Authentication uses Workload Identity Federation, so no long-lived keys are stored in GitHub.
Protect the `production` environment with required reviewers to add a manual approval step.

**Recommended branch protection for `main`:** require pull requests, require the `CI passed` check, block force pushes.

## Configuration

| Where | Variable | Purpose |
|---|---|---|
| API | see [`apps/api/.env.example`](apps/api/.env.example) | Database, secrets, SMTP, CORS, storage. In production the API refuses to start if a secret is missing or weak. |
| App (`apps/mobile`) | `EXPO_PUBLIC_API_URL` | API address, baked in at build time |
| | `EXPO_PUBLIC_APP_URL` | Public address of the web app (used in join QR links) |
| | `EXPO_PUBLIC_DEMO` | `1` runs the app on built-in sample data with no backend (temporary; see [apps/mobile/src/demo/README.md](apps/mobile/src/demo/README.md)) |
| Landing (`apps/web`) | `NEXT_PUBLIC_API_URL`, `NEXT_PUBLIC_APP_URL` | API and app addresses |

`ENVIRONMENT` defaults to **production**. Never commit `.env` files; only `.env.example` templates are tracked.

## Deployment

Step-by-step guide: **[docs/DEPLOY.md](docs/DEPLOY.md)**.

| Piece | Host | Root directory |
|---|---|---|
| API, database, scheduled jobs | Google Cloud Run + Cloud SQL (`asia-south1`) | `apps/api` |
| Owner / resident web app | Vercel | `apps/mobile` |
| Landing website | Vercel | `apps/web` |
| Phone apps | EAS Build → App Store / Play Store | `apps/mobile` |

## Contributing

1. Branch from `main`: `feat/…`, `fix/…`, `chore/…`.
2. Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/) (`feat(api): …`, `fix(mobile): …`).
3. Database changes need an Alembic migration: `make migration m="describe the change"`.
4. In `apps/mobile`, add packages with `npx expo install <pkg>` so versions match the Expo SDK.
5. Run `make check`, open a pull request, fill in the template, and wait for `CI passed` and one review.

## Security

See [SECURITY.md](SECURITY.md) for the security model and how to report a vulnerability.

## License

[Boost Software License 1.0](LICENSE)
