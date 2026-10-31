#!/usr/bin/env bash
# Dumps the GynoCamp database to /srv/gynocamp/backups and drops dumps older than
# 14 days. Run nightly by gynocamp-backup.timer, and by install.sh before a deploy
# when BACKUP_BEFORE_DEPLOY=1. Restore with:
#   sudo -u postgres pg_restore --clean --if-exists --no-owner --role=gynocamp -d <db> <file>.dump
set -euo pipefail
umask 077
set -a
# shellcheck source=/dev/null
. /srv/gynocamp/gynocamp.env   # PGHOST, PGDATABASE, PGUSER, PGPASSWORD
set +a
D=/srv/gynocamp/backups
F="$D/$PGDATABASE-$(date -u +%Y%m%d-%H%M%S).dump"
pg_dump --format=custom --file="$F.part"
mv "$F.part" "$F"
find "$D" -name '*.dump' -mtime +14 -delete
ls -lh "$F"
