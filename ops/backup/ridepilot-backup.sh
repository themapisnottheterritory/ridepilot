#!/usr/bin/env bash
# RidePilot hourly backup (runs on the PRIMARY, 10.0.0.16).
# Produces: a consistent PostGIS dump + an uploads mirror, with rotation.
# Serves double duty: (1) the primary off-box DR backup, (2) the feed the .15
# warm standby pulls from (see ops/warm-standby.md). Installed via host cron.
# Repo is the live source (ops/backup/), same model as ops/monitoring/.
set -uo pipefail
export PATH=/usr/local/bin:/usr/bin:/bin

DEST=/home/philz/backups
DB=ridepilot
APPDIR=/home/philz/rptest/ridepilot
KEEP=168                       # hourly db dumps to retain (~7 days; ~6.4 MB each)
STAMP="$(date '+%Y%m%d-%H%M')"
LOG="$DEST/backup.log"
mkdir -p "$DEST/db" "$DEST/uploads"

log(){ echo "[$(date '+%F %T %Z')] $*" >> "$LOG"; }

# --- database: consistent custom-format dump (MVCC snapshot; safe on a live DB) ---
DBOUT="$DEST/db/ridepilot-db-$STAMP.dump"
if docker exec ridepilot_db_1 pg_dump -U postgres -Fc "$DB" > "$DBOUT" 2>>"$LOG" && [ -s "$DBOUT" ]; then
  ln -sf "ridepilot-db-$STAMP.dump" "$DEST/db/latest.dump"
  log "db OK $(du -h "$DBOUT" | cut -f1) -> $(basename "$DBOUT")"
else
  log "DB DUMP FAILED (removed partial)"
  rm -f "$DBOUT"
fi

# --- uploads: mirror public/system (customer/provider/DVIR images; small) ---
if rsync -a --delete "$APPDIR/public/system/" "$DEST/uploads/system/" 2>>"$LOG"; then
  log "uploads mirrored"
else
  log "UPLOADS SYNC FAILED"
fi

# --- rotation: keep newest $KEEP db dumps (latest.dump symlink is never matched) ---
ls -1t "$DEST"/db/ridepilot-db-*.dump 2>/dev/null | tail -n +$((KEEP+1)) | xargs -r rm -f

log "done"
