# RidePilot Disaster Recovery Runbook

**Audience:** a competent Linux/Docker/Rails operator who knows *nothing* about this
particular deployment. This document assumes no prior context. It is deliberately boring
and explicit. Follow it top to bottom.

**Goal:** rebuild the RidePilot service on a fresh host and get it serving Victoria
Transit dispatchers and driver tablets again, then prove it with the health check.

**Last verified against production:** 2026-08-13.

---

## 0. In an emergency, read this first

- The whole app runs as a **Docker Compose stack on one host: `10.0.0.16`** (user `philz`).
  Lose that host and you rebuild from this doc + the git repo + your data backups.
- The **git repo is the source of truth for all code and most config.** Remote:
  `git@github.com:themapisnottheterritory/ridepilot.git` (GitHub org `themapisnottheterritory`,
  referred to internally as **gcrpc**). Working branch: **`master`**.
- **Three things are NOT in git** and must come from a backup or be recreated (see §3):
  the database, user-uploaded files, and the secrets/certs. Everything else you can
  `git clone`.
- The app is **not exposed to the internet.** It is reached over the LAN and over a
  WireGuard tunnel on the pfSense firewall. Nothing here needs a public IP or public DNS.

---

## 1. System at a glance

### The one host — `10.0.0.16`
Runs Docker + Docker Compose. The repo is checked out at
`/home/philz/rptest/ridepilot`. `docker compose` is run from there.

### Containers (compose services + one standalone)
| Container | Compose service | What it is | Notable |
|-----------|-----------------|-----------|---------|
| `ridepilot_web_1` | `web` | nginx, terminates TLS, proxies to Rails, serves `/tiles` and `/osrm` | image bakes `public/`; **no repo mount** |
| `ridepilot_app_1` | `app` | Rails 7.1 / Ruby 3.2, Puma single mode | runs `RAILS_ENV=development` (see §6) |
| `ridepilot_db_1` | `db` | PostgreSQL 9.4 + PostGIS (`mdillon/postgis:9.4`) | **the crown jewel** — database `ridepilot` |
| `ridepilot_redis_1` | `redis` | Redis | Sidekiq queues + Rails cache; mostly regenerable |
| `ridepilot_sidekiq_1` | `sidekiq` | Sidekiq background workers | GPS polling, ETA, distance, scheduler jobs |
| `ridepilot_optimizer_1` | `optimizer` | Python OR-Tools + OSRM route optimizer sidecar (HTTP) | called by the app over HTTP |
| `ridepilot_osrm_1` | `osrm` | OSRM routing backend | serves distances/durations/routing |
| `osm-tiles` | *(standalone, not in compose)* | `overv/openstreetmap-tile-server`, Texas import | serves raster map tiles; big data volumes |

### Other hosts / services it depends on
- **`10.0.0.23`** — the **GCRPC Internal Root CA** lives here at `~/plane-tls/`
  (`gcrpc-root.crt` / `gcrpc-root.key`). This CA signs the TLS leaf cert. Workstations
  already trust the root org-wide.
- **pfSense firewall** — hosts the **WireGuard tunnel** the ~25 driver tablets use to
  reach `10.0.0.16`, and the **Unbound DNS resolver** that maps
  `rp.internal.gcrpc.org → 10.0.0.16` for workstation browsers.
- **Microsoft Entra ID / Azure** — O365 SSO for web dispatchers (app registration in the
  gcrpc.org tenant). Local password login is kept as a fallback.
- **Intune** — manages the tablets and their always-on per-app VPN (Andrew administers).
- **GitHub (gcrpc org)** — the code.

### How a request flows
Tablet/browser → nginx (`web`, TLS on :443, plain :80) → Rails (`app`) → Postgres (`db`).
Map tiles and routing are proxied by nginx to `osm-tiles` and `osrm`. GPS/ETA/optimization
run as Sidekiq jobs and the Python `optimizer` sidecar.

---

