#!/bin/bash
# =============================================================================
# Poste.io Backup Script
# =============================================================================
# Uso: ./backup.sh
#
# Hace un backup de los datos de Poste.io sin detener el servidor.
# Los backups se guardan en ./backups/ con timestamp.
# =============================================================================

set -e

BACKUP_DIR="backups"
CONTAINER="posteio"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="posteio-backup-${TIMESTAMP}.tar.gz"

echo "=== Poste.io Backup ==="
echo "Iniciando backup en contenedor..."

docker compose exec -T "$CONTAINER" tar -czf /tmp/backup.tar.gz /data

echo "Copiando backup al host..."
docker cp "${CONTAINER}:/tmp/backup.tar.gz" "${BACKUP_DIR}/${BACKUP_FILE}"

echo "Limpiando archivo temporal en contenedor..."
docker compose exec -T "$CONTAINER" rm -f /tmp/backup.tar.gz

echo "Backup completado: ${BACKUP_DIR}/${BACKUP_FILE}"
ls -lh "${BACKUP_DIR}/${BACKUP_FILE}"
