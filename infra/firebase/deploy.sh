#!/usr/bin/env bash
# Deploys the API to the Firebase / Google Cloud project: Cloud Run (API + jobs), Cloud SQL (PostgreSQL 16),
# a private Storage bucket (encrypted KYC/photos), Secret Manager and Cloud Scheduler.
# Safe to re-run: existing resources are kept, generated secrets are created once and never printed.
#
#   gcloud auth login <account that owns the Firebase project>      (once)
#   SMTP_HOST=smtp.gmail.com SMTP_PORT=587 SMTP_USERNAME=... SMTP_PASSWORD=... SMTP_FROM_EMAIL=... \
#   CORS_ORIGINS="https://<web app>,https://<landing site>" APP_URL="https://<web app>" \
#   [EXTERNAL_DATABASE_URL="postgresql+psycopg://...?...sslmode=require"]   (free Postgres; skips paid Cloud SQL) \
#   [OWNER_COMPANY="Origin Living" OWNER_EMAIL=... OWNER_PHONE=... OWNER_NAME=... OWNER_PASSWORD=... [OWNER_TEMP_WEAK=1]] \
#   bash infra/firebase/deploy.sh
#
# The production database starts EMPTY (no demo data; the demo seed scripts refuse to run in production).
set -euo pipefail

PROJECT="${PROJECT:-originpg}"
REGION="${REGION:-asia-south1}"            # Mumbai
SQL_INSTANCE="${SQL_INSTANCE:-pg-db}"
SQL_TIER="${SQL_TIER:-db-f1-micro}"        # smallest; upgrade later: gcloud sql instances patch pg-db --tier db-g1-small
DB_NAME="pg_management"
DB_USER="pgapp"
BUCKET="${BUCKET:-${PROJECT}-pg-files}"
SERVICE="pg-api"
SA_NAME="pg-api"
REPO="pg"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TAG="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || date +%s)"
IMAGE="${REGION}-docker.pkg.dev/${PROJECT}/${REPO}/api:${TAG}"
SA="${SA_NAME}@${PROJECT}.iam.gserviceaccount.com"
CONN="${PROJECT}:${REGION}:${SQL_INSTANCE}"

say() { printf "\n==> %s\n" "$*"; }
need() { [ -n "${!1:-}" ] || { echo "Missing $1 (see the top of this script)."; exit 1; }; }
for v in SMTP_HOST SMTP_PORT SMTP_USERNAME SMTP_PASSWORD SMTP_FROM_EMAIL CORS_ORIGINS APP_URL; do need "$v"; done

gcloud config set project "$PROJECT" >/dev/null

say "Enabling Google Cloud services"
gcloud services enable run.googleapis.com sqladmin.googleapis.com secretmanager.googleapis.com \
  cloudscheduler.googleapis.com artifactregistry.googleapis.com cloudbuild.googleapis.com storage.googleapis.com iam.googleapis.com

say "Container registry"
gcloud artifacts repositories describe "$REPO" --location "$REGION" >/dev/null 2>&1 || \
  gcloud artifacts repositories create "$REPO" --repository-format=docker --location "$REGION" --description "PG API images"

say "Service account for the API"
gcloud iam service-accounts describe "$SA" >/dev/null 2>&1 || \
  gcloud iam service-accounts create "$SA_NAME" --display-name "PG API (Cloud Run)"
for role in roles/cloudsql.client roles/secretmanager.secretAccessor; do
  gcloud projects add-iam-policy-binding "$PROJECT" --member "serviceAccount:$SA" --role "$role" --condition=None >/dev/null
done

say "Private bucket for encrypted KYC and photos"
gcloud storage buckets describe "gs://$BUCKET" >/dev/null 2>&1 || \
  gcloud storage buckets create "gs://$BUCKET" --location "$REGION" --uniform-bucket-level-access --public-access-prevention
gcloud storage buckets add-iam-policy-binding "gs://$BUCKET" --member "serviceAccount:$SA" --role roles/storage.objectAdmin >/dev/null

