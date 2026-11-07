# ==============================================================================
# Origin PG Management System — Production Backend Dockerfile
# Multi-stage container build targeting Python 3.12 on Debian Slim
# ==============================================================================

FROM python:3.12-slim-bookworm AS builder

WORKDIR /build

# Install security updates and build requirements
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy dependency definition
COPY requirements.txt .

# Install dependencies into virtualenv
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt


# ==============================================================================
# Final Production Runtime Stage
# ==============================================================================
FROM python:3.12-slim-bookworm AS runner

# Security: Create non-privileged service user
RUN groupadd -g 10001 appgroup && \
    useradd -u 10001 -g appgroup -s /bin/bash -m appuser

# Install minimal runtime dependencies (curl for container healthcheck)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy virtualenv from builder stage
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    ENVIRONMENT=production \
    DEBUG=false

# Copy application source code and migrations
COPY --chown=appuser:appgroup alembic.ini .
COPY --chown=appuser:appgroup migrations/ migrations/
COPY --chown=appuser:appgroup app/ app/

# Create and set permissions for uploads directory
RUN mkdir -p /app/uploads && chown -R appuser:appgroup /app/uploads

# Drop privileges to non-root user
USER appuser

# Expose HTTP port
EXPOSE 8000

# Docker Healthcheck targeting the readiness probe
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8000/api/v1/health/ready || exit 1

# Production command: Run Uvicorn with proxy headers and multi-worker execution
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "4", "--proxy-headers", "--forwarded-allow-ips=*"]

