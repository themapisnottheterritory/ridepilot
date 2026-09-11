# Fleet record sync: RidePilot → AVL `busavl.fleet`

Written 2026-09-11 after the wheelchair-lift cleanup. Status: proposal, not built.

## Why

The vehicle list exists in two databases that nothing keeps in sync:

| | RidePilot `vehicles` (Postgres, 10.0.0.16) | AVL `busavl.fleet` (MariaDB, 10.0.0.40) |
|---|---|---|
| Edited by | the office, on the Vehicles page | by hand, in SQL |
| Read by | dispatch, runs, optimizer, NTD, DVIR | the Transit Team Portal on 10.0.0.32 (yard.gcrpc.org: fleet status, fleet-maintenance report), the bus tracker |
| Lift flag | `accessibility_equipment` free text ("Wheelchair lift") | `wheelchair_lift` tinyint |

On 2026-09-11 they had drifted: 7 AVL rows had no make/model/year, 3 AVL units flagged as lift-equipped
were wrong or unknown to RidePilot, 38 lift-equipped buses were unflagged, and the two lists differ by
five vehicles (RidePilot has 221, 223, C-10; AVL has RC1, RC2). Both were corrected by hand that day
(RidePilot: 41 Aerotech / Champion Defender units flagged; AVL: same 41 plus the 7 blank rows filled from
RidePilot, Tahoe cleared, RC1/RC2 left as found). Without a sync the same drift returns.

## Decision

**RidePilot is the source of truth for the fleet.** It is where the office creates and edits vehicles, and it
already carries make, model, year, VIN, plate, seating capacity, active status, and the lift. The AVL table
is a consumer.

## What to build

### 1. RidePilot: make the lift a real field

`accessibility_equipment` is free text; the sync would have to grep it. Add to `vehicles`:

- `wheelchair_lift boolean not null default false`
- `mobility_device_accommodations` already exists (tie-down positions, integer; the optimizer assumes 2
  when null). Keep it, fill it in when known.

Backfill `wheelchair_lift = true` where `accessibility_equipment ILIKE '%wheelchair lift%'` (the 41). Show
both on the vehicle form's Additional Info panel next to the free-text box (a checkbox and a number).
Half a day including a spec.

### 2. RidePilot: a fleet JSON endpoint

`GET /api/v1/fleet` (token-authenticated like the driver API, or a per-provider read-only token) returning
every non-deleted vehicle for the provider:

```
{ "unit": "1733", "make": "Ford", "model": "E450 Eldorado Aerotech 240", "year": 2019,
  "vin": "...", "license_plate": "...", "active": true, "seating_capacity": 16,
  "wheelchair_lift": true, "tie_downs": 2, "vehicle_type": "Bus (16 Passenger)",
  "updated_at": "2026-09-11T20:14:00Z" }
```

`unit` is `vehicles.name`. Nothing inbound to RidePilot from the portal; the portal pulls.

### 3. Portal host: a puller, same shape as `ic2_poller.py`

On 10.0.0.32, `~/yard_portal/fleet_sync.py` plus a systemd timer (hourly, like `ic2-poller.timer`):

1. GET the fleet JSON from RidePilot with the token.
2. For each unit, `INSERT ... ON DUPLICATE KEY UPDATE` into `busavl.fleet`: make, model, year,
   passenger_capacity (= seating_capacity), wheelchair_lift, active.
3. Units in `busavl.fleet` that RidePilot does not have (RC1, RC2 today): **leave untouched and log
   them**, so a vehicle the AVL side knows about is never deactivated by the sync. Resolve those by
   adding them to RidePilot (then the sync owns them) or deleting them from AVL by hand.
4. Log a one-line summary (updated N, unchanged M, AVL-only K) to the poller's log.

The puller uses the same `busavl` credentials the portal already holds in `server.js`; do not copy them
into a new place, read them from a shared config the portal also reads (the `apps.config.js` pattern).

### 4. Portal: stop editing the fleet by hand

Once the puller runs, the portal's fleet columns that RidePilot owns are read-only from the AVL side.
Anything AVL-specific (IC2 device mapping, modem, last GPS) stays in AVL as now.

## Order

1. RidePilot boolean + backfill + form (needs a migrate and the usual container restart is not needed;
   development mode reloads).
2. Fleet endpoint + token.
3. Puller + timer on 10.0.0.32, first run by hand with a dry-run flag, compare against the 2026-09-11
   state, then enable the timer.
4. Add RC1 and RC2 to RidePilot, or drop them from AVL, so the two lists match.

About a day in all. Until it is built, any vehicle change made on the RidePilot Vehicles page has to be
repeated in `busavl.fleet` by hand, and the portal's fleet-maintenance report will disagree with RidePilot
until it is.

## Access notes (2026-09-11)

- 10.0.0.32 and 10.0.0.40 now accept the 10.0.0.16 SSH key (`ssh philz@10.0.0.32`, `ssh philz@10.0.0.40`).
- On 10.0.0.40 the `dbmojo` account is granted for remote hosts only; on the box itself use
  `sudo mysql busavl`. `mysql -h 127.0.0.1` still counts as localhost and is refused.
- The portal's MariaDB client in the nextcloud container cannot reach 10.0.0.40 (it insists on TLS the
  server does not offer).
