---
name: backup-db
description: Take a validated, timestamped backup of the Dockerised Postgres database — dump, prove the archive is restorable (TOC + row parity, optional restore-test), then prune old auto-backups generationally. Use before migrations, destructive data work, or when the session-start staleness hook warns.
---

# Database Backup

Create a database backup with the current timestamp.

## Usage

```
/backup-db [description]
```

Examples:
- `/backup-db` - Creates backup with default name
- `/backup-db pre_migration` - Creates backup with custom description

## Execution

When this command is invoked, run:

```bash
BACKUP_DATE=$(date +"%Y%m%d_%H%M%S")
DESCRIPTION="${1:-baseapp_local_backup}"
BACKUP_FILE="database_backups/${BACKUP_DATE}_${DESCRIPTION}.sql"

docker exec "${PG_CONTAINER:-baseapp-postgres-1}" pg_dump -U "${DB_USER:-postgres}" "${DB_NAME:-baseapp_local}" > "$BACKUP_FILE"

if [ -f "$BACKUP_FILE" ]; then
    SIZE=$(ls -lh "$BACKUP_FILE" | awk '{print $5}')
    echo "✅ Backup created: $BACKUP_FILE ($SIZE)"
else
    echo "❌ Backup failed"
fi
```

## Backup Location

All backups are stored in `/database_backups/` which is gitignored.

## Naming Convention

```
YYYYMMDD_HHMMSS_description_backup.sql
```

## Weekly Backup Reminder

Backups should be created at least once per week. Check the most recent backup:

```bash
ls -lt database_backups/*.sql | head -1
```
