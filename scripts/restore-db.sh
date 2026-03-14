#!/usr/bin/env bash
# =============================================================
# Restore a Postgres database from an S3 backup.
#
# Usage:
#   bash scripts/restore-db.sh 2025-01-15T02-00-00Z
#
# If no timestamp is given, lists available backups and exits.
# =============================================================
set -euo pipefail

S3_BUCKET="${BACKUP_S3_BUCKET:?Set BACKUP_S3_BUCKET env var}"
DB_NAME="${DB_NAME:?Set DB_NAME env var}"
DB_USER="${DB_USER:?Set DB_USER env var}"
DB_PASSWORD="${DB_PASSWORD:?Set DB_PASSWORD env var}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
AWS_REGION="${AWS_REGION:-us-east-1}"

list_backups() {
  echo "Available backups in s3://$S3_BUCKET/backups/:"
  aws s3 ls "s3://$S3_BUCKET/backups/" --region "$AWS_REGION" \
    | awk '{print $4}' | grep "\.sql\.gz$" | sort -r | head -20
}

if [ $# -eq 0 ]; then
  list_backups
  echo ""
  echo "Usage: $0 <TIMESTAMP>"
  echo "  e.g. $0 2025-01-15T02-00-00Z"
  exit 0
fi

TIMESTAMP="$1"
FILENAME="backup-${TIMESTAMP}.sql.gz"
S3_KEY="s3://$S3_BUCKET/backups/$FILENAME"
TMPFILE="/tmp/$FILENAME"

echo "⬇️  Downloading $S3_KEY …"
aws s3 cp "$S3_KEY" "$TMPFILE" --region "$AWS_REGION"

echo "⚠️  This will DROP and recreate the database: $DB_NAME on $DB_HOST"
read -r -p "  Are you sure? Type 'yes' to continue: " confirm
if [ "$confirm" != "yes" ]; then
  echo "Aborted."
  rm -f "$TMPFILE"
  exit 1
fi

export PGPASSWORD="$DB_PASSWORD"

echo "🔄 Dropping and recreating $DB_NAME …"
psql --host="$DB_HOST" --port="$DB_PORT" --username="$DB_USER" \
  --dbname=postgres \
  --command="DROP DATABASE IF EXISTS $DB_NAME;" \
  --command="CREATE DATABASE $DB_NAME OWNER $DB_USER;"

echo "📥 Restoring from backup …"
gunzip -c "$TMPFILE" \
  | psql --host="$DB_HOST" --port="$DB_PORT" \
         --username="$DB_USER" --dbname="$DB_NAME"

rm -f "$TMPFILE"
echo "✅ Restore complete: $DB_NAME restored from $FILENAME"
