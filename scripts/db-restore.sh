#!/bin/bash
set -e

ENV=${1:-staging}
BACKUP_FILE=$2

if [ -z "$BACKUP_FILE" ]; then
    echo "Erreur : Vous devez spécifier le chemin du fichier de backup."
    echo "Usage: $0 [staging|prod] /chemin/vers/le/backup.sql.gz"
    exit 1
fi

if [ ! -f "$BACKUP_FILE" ]; then
    echo "Erreur : Le fichier $BACKUP_FILE n'existe pas."
    exit 1
fi

if [ "$ENV" = "prod" ]; then
    CONTAINER="postgres-prod"
    DB_NAME="${POSTGRES_DB:-cesizen_prod}"
else
    CONTAINER="postgres-staging"
    DB_NAME="${POSTGRES_DB:-cesizen_staging}"
fi

# Sécurité : On demande confirmation car une restauration écrase les données actuelles !
echo "ATTENTION : Vous allez écraser la base de données '$DB_NAME' ($ENV) avec le backup : $BACKUP_FILE"
read -p "Êtes-vous sûr de vouloir continuer ? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Restauration annulée."
    exit 0
fi

echo "Restauration de la base ${DB_NAME} en cours..."

gunzip -c "$BACKUP_FILE" | docker exec -i "$CONTAINER" psql -U "${POSTGRES_USER:-cesizen_user}" -d "$DB_NAME"

echo "Restauration réussie avec succès !"