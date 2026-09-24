#!/usr/bin/env python3
"""Tell the Inteplast Shuttle Status board (ride.gcrpc.org) what today looks
like on dispatch's schedule: which commuter lines are one bus today (a
"double" on the sheet) and which are not in service.

Reads the day's roster from the schedule bot on 10.0.0.18, the same feed the
RidePilot roster sync uses, and POSTs to the board's /api/roster/day. The
board pairs the two lines (one status, one bus, delay texts to both lines'
subscribers) and marks not-in-service lines cancelled with a row it owns; it
never overwrites a status a person entered. Riders keep seeing their town.

    push-status-board.py [today|tomorrow|YYYY-MM-DD]     # default today

Env (from ~/ridepilot-ops/sched.env, sourced by roster-sync.sh):
    SCHED_SHIM_TOKEN   bearer for the roster
    ROSTER_PUSH_TOKEN  X-Roster-Token the board expects (same value in its .env)
    ROSTER_URL         default http://10.0.0.18:8792
    STATUS_BOARD_URL   default http://10.0.0.32:3001
"""
import json
import os
import sys
import urllib.request

ROSTER_URL = os.environ.get("ROSTER_URL", "http://10.0.0.18:8792").rstrip("/")
BOARD_URL = os.environ.get("STATUS_BOARD_URL", "http://10.0.0.32:3001").rstrip("/")

# Sheet route -> line on the board (bus_lines.line_number). VIC3 riders ride
# the Edna bus; the board has called that line "Edna/Vic" since before this.
LINES = {
    "BAY": "Bay City", "BAY CITY": "Bay City", "PAL": "Palacios", "PALACIOS": "Palacios",
    "CAMPO": "El Campo", "EL CAMPO": "El Campo", "PORT LAVACA": "Port Lavaca", "PL": "Port Lavaca",
    "VIC1": "Victoria 1", "VIC 1": "Victoria 1", "VICTORIA 1": "Victoria 1",
    "VIC2": "Victoria 2", "VIC 2": "Victoria 2", "VICTORIA 2": "Victoria 2",
    "VIC3/EDNA": "Edna/Vic", "VIC 3/EDNA": "Edna/Vic", "EDNA/VIC3": "Edna/Vic", "EDNA": "Edna/Vic",
}


def line_for(route):
    key = route.strip().upper()
    key = key.split(" (")[0]            # "EDNA ASSIST (AM/PM)" -> "EDNA ASSIST"
    if "ASSIST" in key:
        return None                     # an overflow bus, not a line
    return LINES.get(key)


def main():
    date = sys.argv[1] if len(sys.argv) > 1 else "today"
    shim = os.environ.get("SCHED_SHIM_TOKEN")
    push = os.environ.get("ROSTER_PUSH_TOKEN")
    if not shim or not push:
        print("push-status-board: SCHED_SHIM_TOKEN and ROSTER_PUSH_TOKEN are required", file=sys.stderr)
        return 2
    req = urllib.request.Request(f"{ROSTER_URL}/roster?date={date}&category=commuter",
                                 headers={"Authorization": f"Bearer {shim}"})
    with urllib.request.urlopen(req, timeout=30) as r:
        roster = json.load(r)
    if roster.get("error"):
        print(f"push-status-board: roster says {roster['error']} for {date}; board left as is", file=sys.stderr)
        return 3

    entries = (roster.get("categories") or {}).get("commuter") or []
    by_line = {}
    for e in entries:
        line = line_for(e.get("route", ""))
        if line:
            by_line.setdefault(line, []).append(e.get("status"))
    not_in_service = sorted(l for l, st in by_line.items() if st and all(s == "not_in_service" for s in st))

    pairs, seen = [], set()
    for c in (roster.get("combos") or {}).get("commuter") or []:
        lines = sorted({line_for(r) for r in c.get("routes", []) if line_for(r)})
        if len(lines) == 2 and tuple(lines) not in seen:
            pairs.append(lines); seen.add(tuple(lines))
        elif len(lines) > 2:
            print(f"push-status-board: {c.get('operator')} holds {lines}; the board pairs two at a time, first two used", file=sys.stderr)
            pairs.append(lines[:2])

    body = json.dumps({"date": roster.get("date"), "pairs": pairs, "not_in_service": not_in_service}).encode()
    req = urllib.request.Request(f"{BOARD_URL}/api/roster/day", data=body, method="POST",
                                 headers={"Content-Type": "application/json", "X-Roster-Token": push})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            out = json.load(r)
    except urllib.error.HTTPError as e:
        print(f"push-status-board: board answered {e.code}: {e.read()[:200]!r}", file=sys.stderr)
        return 4
    print(f"status board {roster.get('date')}: pairs {pairs or 'none'}; not in service {not_in_service or 'none'}; "
          f"board: {out.get('pairs')} pairs, {out.get('not_in_service')} off, unknown {out.get('unknown') or 'none'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
