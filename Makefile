.PHONY: help setup db-up db-down migrate migration dev test lint audit jobs app app-check web-check checkout-check check

API = apps/api

help:
	@echo "make setup      create venv + install dev dependencies"
	@echo "make db-up      start local Postgres (docker compose)"
	@echo "make migrate    apply database migrations"
	@echo "make migration m='message'   autogenerate a new migration"
	@echo "make dev        run the API with reload on :8000"
	@echo "make test       run the full backend test suite"
	@echo "make lint       ruff static checks"
	@echo "make audit      scan dependencies for known vulnerabilities"
	@echo "make jobs       run monthly invoicing + reminders once (local)"
	@echo "make app        run the Expo app (press w for web, i for iOS)"
	@echo "make check      run every CI check locally (API, app, website, payment page)"

setup:
	python3 -m venv $(API)/.venv
	$(API)/.venv/bin/pip install -q -r $(API)/requirements-dev.txt
	@test -f $(API)/.env || cp $(API)/.env.example $(API)/.env

db-up:
	docker compose -f infra/docker/docker-compose.yml up -d db

db-down:
	docker compose -f infra/docker/docker-compose.yml down

migrate:
	cd $(API) && .venv/bin/alembic upgrade head

migration:
	cd $(API) && .venv/bin/alembic revision --autogenerate -m "$(m)"

dev:
	cd $(API) && .venv/bin/uvicorn app.main:app --reload --port 8000

test:
	cd $(API) && .venv/bin/python -m pytest -q -p no:warnings

lint:
	cd $(API) && .venv/bin/ruff check app tests

audit:
	cd $(API) && .venv/bin/pip-audit -r requirements.txt

jobs:
	cd $(API) && .venv/bin/python -m app.tasks.run monthly-invoices && .venv/bin/python -m app.tasks.run reminders

app:
	cd apps/mobile && EXPO_PUBLIC_API_URL=$${EXPO_PUBLIC_API_URL:-http://localhost:8000} npx expo start

app-check:
	cd apps/mobile && npm run typecheck && npm run lint && EXPO_PUBLIC_API_URL=https://api.example.invalid npx expo export -p web --output-dir dist

web-check:
	npm run lint -w @pg/web && npm run build -w @pg/web

checkout-check:
	cd apps/checkout-web && npm test && npm run build

check: lint test audit app-check web-check checkout-check
	@echo "All checks passed."
