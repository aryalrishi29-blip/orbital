# ╔══════════════════════════════════════════════════════════════╗
# ║  Multi-stage Dockerfile                                      ║
# ║  Stage 1 (builder) – install dependencies                    ║
# ║  Stage 2 (production) – lean runtime image, non-root user    ║
# ╚══════════════════════════════════════════════════════════════╝

# ── Stage 1: builder ─────────────────────────────────────────
FROM python:3.11-slim AS builder

WORKDIR /app

# Build-time OS deps (compiler + libpq headers for psycopg2)
RUN apt-get update && apt-get install -y --no-install-recommends \
        gcc \
        libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .

RUN pip install --upgrade pip \
 && pip install --prefix=/install --no-cache-dir -r requirements.txt


# ── Stage 2: production ───────────────────────────────────────
FROM python:3.11-slim AS production

# Non-root user — never run app code as root
RUN groupadd --system appgroup \
 && useradd  --system --gid appgroup --no-create-home appuser

WORKDIR /app

# Runtime OS deps only (libpq shared library)
RUN apt-get update && apt-get install -y --no-install-recommends \
        libpq5 \
    && rm -rf /var/lib/apt/lists/*

# Copy compiled packages from builder stage
COPY --from=builder /install /usr/local

# Copy application source (owned by appuser)
COPY --chown=appuser:appgroup . .

# Pre-compile static files into /app/staticfiles
# Uses a throwaway SQLite DB so no real Postgres is needed at build time
RUN DJANGO_SECRET_KEY=build-time-only \
    DATABASE_URL=sqlite:///tmp/build.db \
    python manage.py collectstatic --noinput --settings=myapp.settings_build

USER appuser

EXPOSE 8000

# Gunicorn: sync workers, sensible timeouts, structured logs to stdout
CMD ["gunicorn", \
     "--bind",         "0.0.0.0:8000", \
     "--workers",      "3", \
     "--worker-class", "sync", \
     "--timeout",      "30", \
     "--access-logfile",  "-", \
     "--error-logfile",   "-", \
     "--log-level",    "info", \
     "myapp.wsgi:application"]
