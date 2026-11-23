.PHONY: help setup db-up db-down migrate migration dev test lint audit jobs

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
