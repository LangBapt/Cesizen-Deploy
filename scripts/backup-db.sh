#!/bin/bash
set -e

ENV=${1:-staging}
BACKUP_DIR="/opt/cesizen/backups/${ENV}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/cesizen_${ENV}_${TIMESTAMP}.sql.gz"

mkdir -p "$BACKUP_DIR"

if [ "$ENV" = "prod" ]; then
  CONTAINER="postgres-prod"
  DB_NAME="${POSTGRES_DB:-cesizen_prod}"
else
  CONTAINER="postgres-staging"
  DB_NAME="${POSTGRES_DB:-cesizen_staging}"
fi

echo "Backup de la base ${DB_NAME} (${ENV})..."
docker exec "$CONTAINER" pg_dump -U "${POSTGRES_USER:-cesizen_user}" "$DB_NAME" | \
  gzip > "$BACKUP_FILE"

echo "Backup créé : $BACKUP_FILE"

find "$BACKUP_DIR" -name "*.sql.gz" -mtime +7 -delete
echo "Anciens backups (+7j) supprimés."