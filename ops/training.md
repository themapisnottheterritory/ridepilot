# RidePilot training / demo server

A second RidePilot on the warm-standby box **10.0.0.15**, restored from last night's production
backup, with every rider replaced by a fictitious one and a fresh set of trainee runs seeded each
morning. Dispatchers train on the web side at `training.internal.gcrpc.org`; drivers train on a
separate **RideAVL Training** tablet app that only talks to `.15`. Nothing done on it touches
production, and it wipes itself nightly. It doubles as the leadership demo box.

The standby runbook already frames `.15` as "failover + test" with "the sync is the reset"
(see [warm-standby.md](warm-standby.md) §Why one box can be both). This document is the test half.

## What the reset does (`ops/training/training-reset.sh`, cron 03:30)

1. `ops/backup/ridepilot-standby-pull.sh` — pull last night's dump + uploads from `.16` and restore.
2. `rake db:migrate` — the restored schema can be behind the checkout.
3. `rake training:reset` = `training:scrub` + `training:seed` (below).
4. Restart app + sidekiq (a restored/migrated schema is not picked up by a running puma).

`SKIP_RESTORE=1 ops/training/training-reset.sh` scrubs and seeds whatever is loaded, without a
restore. To keep a multi-day scenario, comment the cron out for the week.

### `rake training:scrub` — fictitious riders
- Customers: name from two fixed word lists keyed by id (so "Ada Abbott" stays "Ada Abbott" across
  resets), phone `555-01xx`, no email, shifted birth date, all notes cleared, `public_notes` =
  "TRAINING DATA - fictitious rider", Shah client code → `T<id>`, SMS off.
- Rider addresses keep the **street** (maps, distances and ETAs need it) but lose label, phone and notes.
- Staff and driver home addresses are moved to the depot. Emergency contacts anonymised.
- Trip notes cleared. Chat messages, documents, paper trail, action logs and GPS history deleted.
- Staff logins are the real ones from the backup (trainers sign in as themselves). Driver token
  logins are kept.

### `rake training:seed[N]` — today's class (default 6 trainees)
- Users `trainee01…trainee06`, password `Train-2026!` (override with `TRAINING_PASSWORD=`), each with
  a driver record and a role on provider 1.
- One run per trainee for today, 08:00–17:00, depot to depot, on an active vehicle no other run
  uses today, **3 trips** on random fictitious riders to Walmart on Navarro / Citizens Medical
  Center / the library, manifest published. Yesterday's training runs are removed first.
- `trainee01` also has **yesterday's completed run with a pre-trip defect** (brake fluid), pushed
  to a maintenance event, so today's pre-trip shows the prior-defect card.
- Fixed route: once the fixed-route work packages land, the seed will also create one fixed run
  per route (see `ops/fixed-route-phase1-plan.md`); until then fixed-route training is the
  unit-confirmation + DVIR part of the flow.

**Guard:** every task aborts unless `TRAINING_MODE: 'true'` is in `config/application.yml`. That
key exists only on `.15`. Running the tasks on production does nothing.

`rake training:status` shows what is loaded.

## One-time setup on `.15`

Assumes the stack from [warm-standby.md](warm-standby.md) Phase 1 is up (app, db, sidekiq, web,
osrm, osm-tiles) and the standby pull works.

```sh
cd ~/rptest/ridepilot && git pull
# config/application.yml (gitignored) — add:
#   TRAINING_MODE: 'true'
# and make sure NO Twilio / SMTP credentials are present, so nothing real gets texted or mailed.
docker restart ridepilot_app_1 ridepilot_sidekiq_1
ops/training/training-reset.sh            # first restore + scrub + seed; watch the output
crontab -e   # 30 3 * * * /home/philz/rptest/ridepilot/ops/training/training-reset.sh >> /home/philz/ridepilot-training-reset.log 2>&1
```

Web name and TLS, per the house standard (internal CA on `.23`):
- DNS `training.internal.gcrpc.org → 10.0.0.15` on pfSense Unbound.
- Leaf cert `training.key/.crt` minted from `~/plane-tls/` on `.23` (SAN = DNS name + IP 10.0.0.15),
  dropped into `/home/philz/ridepilot-ops/certs` on `.15`, `docker/web/nginx.conf` server_name set
  to the training name, web container recreated.
- The web layout shows an orange **TRAINING SERVER** bar on every page when `TRAINING_MODE` is set,
  so a dispatcher can never mistake the two tabs.

## Tablet: RideAVL Training

Separate Android flavour in rideavl-v2, installs beside the real app:
- `npm run apk:training` → `android/app/build/outputs/apk/training/debug/app-training-debug.apk`.
  (`npm run apk` builds the production flavour.)
- App id `com.victoriatransit.rideavl.training`, name **RideAVL Training**, version suffix
  `-training`, every screen has an orange **TRAINING** bar, all URLs point at `10.0.0.15`.
- Tablets reach `.15` over the same WireGuard tunnel as `.16`; check the pfSense rule allows it.
- Install over USB: `adb install -r app-training-debug.apk`, or serve the file from the training
  box like the pilot APK.

## Running a class

1. Morning: confirm the reset ran (`tail ~/ridepilot-training-reset.log`) or run it by hand.
2. Hand each trainee a tablet with RideAVL Training and a `traineeNN` login.
3. Driver flow per `~/ridepilot-ops/driver-app-training.md`: confirm unit → pre-trip DVIR
   (trainee01 sees the prior defect) → manifest → stops → post-trip → end run.
4. Dispatcher flow on `training.internal.gcrpc.org`: watch the runs, the chat message when a trainee
   takes a different unit, the run's action log, the pre-run inspection report with photo.
5. Tomorrow it is all gone.
