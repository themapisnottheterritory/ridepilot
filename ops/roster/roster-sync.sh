#!/usr/bin/env bash
# Dispatch's operator schedule -> RidePilot's fixed-route runs, daily (host cron).
#
# Reads the roster for tomorrow from the schedule bot on 10.0.0.18 (which parses
# dispatch's SharePoint workbook live) and compares it with RidePilot's runs.
# MODE=watch (default) only reports; MODE=apply puts the sheet's driver on each
# run. Full output goes to $LOG; anything needing a human (open route, unknown
# driver, refused assignment, shim down) is appended as one line to $ALERTS,
# which the session-start hook surfaces the same way as the health check.
#
#   /home/philz/rptest/ridepilot/ops/roster/roster-sync.sh            # tomorrow, watch
#   MODE=apply DATE=2026-10-06 .../roster-sync.sh
#
# The shim's bearer token lives in $ENVFILE as SCHED_SHIM_TOKEN=... (mode 600,
# copied by hand from /etc/operator-schedule/sched.env on 10.0.0.18).
set -uo pipefail
ENVFILE=${ENVFILE:-/home/philz/ridepilot-ops/sched.env}
LOG=${LOG:-/home/philz/ridepilot-roster.log}
ALERTS=${ALERTS:-/home/philz/ridepilot-roster-ALERTS.log}
MODE=${MODE:-watch}
DATE=${DATE:-tomorrow}
CATEGORIES=${CATEGORIES:-fixed,commuter}
TS=$(date -u '+%Y-%m-%d %H:%M:%S UTC')

if [ ! -r "$ENVFILE" ]; then
  echo "[$TS] roster-sync: $ENVFILE missing or unreadable — no token, nothing checked" | tee -a "$LOG" >>"$ALERTS"
  exit 2
fi
# shellcheck disable=SC1090
set -a; . "$ENVFILE"; set +a
if [ -z "${SCHED_SHIM_TOKEN:-}" ]; then
  echo "[$TS] roster-sync: SCHED_SHIM_TOKEN not set in $ENVFILE" | tee -a "$LOG" >>"$ALERTS"
  exit 2
fi

OUT=$(/usr/bin/docker exec -e ROSTER_TOKEN="$SCHED_SHIM_TOKEN" -e ROSTER_CATEGORIES="$CATEGORIES" \
        ridepilot_app_1 bundle exec rake "fixed_routes:roster[$DATE,$MODE]" 2>&1 \
      | grep -v -i 'deprecat\|upgrading_ruby\|called from\|cache serialization\|^$')
RC=${PIPESTATUS[0]}
{ echo "[$TS] roster-sync $MODE $DATE (rc=$RC)"; echo "$OUT"; } >>"$LOG"
# The shuttle status board (ride.gcrpc.org) gets today's doubles and
# not-in-service lines from the same roster -- only on the same-day run, the
# evening shuttle is still today's.
if [ "$DATE" = "today" ]; then
  B=$(/usr/bin/python3 /home/philz/rptest/ridepilot/ops/roster/push-status-board.py today 2>&1); RB=$?
  echo "$B" >>"$LOG"
  [ "$RB" -ne 0 ] && echo "[$TS] status board push failed rc=$RB: $(echo "$B" | tail -1)" >>"$ALERTS"
fi
A=$(echo "$OUT" | grep '^  ALERTS:' | sed 's/^  ALERTS: //')
if [ -n "$A" ]; then
  echo "[$TS] roster $DATE: $A" >>"$ALERTS"
elif [ "$RC" -ne 0 ]; then
  echo "[$TS] roster $DATE: rake failed rc=$RC — $(echo "$OUT" | tail -1)" >>"$ALERTS"
fi
exit 0
