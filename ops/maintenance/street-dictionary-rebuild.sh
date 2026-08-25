#!/usr/bin/env bash
# RidePilot nightly street-dictionary rebuild.
#
# Picks up streets added to the address book since the last run and resolves
# them against the geocoder. The dictionary is what lets the address pickers
# complete a partial street ("1404 E Vir"), which Nominatim cannot do on its
# own; without this it goes stale as new streets appear.
#
# Cheap to repeat: collect is a local scan, and canonicalize only touches rows
# that are still unresolved, so a night with no new streets costs a few seconds.
# Entries the geocoder cannot match are left unresolved (and kept out of
# suggestions) and dumped to $WORKLIST as a data-quality list.
#
# Installed via host crontab (user philz). Companion to the scheduler:run cron.
set -uo pipefail
export PATH=/usr/local/bin:/usr/bin:/bin

LOG=/home/philz/ridepilot-street-dictionary.log
WORKLIST=/home/philz/ridepilot-ops/street-dictionary-unresolved.csv
CONTAINER=ridepilot_app_1
TS="$(date '+%Y-%m-%d %H:%M:%S %Z')"

log() { printf '%s\n' "$*" >>"$LOG"; }

log ""
log "=== street dictionary rebuild $TS ==="

if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$CONTAINER"; then
  log "ABORT: $CONTAINER is not running"
  exit 1
fi

run_rake() {
  docker exec "$CONTAINER" sh -c "cd /var/www/ridepilot && bin/rails $1" 2>&1 \
    | grep -vE 'DEPRECATION|upgrading_ruby_on_rails|for more information on how to upgrade|WickedPdf|^\s*\(called from|^$'
}

# Rebuild. Unbounded on purpose: a nightly run has only the day's new streets
# to resolve, and capping it would leave them unresolved indefinitely.
if ! run_rake "street_dictionary:build" >>"$LOG"; then
  log "WARN: build exited non-zero"
fi

run_rake "street_dictionary:status" >>"$LOG"

# Refresh the worklist so it reflects tonight's state rather than whenever
# someone last ran it by hand.
if run_rake "street_dictionary:unresolved CSV=/tmp/street-dictionary-unresolved.csv" >>"$LOG"; then
  docker cp "$CONTAINER:/tmp/street-dictionary-unresolved.csv" "$WORKLIST" >/dev/null 2>&1 \
    && log "worklist -> $WORKLIST" \
    || log "WARN: could not copy worklist out of the container"
fi

log "=== done $(date '+%H:%M:%S') ==="