## 2. What lives where (inventory)

| Thing | Location | In git? |
|-------|----------|---------|
| App code, `docker-compose.yml`, `docker/web/nginx.conf`, Gemfile.lock, initializers | repo | ✅ yes |
| Committed pilot APK + QR | `public/rideavl-pilot.apk`, `public/rideavl-apk-qr.png` | ✅ yes |
| Monitoring scripts + this runbook | `ops/` | ✅ yes |
| **Secrets** — `config/application.yml`, DB password in `config/database.yml` | repo checkout on host | ⚠️ gitignored / host-only |
| **TLS leaf cert + key** | `/home/philz/ridepilot-ops/certs/` | ⚠️ host-only |
| **Database** | Docker volume `ridepilot_postgres_data` | ❌ **no — back it up** |
| **User uploads** (customer/provider photos, DVIR photos) | `public/system/` in the checkout | ❌ **no — back it up** |
| **Host crontab** (`scheduler:run`, health check) | `crontab -l` for user `philz` | ⚠️ documented here, host-only |
| **Claude Code session hook** | `.claude/settings.local.json` | ⚠️ gitignored, host-only |
| Map tiles / OSRM data | volumes `osm-tile-db`, `osm-tile-cache`, and the OSRM data | ❌ no — regenerable from OSM extract (slow) |
| Redis data | volume `ridepilot_redis` | ❌ no — regenerable |
| Runtime gem bundle | volume `ridepilot_bundle_cache` | ❌ no — rebuilt by `bundle install` |

### The secrets in `config/application.yml` (key names only)
`GOOGLE_API_KEY`, `GOOGLE_ROAD_API_KEY`, `GOOGLE_TRIP_PLANNER_URL`,
`GOOGLE_DIRECTIONS_WAYPOINT_LIMIT`, `GOOGLE_ROAD_POINT_LIMIT`, `NOMINATIM_URL`,
`OPEN_TRIP_PLANNER_URL`, `OSRM_URL`, `TRIP_PLANNER_TYPE`, `RIDEPILOT_HOST`,
`SMTP_MAIL_*` (address/domain/port/user/password), `SYSTEM_ADMIN_EMAIL`,
`SYSTEM_ADMIN_PASSWORD`, `SYSTEM_SEND_FROM_ADDRESS`.
Keep a copy of this file in your password manager / secrets store. For self-hosted
routing set `TRIP_PLANNER_TYPE: OSRM` and `OSRM_URL: http://osrm:5000`.

---

## 3. Backup status — READ THIS

> ✅ **As of 2026-08-14 an automated hourly backup is live** — `ops/backup/
> ridepilot-backup.sh` runs from the host crontab (`0 * * * *`) and writes a PostGIS
> dump + uploads mirror to `/home/philz/backups/` (168 hourly dumps retained, ~6.4 MB
> each). This is also the feed for the `.15` warm standby — see
> [warm-standby.md](warm-standby.md). **Remaining gap:** those backups still live on
> `10.0.0.16`; copy `~/backups/` off-box (the standby pull does this hourly once `.15`
> is wired) so a loss of `.16` doesn't take the backups with it.

### Create backups (run on the host)
```sh
# Database (PostGIS 9.4) — custom-format dump
docker exec ridepilot_db_1 pg_dump -U postgres -Fc ridepilot \
  > /home/philz/backups/ridepilot-db-$(date +%F).dump

# Uploads (small today, ~500K)
tar czf /home/philz/backups/ridepilot-uploads-$(date +%F).tgz \
  -C /home/philz/rptest/ridepilot public/system

# Secrets + certs (store OFF this host, encrypted)
cp /home/philz/rptest/ridepilot/config/application.yml /home/philz/backups/
cp -r /home/philz/ridepilot-ops/certs /home/philz/backups/certs
```
Then copy `/home/philz/backups/` to a **different machine**. A backup that only lives on
`10.0.0.16` does not protect you from losing `10.0.0.16`.

