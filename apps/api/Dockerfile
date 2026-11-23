# Origin PG Management API - production image.
FROM python:3.14-slim-bookworm AS builder
WORKDIR /build
COPY requirements.txt .
RUN python -m venv /opt/venv && /opt/venv/bin/pip install --no-cache-dir --upgrade pip \
    && /opt/venv/bin/pip install --no-cache-dir -r requirements.txt

FROM python:3.14-slim-bookworm AS runner
RUN groupadd -g 10001 app && useradd -u 10001 -g app -m app \
    && apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH" PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 \
    ENVIRONMENT=production DEBUG=false PORT=8000
COPY --chown=app:app alembic.ini .
COPY --chown=app:app migrations/ migrations/
COPY --chown=app:app app/ app/
COPY --chown=app:app scripts/ scripts/
# Encrypted KYC files live here; mount a persistent volume at /app/uploads in production.
RUN mkdir -p /app/uploads/kyc && chown -R app:app /app/uploads
USER app
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD curl -fs http://localhost:${PORT}/api/v1/health/live || exit 1
# One process: rate limiting and lockout are in-process (sized for a single PG business).
# FORWARDED_ALLOW_IPS (read by uvicorn) must be set to the load balancer's address(es).
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT} --proxy-headers"]
