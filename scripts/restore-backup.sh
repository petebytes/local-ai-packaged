#!/bin/bash

# Check if backup file is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <backup-file>"
    echo "Example: $0 backup-2025-03-18-00-00-00.tar.gz"
    echo "Available backups:"
    ls -l /var/lib/docker/volumes/local-ai-packaged_backup_data/_data/
    exit 1
fi

BACKUP_FILE=$1

# Stop the services that are being restored
echo "Stopping services..."
docker-compose stop n8n flowise open-webui qdrant nocodb

# Extract backup file
echo "Restoring volumes from $BACKUP_FILE..."
docker run --rm \
    -v local-ai-packaged_backup_data:/backup \
    -v local-ai-packaged_n8n_storage:/restore/n8n \
    -v local-ai-packaged_qdrant_storage:/restore/qdrant \
    -v local-ai-packaged_open-webui:/restore/open-webui \
    -v local-ai-packaged_flowise_storage:/restore/flowise \
    -v local-ai-packaged_nocodb:/restore/nocodb \
    -v /var/run/docker.sock:/var/run/docker.sock \
    alpine sh -c "cd /restore && tar xzf /backup/$BACKUP_FILE"

# Restore PostgreSQL database if it exists in the backup
if [ -f "/var/lib/docker/volumes/local-ai-packaged_backup_data/_data/postgres.sql" ]; then
    echo "Restoring PostgreSQL database..."
    docker run --rm \
        -v local-ai-packaged_backup_data:/backup \
        --network local-ai-packaged_localai_default \
        postgres:13 pg_restore \
        -h "$POSTGRES_HOST" \
        -p "$POSTGRES_PORT" \
        -U postgres \
        -d "$POSTGRES_DB" \
        -c /backup/postgres.sql
fi

# Start the services back
echo "Starting services..."
docker-compose start n8n flowise open-webui qdrant nocodb

echo "Restore completed!"