# Database: EXTERNAL_DATABASE_URL (free Supabase/Neon Postgres, ~₹0) or Cloud SQL (~₹800-1,000/month).
if [ -z "${EXTERNAL_DATABASE_URL:-}" ]; then
say "PostgreSQL 16 (Cloud SQL). The first creation takes about 10 minutes"
gcloud sql instances describe "$SQL_INSTANCE" >/dev/null 2>&1 || \
  gcloud sql instances create "$SQL_INSTANCE" --database-version POSTGRES_16 --edition ENTERPRISE --tier "$SQL_TIER" \
    --region "$REGION" --storage-size 10 --storage-auto-increase --backup-start-time 20:30 --retained-backups-count 14
gcloud sql databases describe "$DB_NAME" --instance "$SQL_INSTANCE" >/dev/null 2>&1 || \
  gcloud sql databases create "$DB_NAME" --instance "$SQL_INSTANCE"
fi

# Secrets: generated once (or taken from the environment for SMTP / owner password); never echoed.
put_secret() { # name value [update]
  if gcloud secrets describe "$1" >/dev/null 2>&1; then
    if [ "${3:-}" = "update" ]; then printf "%s" "$2" | gcloud secrets versions add "$1" --data-file=- >/dev/null; fi
  else
    printf "%s" "$2" | gcloud secrets create "$1" --replication-policy automatic --data-file=- >/dev/null
  fi
}
rand() { python3 -c "import secrets;print(secrets.token_urlsafe($1))"; }
say "Secrets"
if [ -n "${EXTERNAL_DATABASE_URL:-}" ]; then
  put_secret DATABASE_URL "$EXTERNAL_DATABASE_URL" update
elif ! gcloud secrets describe DB_PASSWORD >/dev/null 2>&1; then
  DB_PASS="$(rand 32)"
  put_secret DB_PASSWORD "$DB_PASS"
  gcloud sql users create "$DB_USER" --instance "$SQL_INSTANCE" --password "$DB_PASS" >/dev/null
  put_secret DATABASE_URL "postgresql+psycopg://${DB_USER}:${DB_PASS}@/${DB_NAME}?host=/cloudsql/${CONN}"
else
  DB_PASS="$(gcloud secrets versions access latest --secret DB_PASSWORD)"
  put_secret DATABASE_URL "postgresql+psycopg://${DB_USER}:${DB_PASS}@/${DB_NAME}?host=/cloudsql/${CONN}"
fi
put_secret SECRET_KEY "$(rand 48)"
put_secret ENCRYPTION_KEY "$(python3 -c 'import base64,os;print(base64.urlsafe_b64encode(os.urandom(32)).decode())')"
put_secret ADMIN_REGISTRATION_SUPER_KEY "$(rand 24)"
put_secret ATTENDANCE_DEVICE_KEY "$(rand 24)"
put_secret SMTP_PASSWORD "$SMTP_PASSWORD" update

say "Building the API image (Cloud Build)"
gcloud builds submit "$ROOT/apps/api" --tag "$IMAGE"

# "@" separates env vars so commas inside values (CORS list, proxy ranges) stay intact.
ENVS="^@^ENVIRONMENT=production@DEBUG=false@STORAGE_BACKEND=gcs@GCS_BUCKET=${BUCKET}@EMAIL_PROVIDER=SMTP"
ENVS+="@SMTP_HOST=${SMTP_HOST}@SMTP_PORT=${SMTP_PORT}@SMTP_USERNAME=${SMTP_USERNAME}@SMTP_FROM_EMAIL=${SMTP_FROM_EMAIL}"
ENVS+="@SMTP_FROM_NAME=${SMTP_FROM_NAME:-Origin Living}@APP_URL=${APP_URL}@CORS_ORIGINS=${CORS_ORIGINS}"
ENVS+="@PUSH_PROVIDER=EXPO@LICENSE_ENFORCED=false@FORWARDED_ALLOW_IPS=169.254.0.0/16,127.0.0.1"
SECRETS="DATABASE_URL=DATABASE_URL:latest,SECRET_KEY=SECRET_KEY:latest,ENCRYPTION_KEY=ENCRYPTION_KEY:latest"
SECRETS+=",ADMIN_REGISTRATION_SUPER_KEY=ADMIN_REGISTRATION_SUPER_KEY:latest,ATTENDANCE_DEVICE_KEY=ATTENDANCE_DEVICE_KEY:latest"
SECRETS+=",SMTP_PASSWORD=SMTP_PASSWORD:latest"
COMMON=(--image "$IMAGE" --region "$REGION" --service-account "$SA"
        --set-env-vars "$ENVS" --set-secrets "$SECRETS" --memory 512Mi)
