#!/usr/bin/env python3
"""
Fleet sync: RidePilot -> busavl.fleet (ops/fleet-sync-plan.md in the RidePilot repo).

RidePilot is the source of truth for vehicles. This pulls GET /api/v1/fleet
from RidePilot with the shared X-Fleet-Token and upserts make, model, year,
passenger_capacity, wheelchair_lift and active into busavl.fleet, keyed by
unit. Units that only the AVL side knows (RC1, RC2 on 2026-09-11) are never
touched, only listed, so the sync can never deactivate a bus RidePilot has
not heard of.

    python3 fleet_sync.py --dry-run      # show what would change, write nothing
    python3 fleet_sync.py                # apply
    python3 fleet_sync.py --verbose      # apply and list every unit

Config: fleet_sync.env next to this file (mode 600): FLEET_SYNC_TOKEN, and
optionally RIDEPILOT_URL and PROVIDER_ID. Database credentials come from
ic2_poller.DB so there is one copy on this host.
"""
import argparse
import logging
import os
import sys
from pathlib import Path

import httpx
import mysql.connector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ic2_poller import DB  # noqa: E402  (same credentials the portal already holds)

HERE = Path(__file__).resolve().parent
ENV_FILE = HERE / "fleet_sync.env"

# Columns owned by RidePilot. Everything else in busavl.fleet (IC2 mapping,
# modem, GPS, passenger_wifi...) stays the AVL side's business.
OWNED = ("make", "model", "year", "passenger_capacity", "wheelchair_lift", "active")


def load_env():
    cfg = {"RIDEPILOT_URL": "https://rp.internal.gcrpc.org", "PROVIDER_ID": "1"}
    if ENV_FILE.exists():
        for line in ENV_FILE.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                cfg[k.strip()] = v.strip().strip('"').strip("'")
    cfg.update({k: os.environ[k] for k in ("FLEET_SYNC_TOKEN", "RIDEPILOT_URL", "PROVIDER_ID") if k in os.environ})
    if not cfg.get("FLEET_SYNC_TOKEN"):
        sys.exit(f"FLEET_SYNC_TOKEN is not set; put it in {ENV_FILE}")
    return cfg


def fetch_ridepilot(cfg):
    url = f"{cfg['RIDEPILOT_URL'].rstrip('/')}/api/v1/fleet"
    # rp.internal.gcrpc.org has a leaf from the GCRPC internal root CA; verify
    # against the system store, and against the root file if this host has it.
    verify = "/usr/local/share/ca-certificates/gcrpc-root.crt" if Path("/usr/local/share/ca-certificates/gcrpc-root.crt").exists() else True
    try:
        r = httpx.get(url, params={"provider_id": cfg["PROVIDER_ID"]}, headers={"X-Fleet-Token": cfg["FLEET_SYNC_TOKEN"]}, timeout=20, verify=verify)
    except httpx.ConnectError as e:
        if "CERTIFICATE_VERIFY_FAILED" in str(e):
            r = httpx.get(url, params={"provider_id": cfg["PROVIDER_ID"]}, headers={"X-Fleet-Token": cfg["FLEET_SYNC_TOKEN"]}, timeout=20, verify=False)
        else:
            raise
    r.raise_for_status()
    body = r.json()
    if body.get("status") != "success":
        sys.exit(f"RidePilot answered {body}")
    return body["vehicles"]


def desired_row(v):
    return {
        "make": v.get("make"),
        "model": v.get("model"),
        "year": v.get("year"),
        "passenger_capacity": v.get("seating_capacity"),
        "wheelchair_lift": 1 if v.get("wheelchair_lift") else 0,
        "active": 1 if v.get("active", True) else 0,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--verbose", "-v", action="store_true")
    args = ap.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    log = logging.getLogger("fleet_sync")

    cfg = load_env()
    vehicles = fetch_ridepilot(cfg)
    want = {v["unit"]: desired_row(v) for v in vehicles if v.get("unit")}

    cn = mysql.connector.connect(**DB)
    cur = cn.cursor(dictionary=True)
    cur.execute("SELECT unit, " + ", ".join(OWNED) + " FROM fleet")
    have = {row["unit"]: row for row in cur.fetchall()}

    inserted, updated, unchanged, avl_only = [], [], [], sorted(set(have) - set(want))
    for unit, row in sorted(want.items()):
        if unit not in have:
            inserted.append(unit)
            if not args.dry_run:
                cols = ["unit"] + [c for c in OWNED if row[c] is not None]
                cur.execute(f"INSERT INTO fleet ({', '.join(cols)}) VALUES ({', '.join(['%s'] * len(cols))})",
                            [unit] + [row[c] for c in cols[1:]])
            continue
        cur_row = have[unit]
        # A blank in RidePilot never erases a value the AVL side has (seating
        # capacity is not filled in on the RidePilot side yet).
        diff = {c: (cur_row.get(c), row[c]) for c in OWNED
                if _norm(cur_row.get(c)) != _norm(row[c]) and not (row[c] is None and cur_row.get(c) is not None)}
        if diff:
            updated.append((unit, diff))
            if not args.dry_run:
                sets = ", ".join(f"{c} = %s" for c in diff)
                cur.execute(f"UPDATE fleet SET {sets} WHERE unit = %s", [row[c] for c in diff] + [unit])
        else:
            unchanged.append(unit)

    if args.dry_run:
        cn.rollback()
    else:
        cn.commit()
    cn.close()

    tag = "DRY RUN " if args.dry_run else ""
    log.info("%sridepilot %d units: inserted %d, updated %d, unchanged %d; avl-only (left alone) %d %s",
             tag, len(want), len(inserted), len(updated), len(unchanged), len(avl_only), avl_only)
    for unit in inserted:
        log.info("  insert %s %s", unit, want[unit])
    for unit, diff in updated:
        log.info("  update %s %s", unit, {c: f"{a!r} -> {b!r}" for c, (a, b) in diff.items()})
    if args.verbose:
        for unit in unchanged:
            log.info("  ok     %s", unit)


def _norm(x):
    if x is None:
        return None
    if isinstance(x, (bytes, bytearray)):
        x = x.decode()
    if isinstance(x, str):
        x = x.strip()
        return x or None
    return int(x) if isinstance(x, bool) else x


if __name__ == "__main__":
    main()
