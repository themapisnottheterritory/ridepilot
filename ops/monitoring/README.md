# RidePilot ops monitoring

Backup / source-of-truth for the host-side monitoring scripts. These run on the
Docker host (10.0.0.16, user `philz`), **not** inside the repo or a container —
this directory exists so a host rebuild can recover them. Editing here does
nothing until you copy the file to the host and (re)install the cron / hook.

## Files

| File | Installed at | Purpose |
|------|--------------|---------|
| `ridepilot-healthcheck.sh` | `/home/philz/ridepilot-healthcheck.sh` | Daily stack health check (containers, app 500s, nginx errors, sidekiq scheduler/backlog, scheduler cron freshness, disk). |
| `ridepilot-alerts-hook.sh` | `/home/philz/ridepilot-alerts-hook.sh` | Claude Code `SessionStart` hook: injects the alerts log into context so it gets summarized each session. |

## Runtime files it writes (host, gitignored — not backed up here)

- `~/ridepilot-health.log` — full timestamped report each run (trimmed to 4000 lines).
- `~/ridepilot-health-ALERTS.log` — one line **only when something is wrong** (`WACKY — N issue(s): …`). Tail this for problems only.
- `~/ridepilot-health-cron.log` — cron stdout/stderr capture.
- `~/ridepilot-scheduler.log` — written by the separate nightly `scheduler:run` cron (see below).

## Install on a fresh host

```sh
# 1) place the scripts
cp ops/monitoring/ridepilot-healthcheck.sh  /home/philz/ridepilot-healthcheck.sh
cp ops/monitoring/ridepilot-alerts-hook.sh  /home/philz/ridepilot-alerts-hook.sh
chmod +x /home/philz/ridepilot-healthcheck.sh /home/philz/ridepilot-alerts-hook.sh

# 2) crontab (user philz) — health check at 00:30, 30 min after the nightly scheduler
crontab -e
```

Crontab entries (the scheduler entry is a separate pre-existing job, kept for completeness):

```cron
PATH=/usr/local/bin:/usr/bin:/bin
# RidePilot nightly scheduler: recurring trips, run status, standby->unmet, GPS archive
0 0 * * * /usr/bin/docker exec ridepilot_app_1 bundle exec rake scheduler:run >> /home/philz/ridepilot-scheduler.log 2>&1
# RidePilot daily health check: containers, 500s, sidekiq scheduler/backlog, scheduler cron, disk. Alerts -> ridepilot-health-ALERTS.log
30 0 * * * /home/philz/ridepilot-healthcheck.sh >> /home/philz/ridepilot-health-cron.log 2>&1
```

```sh
# 3) register the SessionStart hook for Claude Code sessions in this project.
#    Lives in .claude/settings.local.json (gitignored, host-local), under "hooks":
```

```json
"hooks": {
  "SessionStart": [
    { "hooks": [ { "type": "command", "command": "/home/philz/ridepilot-alerts-hook.sh", "timeout": 15 } ] }
  ]
}
```

## Notes

- Depends on: `docker` CLI, `python3` (hook JSON emit), a running `ridepilot_app_1`
  for the sidekiq `rails runner` probe. No `jq` required.
- The scheduler-thread-death check counts deaths only **after the last sidekiq boot**
  (`docker logs -t` timestamps + awk compare), so a fixed-and-restarted scheduler does
  not show as a residual alert. See the `sidekiq-connection-pool` context for why that
  check exists (connection_pool 3.0 vs sidekiq 7.3.9).
- Expected containers checked: `ridepilot_{web,app,db,redis,sidekiq,optimizer,osrm}_1`
  and `osm-tiles`. Update the `EXPECTED` list in the script if the compose service set changes.