[ -n "${EXTERNAL_DATABASE_URL:-}" ] || COMMON+=(--set-cloudsql-instances "$CONN")

job() { # name command [args...]
  local name="$1" cmd="$2"; shift 2
  local args; args="$(IFS=,; echo "$*")"
  gcloud run jobs deploy "$name" "${COMMON[@]}" --command "$cmd" ${args:+--args "$args"} --max-retries 1 --task-timeout 900 >/dev/null
}

say "Database migrations (creates all tables in the empty database)"
job pg-migrate alembic upgrade head
gcloud run jobs execute pg-migrate --region "$REGION" --wait

say "API service (Cloud Run)"
# One instance: rate limits and login lockouts live in memory (sized for one PG business).
gcloud run deploy "$SERVICE" "${COMMON[@]}" --allow-unauthenticated --min-instances 0 --max-instances 1 \
  --cpu 1 --concurrency 40 --timeout 60 --port 8000

say "Scheduled jobs: monthly bills, rent reminders, KYC deadlines"
job pg-monthly-invoices python -m app.tasks.run monthly-invoices
job pg-rent-reminders python -m app.tasks.run reminders
job pg-kyc-deadlines python -m app.tasks.run kyc-deadlines
gcloud projects add-iam-policy-binding "$PROJECT" --member "serviceAccount:$SA" --role roles/run.invoker --condition=None >/dev/null
schedule() { # job cron
  local uri="https://run.googleapis.com/v2/projects/${PROJECT}/locations/${REGION}/jobs/$1:run" verb=create
  gcloud scheduler jobs describe "$1" --location "$REGION" >/dev/null 2>&1 && verb=update
  gcloud scheduler jobs "$verb" http "$1" --location "$REGION" --schedule "$2" --time-zone "Asia/Kolkata" --uri "$uri" \
    --http-method POST --oauth-service-account-email "$SA" >/dev/null
}
schedule pg-monthly-invoices "30 7 1 * *"   # 07:30 IST on the 1st
schedule pg-rent-reminders "0 9 * * *"      # 09:00 IST daily
schedule pg-kyc-deadlines "15 9 * * *"      # 09:15 IST daily

if [ -n "${OWNER_EMAIL:-}" ]; then
  say "First owner login"
  for v in OWNER_COMPANY OWNER_PHONE OWNER_NAME OWNER_PASSWORD; do need "$v"; done
  put_secret OWNER_INITIAL_PASSWORD "$OWNER_PASSWORD" update
  gcloud run jobs deploy pg-create-owner "${COMMON[@]}" --set-secrets "${SECRETS},OWNER_PASSWORD=OWNER_INITIAL_PASSWORD:latest" \
    --command python --args "scripts/create_owner.py,--company,${OWNER_COMPANY},--email,${OWNER_EMAIL},--phone,${OWNER_PHONE},--name,${OWNER_NAME},--beds,250${OWNER_TEMP_WEAK:+,--temporary-weak-password}" \
    --max-retries 0 >/dev/null
  gcloud run jobs execute pg-create-owner --region "$REGION" --wait || echo "(Owner may already exist; see the job logs.)"
  gcloud secrets delete OWNER_INITIAL_PASSWORD --quiet >/dev/null || true
fi

URL="$(gcloud run services describe "$SERVICE" --region "$REGION" --format 'value(status.url)')"
say "Done"
echo "API:    ${URL}"
echo "Health: ${URL}/api/v1/health"
echo "Next:   set EXPO_PUBLIC_API_URL=${URL} for the web app build, and add its address to CORS_ORIGINS."