**Suggested cron (not yet installed):**
```cron
0 1 * * * docker exec ridepilot_db_1 pg_dump -U postgres -Fc ridepilot > /home/philz/backups/ridepilot-db-$(date +\%F).dump 2>> /home/philz/backups/backup.log
```

---

## 4. Full recovery — bare host to running stack

Prerequisites on the fresh host: Docker + Docker Compose, git with access to the gcrpc
repo (SSH deploy key), and your backup files.

### 4.1 Get the code
```sh
mkdir -p /home/philz/rptest && cd /home/philz/rptest
git clone git@github.com:themapisnottheterritory/ridepilot.git
cd ridepilot && git checkout master
```
> If the checkout path differs from `/home/philz/rptest/ridepilot`, update the crontab and
> the Claude hook paths in §4.7–4.8 accordingly.

### 4.2 Restore secrets and certs
The clone does NOT include gitignored config — the app won't boot without it (a
missing `config/database.yml` throws `Cannot load database configuration` at startup).
List them on a working box with `git status --ignored config/`; as of 2026-08-14 they are
**`application.yml`, `database.yml`, `master.key`, `credentials.yml.enc`** (all four).
```sh
for f in application.yml database.yml master.key credentials.yml.enc; do
  cp /path/to/backup/config/$f config/$f
done
chmod 600 config/master.key
mkdir -p /home/philz/ridepilot-ops
cp -r /path/to/backup/certs /home/philz/ridepilot-ops/certs
chmod 600 /home/philz/ridepilot-ops/certs/rp.key
```
If the TLS leaf is lost or expired, mint a new one from the Internal Root CA on
`10.0.0.23` (`~/plane-tls/`): leaf CN `rp.internal.gcrpc.org`, **SAN must include both**
`DNS:rp.internal.gcrpc.org` and `IP:10.0.0.16`, 825-day. See the GCRPC house-standard
TLS procedure. Place the leaf + fullchain + key in `~/ridepilot-ops/certs/` as
`rp.key`, `rp.crt`, `rp-fullchain.crt`.

