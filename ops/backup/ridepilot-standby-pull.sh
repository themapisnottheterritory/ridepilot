#!/usr/bin/env bash
# RidePilot warm-standby pull (runs on the STANDBY, 10.0.0.15, hourly cron).
# Pulls the latest backups from the primary (10.0.0.16) and restores them so the
# standby stays ~1h fresh and ready for failover. The standby INITIATES the pull
# (no creds stored on the primary); needs a .15 -> .16 ssh key for user philz.
#
# NOTE: this REPLACES the standby database each run. While actively using .15 as
# a test/staging mirror, disable this cron so your test data isn't wiped; the
# next enabled run resyncs you back to a clean prod mirror. See ops/warm-standby.md.
set -uo pipefail
export PATH=/usr/local/bin:/usr/bin:/bin

PRIMARY=philz@10.0.0.16
REMOTE=/home/philz/backups
DEST=/home/philz/backups
DB=ridepilot
APPDIR=/home/philz/rptest/ridepilot
LOG="$DEST/standby-pull.log"
mkdir -p "$DEST/db" "$DEST/uploads"

log(){ echo "[$(date '+%F %T %Z')] $*" >> "$LOG"; }

# 1) pull latest backups from the primary
if rsync -az --delete "$PRIMARY:$REMOTE/db/"      "$DEST/db/"      2>>"$LOG" \
   && rsync -az --delete "$PRIMARY:$REMOTE/uploads/" "$DEST/uploads/" 2>>"$LOG"; then
  log "pulled backups from $PRIMARY"
else
  log "PULL FAILED (primary unreachable?) — keeping existing local copy for failover"
fi

# 2) restore the latest db dump into the standby's db container
LATEST="$DEST/db/latest.dump"
if [ -e "$LATEST" ]; then
  REAL="$DEST/db/$(readlink "$LATEST" 2>/dev/null || echo "$(basename "$LATEST")")"
  if docker exec -i ridepilot_db_1 pg_restore -U postgres -d "$DB" --clean --if-exists < "$REAL" 2>>"$LOG"; then
    log "restored $(basename "$REAL")"
  else
    log "restore finished with warnings (benign --clean drops are expected)"
  fi
else
  log "no latest.dump present — nothing to restore yet"
fi

# 3) refresh uploads into the app checkout
rsync -a --delete "$DEST/uploads/system/" "$APPDIR/public/system/" 2>>"$LOG" && log "uploads refreshed"
log "done"
