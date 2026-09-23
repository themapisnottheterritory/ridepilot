#!/usr/bin/env bash
# SessionStart hook: surface RidePilot daily health-check alerts into Claude's
# context so they get translated into plain English. Reads the anomaly log
# written by ridepilot-healthcheck.sh (host cron, 00:30 daily).
# Emits JSON with hookSpecificOutput.additionalContext.
set -uo pipefail
f=/home/philz/ridepilot-health-ALERTS.log

if [ -s "$f" ]; then
  lines="$(tail -5 "$f")"
  msg="RidePilot daily health-check ALERTS (oldest first, most recent last). Translate any RECENT/unresolved entry into plain English for the user and say what to do; skip entries that are already stale or resolved. Known residual to ignore: a 'sidekiq scheduler thread died' alert stemming from the 2026-08-13 connection_pool fix ages out of the 25h window by 2026-08-15.

$lines"
else
  msg="RidePilot daily health-check: no alerts logged — all clear. (No need to mention unless asked.)"
fi

# Dispatch roster sync (ops/roster/roster-sync.sh, 15:00 daily): open routes,
# unknown drivers, refused assignments, or the schedule bot being down.
r=/home/philz/ridepilot-roster-ALERTS.log
if [ -s "$r" ]; then
  msg="$msg

Roster sync alerts (dispatch sheet vs RidePilot runs; most recent last). Translate recent entries into plain English: an OPEN route means dispatch has nobody on it, an unknown driver means the sheet's spelling matches no RidePilot driver.
$(tail -5 "$r")"
fi
python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":sys.stdin.read()}}))' <<<"$msg"