### 4.3 Build and start the stack
The Docker build context is the repo's PARENT and needs the `engines/` sibling
(path-dependency gems, NOT in the repo). On Compose v2 hosts, force underscore container
names so the ops scripts match, and bring `app` up alone first to avoid the shared-gem-
volume populate race. (Full explanations in [warm-standby.md](warm-standby.md) → "Build
gotchas".)
```sh
# engines sibling (from a working box or backup)
cp -r /path/to/engines /home/philz/rptest/engines      # reporting + translation_engine
cd /home/philz/rptest/ridepilot
export COMPOSE_COMPATIBILITY=true                       # v2 -> underscore names (ridepilot_db_1)
docker compose build
docker compose up -d app                                # populate bundle_cache alone first
sleep 25
docker compose up -d                                    # then the rest
```
This creates fresh (empty) `ridepilot_postgres_data`, `ridepilot_redis`, and
`ridepilot_bundle_cache` volumes.

### 4.4 Restore the database
```sh
# ensure the empty database exists (PostGIS is available in the mdillon image)
docker exec ridepilot_db_1 psql -U postgres -c "CREATE DATABASE ridepilot;" 2>/dev/null || true
# restore the dump
docker exec -i ridepilot_db_1 pg_restore -U postgres -d ridepilot --clean --if-exists \
  < /path/to/backup/ridepilot-db-YYYY-MM-DD.dump
```
> PostGIS note: the dump carries its PostGIS objects; the `mdillon/postgis:9.4` image
> ships PostGIS so the extension is available. If restore complains about the `postgis`
> extension, `CREATE EXTENSION postgis;` in the db first, then re-run.

If you have **no** database backup (first-ever setup), instead initialize schema:
```sh
docker exec ridepilot_app_1 bundle exec rails db:create db:schema:load db:seed
```

### 4.5 Restore uploads
```sh
tar xzf /path/to/backup/ridepilot-uploads-YYYY-MM-DD.tgz \
  -C /home/philz/rptest/ridepilot
```

### 4.6 Restart app + workers to pick up restored data/config
```sh
docker compose restart app sidekiq
```

### 4.7 Reinstall the host crontab (user `philz`)
```sh
crontab -e
```
```cron
PATH=/usr/local/bin:/usr/bin:/bin
# Nightly scheduler: recurring trips, run status, standby->unmet, GPS archive
0 0 * * * /usr/bin/docker exec ridepilot_app_1 bundle exec rake scheduler:run >> /home/philz/ridepilot-scheduler.log 2>&1
# Daily health check (runs from the repo checkout)
30 0 * * * /home/philz/rptest/ridepilot/ops/monitoring/ridepilot-healthcheck.sh >> /home/philz/ridepilot-health-cron.log 2>&1
```
> There is **no cron inside any container** — the scheduler runs from the host crontab.
> If this crontab is missing, recurring trips silently stop generating. See
> `ops/monitoring/README.md`.

### 4.8 (Optional) Claude Code session hook
Only if you use Claude Code here. In `.claude/settings.local.json` (gitignored), add:
```json
"hooks": { "SessionStart": [ { "hooks": [
  { "type": "command", "command": "/home/philz/rptest/ridepilot/ops/monitoring/ridepilot-alerts-hook.sh", "timeout": 15 }
] } ] }
```

### 4.9 Map tiles (only if the tile host was lost)
The `osm-tiles` container and its `osm-tile-db` / `osm-tile-cache` volumes hold a Texas
OSM import. If lost, re-import from a Texas `.osm.pbf` extract into
`overv/openstreetmap-tile-server` — this is **slow (hours)** but fully regenerable and
not urgent; maps just render gray until it finishes. nginx proxies `/tiles` and `/osrm`,
so no app change is needed once the tile/osrm containers are back.

---

## 5. Final verification

```sh
/home/philz/rptest/ridepilot/ops/monitoring/ridepilot-healthcheck.sh
tail -40 /home/philz/ridepilot-health.log
```
**Expect `VERDICT: OK — all clear`** with: all 8 containers up, no app 500s, clean nginx
log, Sidekiq heartbeat fresh + `past_due=0` + 0 scheduler-thread deaths, recurring-trip
`scheduled_through` in the future with future trips present, scheduler cron fresh, disk
< 85%. Then spot-check in a browser: log in at `https://rp.internal.gcrpc.org/` (or
`http://10.0.0.16/`), open a customer, open a trip with a map, confirm tiles + a distance
estimate render.

---

## 6. Landmines (things that will cost you a day if you don't know them)

These are hard-won. Most of the code fixes are **already in the repo** — the point here is
to explain *why* they exist so nobody "cleans them up."

### Runtime / environment
- **The app runs `RAILS_ENV=development` in production.** Unusual, but true. Consequence:
  model/code edits auto-reload per request (no restart needed), but **boot-time
  initializers still require an app restart** to take effect. Assets are not
  precompiled/served the production way. Don't "fix" this to production without testing —
  several behaviors depend on it.
- **The scheduler is a HOST cron, not container cron.** See §4.7. No container runs cron.
- **Secrets** live in `config/application.yml` (gitignored). Missing it → boots with blank
  API keys / SMTP / admin creds and self-hosted routing off.

### Ruby 3 / Rails 7 upgrade shims (in `config/initializers/`, already committed)
- `sorted_set_shim.rb` — Ruby 3 removed `SortedSet`; ice_cube 0.6.14 needs it for
  recurring-trip scheduling.
- `ice_cube_psych4_compat.rb` — Psych 4 `safe_load` rejects the symbol/time keys in
  ice_cube schedule YAML; this restores `unsafe_load` for that trusted data.
- `paperclip_rails71_fix.rb` — Rails 7.1 renamed a validator constant Paperclip 6.1 uses.
- `rubyxl_convenience.rb` — RubyXL 3.x split its convenience API into a separate require;
  needed for the NTD `.xlsx` report.
- **`belongs_to` is required by default in Rails 7.** Several models needed
  `optional: true` (Run, RepeatingTrip, and the ridership-mobility join models). Symptom
  of a missing one: `"... is invalid"` / `"... must exist"` on a create form.
- **`connection_pool` is pinned `~> 2.5` in the Gemfile.** connection_pool 3.0 breaks
  Sidekiq 7.3.9's scheduler thread (`wrong number of arguments (given 1, expected 0)`),
  which silently kills all scheduled/retry jobs. Do **not** unpin it. The daily health
  check watches for this specifically.

### Operational gotchas
- **Recreate a single compose service with `--no-deps`**, e.g.
  `docker compose up -d --no-deps --force-recreate web`. Without it, Compose also recreates
  dependencies (redis/db), yanking connections out from under long-running Sidekiq.
- **The nginx config is a single-file bind mount.** After editing `docker/web/nginx.conf`,
  a plain reload won't pick it up (inode swap) — you must
  `docker compose up -d --no-deps --force-recreate web`.
- **`ridepilot_bundle_cache` volume** holds gems added at runtime (`bundle install` after
  the image was built, e.g. the connection_pool downgrade). Don't wipe it without a
  rebuild; a full image rebuild re-bakes the current Gemfile.lock.
- **Tablets and the driver app use the IP `http://10.0.0.16`, not DNS.** There is no
  internal DNS pushed over the WireGuard tunnel. `rp.internal.gcrpc.org` is a
  workstation-browser convenience only (pfSense Unbound). The TLS leaf covers **both** the
  name and the IP, so HTTPS-by-IP validates.

---

## 7. "If X is broken, look here"

| Symptom | Likely cause | Where to look |
|---------|--------------|---------------|
| Recurring trips stopped generating | host `scheduler:run` cron not firing | `crontab -l`, `~/ridepilot-scheduler.log` |
| Scheduled/retry/GPS jobs not running; backlog grows | Sidekiq scheduler thread died (connection_pool) | `docker logs ridepilot_sidekiq_1`, health check `past_due` |
| Maps render gray | tiles/osrm proxy or `osm-tiles` down | `docker ps`, nginx `/tiles` `/osrm`, §4.9 |
| No distance/ETA on trips | `TRIP_PLANNER_TYPE`/`OSRM_URL` unset, or `osrm` down | `config/application.yml`, `ridepilot_osrm_1` |
| Cert warning in browser | leaf expired or missing IP SAN; workstation missing root CA | §4.2, `~/ridepilot-ops/certs`, CA on `10.0.0.23` |
| `"... is invalid" / "must exist"` on a create form | a `belongs_to` missing `optional: true` | the model in `app/models`, §6 |
| Report `.xlsx` 500s | RubyXL convenience require | `config/initializers/rubyxl_convenience.rb` |
| `"Provider is not available for the trip"` | pickup outside the provider's operating hours | Provider settings → operating hours (Victoria = 6am–7pm) |
| Tablet can't reach the app | not on the WireGuard tunnel, or using DNS name instead of IP | tunnel status (Intune), use `http://10.0.0.16` |
| A boot-time fix "isn't taking" | it's an initializer; needs an app restart | `docker compose restart app sidekiq` |

---

## 8. Contacts & external dependencies
- **Code:** GitHub `themapisnottheterritory/ridepilot` (gcrpc org), branch `master`.
- **Internal Root CA:** `10.0.0.23:~/plane-tls/` (house TLS standard).
- **Network / DNS / VPN:** pfSense (WireGuard tunnel for tablets, Unbound for internal DNS).
- **Tablets / MDM:** Intune (Andrew).
- **SSO:** Microsoft Entra ID, gcrpc.org tenant (web-dispatcher login; local password fallback exists).
