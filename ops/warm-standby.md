# RidePilot Warm Standby (10.0.0.15)

Turns `10.0.0.15` into a **warm standby** for the production stack on `10.0.0.16`:
an hourly-synced mirror that can take over in minutes if `.16` dies, and doubles
as a **test/staging box** for trying upgrades against real data.

Companion to [disaster-recovery.md](disaster-recovery.md) (the from-scratch
rebuild) — this is the "don't rebuild from scratch, fail over instead" answer to
the single-host risk.

**Status (2026-08-14):** primary-side hourly backup is **live** (`ops/backup/
ridepilot-backup.sh` + cron on `.16`). `.15` reinstalled to Ubuntu 24.04. Standby
setup (phases 0–1) and the pull/failover wiring (phases 2b–3) are pending.

---

## Why one box can be both

The two roles seem to conflict — a failover standby wants *pristine* prod data,
a test box wants you to *mess with* the data. They don't conflict here because
**the hourly sync overwrites `.15`'s database with fresh prod data every run.**
So:

- **As a standby:** `.15` is always ≤1 hour behind prod, ready to serve.
- **As a test box:** test freely; the next hourly sync resets you to a clean prod
  mirror. *The sync is the reset.* (While mid-test, disable the pull cron so it
  doesn't wipe your work; re-enable to return to standby.)

## The failover design that matters: IP takeover

The ~25 driver tablets and the RideAVL app are **hardcoded to `http://10.0.0.16`**
(there is no internal DNS pushed over the tunnel — see the DR runbook). So failover
is **not** "repoint DNS." Instead, when `.16` is down, **`.15` assumes the
`10.0.0.16` address**. Because `.16` is dead there's no IP conflict, and:

- tablets keep working with **zero changes** (they still hit `10.0.0.16`),
- the TLS leaf already lists `IP:10.0.0.16` in its SAN, so HTTPS still validates,
- `rp.internal.gcrpc.org` (pfSense Unbound → `.16`) also resolves correctly.

`.15` keeps its own `10.0.0.15` address normally and *adds* `10.0.0.16` only during
failover.

---

## Data flow

```
  PRIMARY 10.0.0.16                         STANDBY 10.0.0.15
  ┌───────────────────┐   hourly rsync      ┌───────────────────┐
  │ pg_dump -Fc  ─────┼──(standby pulls)───▶│ pg_restore latest │
  │ uploads mirror    │   over ssh          │ uploads → checkout│
  │ → ~/backups/      │                     │ stack pre-built   │
  └───────────────────┘                     └───────────────────┘
   ops/backup/ridepilot-backup.sh            ops/backup/ridepilot-standby-pull.sh
   (cron: 0 * * * *)                          (cron: 20 * * * * — offset)
```

The standby **initiates** the pull (so the primary stores no credentials to the
standby). DB dumps are 6.4 MB, so this is cheap; retention on the primary is 168
hourly dumps (~7 days).

---

## Phases

### Phase 0 — prep `.15`  *(24.04 done)*
```sh
# Docker + compose plugin
sudo apt-get update
sudo apt-get install -y docker.io docker-compose-v2
sudo usermod -aG docker philz    # log out/in after
# git access to the gcrpc repo (deploy key), then:
mkdir -p /home/philz/rptest && cd /home/philz/rptest
git clone git@github.com:themapisnottheterritory/ridepilot.git
cd ridepilot && git checkout master
# ssh key so .15 can pull from .16 (standby initiates):
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ''   # if none
ssh-copy-id philz@10.0.0.16                          # authorize .15 -> .16
```

### Phase 1 — stand up the stack on `.15` (empty)
Follow [disaster-recovery.md](disaster-recovery.md) §4.2–4.3: restore
`config/application.yml` + certs, then `docker compose build && docker compose up -d`.
Leave it running; the pull job (Phase 2b) keeps its data fresh.

### Phase 2a — primary backup  *(DONE — live on `.16`)*
`ops/backup/ridepilot-backup.sh`, hourly cron `0 * * * *`. Writes
`~/backups/db/ridepilot-db-*.dump` (+ `latest.dump` symlink) and mirrors uploads.

### Phase 2b — standby pull  *(install on `.15`)*
`ops/backup/ridepilot-standby-pull.sh` is already in the repo checkout. Install its
cron on `.15`, offset from the producer so it pulls *after* the fresh dump exists:
```cron
PATH=/usr/local/bin:/usr/bin:/bin
# Pull latest prod backup and restore into the standby (~1h fresh). Disable while test-driving .15.
20 * * * * /home/philz/rptest/ridepilot/ops/backup/ridepilot-standby-pull.sh >> /home/philz/backups/standby-pull.log 2>&1
```

### Phase 3 — failover (practice this before you need it)
When `.16` is confirmed down:
```sh
# on .15
# 1) make sure the newest available dump is restored (run the pull once; it tolerates .16 being down)
/home/philz/rptest/ridepilot/ops/backup/ridepilot-standby-pull.sh
# 2) take over the primary IP (adjust interface name; `ip -br addr` to find it)
sudo ip addr add 10.0.0.16/24 dev <iface>
# 3) bring the stack up and verify
cd /home/philz/rptest/ridepilot && docker compose up -d
ops/monitoring/ridepilot-healthcheck.sh && tail -40 ~/ridepilot-health.log
```
Tablets reconnect on their own (same IP). Expect `VERDICT: OK — all clear`.

**Failback** (when `.16` returns): stop the stack on `.15`, `sudo ip addr del
10.0.0.16/24 dev <iface>`, take a final dump from `.15`, restore it onto `.16`,
bring `.16` back up, resume normal sync.

### Phase 4 — test/staging use
Disable the Phase 2b pull cron on `.15`, test whatever you like (OS/gem/Rails
upgrades, migrations) against the real-data copy, then re-enable the cron to snap
back to a clean standby.

---

## Data-freshness & caveats
- **Failover data loss ≤ ~1 hour** (last completed hourly dump). If `.16` is still
  reachable at failover time, run the pull once first to grab the freshest state.
- The hourly restore **replaces** the standby DB — that's why test-mode means
  "pause the cron."
- Retention on `.16`: 168 hourly dumps (~7 days). For longer/offsite retention,
  also copy `~/backups/` somewhere off both boxes.
- `pg_restore --clean --if-exists` logs benign "does not exist, skipping" drops on
  first restore into an empty DB — expected, not an error.
