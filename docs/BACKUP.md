# Backup and Restore Documentation

This document describes the backup and restore system implemented for the Local AI stack.

## Overview

The backup system uses `offen/docker-volume-backup` to automatically backup:
- All Docker volumes (n8n, flowise, qdrant, open-webui, nocodb)
- PostgreSQL database
- Configuration files

## Backup Configuration

### Schedule
- Automatic backups run daily at midnight (configurable via `BACKUP_CRON_EXPRESSION`)
- Keeps last 7 days of backups (configurable via `BACKUP_RETENTION_DAYS`)
- Compressed backups with timestamps
- Non-disruptive (doesn't stop running containers)

### Backup Contents
Each backup includes:
1. **Docker Volumes**
   - n8n_storage: N8N workflows and data
   - qdrant_storage: Vector database data
   - open-webui: Web UI configurations
   - flowise_storage: Flowise flows and settings
   - nocodb: NocoDB metadata

2. **PostgreSQL Database**
   - Complete database dump
   - Includes all tables and data
   - Preserves database structure

### Backup Location
Backups are stored in the `backup_data` Docker volume:
```
/var/lib/docker/volumes/local-ai-packaged_backup_data/_data/
```

## Usage

### Start Backup Service
```bash
# Start all services including backup
docker-compose up -d

# Start only backup service
docker-compose up -d backup
```

### Manual Backup
To trigger a manual backup:
```bash
docker-compose exec backup backup
```

### List Backups
View available backup files:
```bash
docker-compose exec backup ls -l /backup
```

### Backup Files
Backup files are named with timestamps:
```
backup-YYYY-MM-DD-HH-MM-SS.tar.gz
```

## Restore Process

### Using Restore Script
The `restore-backup.sh` script automates the restore process:

1. View available backups:
```bash
./restore-backup.sh
```

2. Restore from a specific backup:
```bash
./restore-backup.sh backup-2025-03-18-00-00-00.tar.gz
```

The restore process:
1. Stops affected services
2. Restores volume data
3. Restores PostgreSQL database if present
4. Restarts services

### Manual Restore
If you need to restore manually:

1. Stop services:
```bash
docker-compose stop n8n flowise open-webui qdrant nocodb
```

2. Extract backup:
```bash
docker run --rm \
    -v local-ai-packaged_backup_data:/backup \
    -v local-ai-packaged_n8n_storage:/restore/n8n \
    -v local-ai-packaged_qdrant_storage:/restore/qdrant \
    -v local-ai-packaged_open-webui:/restore/open-webui \
    -v local-ai-packaged_flowise_storage:/restore/flowise \
    -v local-ai-packaged_nocodb:/restore/nocodb \
    alpine sh -c "cd /restore && tar xzf /backup/backup-file.tar.gz"
```

3. Start services:
```bash
docker-compose start n8n flowise open-webui qdrant nocodb
```

## Monitoring

### Check Backup Status
```bash
# View backup service logs
docker-compose logs backup

# Follow backup service logs
docker-compose logs -f backup
```

### Backup Health Check
The backup service includes a health check that verifies:
- Backup process is running
- Sufficient disk space
- Access to all required volumes

## Troubleshooting

### Common Issues

1. **Backup Failed**
   - Check logs: `docker-compose logs backup`
   - Verify disk space: `df -h`
   - Ensure all volumes are properly mounted

2. **Restore Failed**
   - Verify backup file exists
   - Check for sufficient disk space
   - Ensure services are stopped before restore

3. **Database Restore Issues**
   - Verify PostgreSQL connection settings
   - Check database user permissions
   - Ensure database exists at restore target

### Getting Help
If you encounter issues:
1. Check the backup service logs
2. Verify all services are running
3. Check system resources (disk space, memory)
4. Ensure proper permissions on backup directories

## Customization

### Environment Variables

The backup service can be customized through environment variables:

```yaml
environment:
  - BACKUP_CRON_EXPRESSION=0 0 * * *  # Backup schedule
  - BACKUP_FILENAME=backup-%Y-%m-%d-%H-%M-%S.tar.gz  # Backup filename format
  - BACKUP_RETENTION_DAYS=7  # Number of days to keep backups
  - BACKUP_COMPRESSION_LEVEL=9  # Compression level (1-9)
  - BACKUP_STOP_CONTAINERS=false  # Whether to stop containers during backup
```

### Adding New Volumes

To backup additional volumes:
1. Add volume to docker-compose.yml
2. Mount volume in backup service with `:ro` flag
3. Update restore script if needed
