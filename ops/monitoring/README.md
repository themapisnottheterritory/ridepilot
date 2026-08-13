# RidePilot ops monitoring

> Rebuilding the host from scratch? Start with **[../disaster-recovery.md](../disaster-recovery.md)** — this monitoring is the last (verification) step of that runbook.


Host-side monitoring for the RidePilot deployment (Docker host 10.0.0.16, user
`philz`). **The scripts here are the live source** — the host cron and the Claude
Code hook invoke them *in place* from this checkout, so editing a file here (and
committing) changes what actually runs. There are no separate host copies to keep
in sync.

Assumes the repo is checked out at `/home/philz/rptest/ridepilot`. If that path
ever changes, update the two pointers in the install step below.

## Files

| File | Invoked by | Purpose |
|------|-----------|---------|
| `ridepilot-healthcheck.sh` | host crontab, daily 00:30 | Stack health check: containers, app 500s, nginx errors, sidekiq (heartbeat / past-due backlog / scheduler-thread deaths since last boot), scheduler:run cron freshness, disk. |
| `ridepilot-alerts-hook.sh` | Claude Code `SessionStart` hook | Injects the alerts log into context so it gets summarized each session. |

## Runtime files it writes (host, gitignored — regenerated state, not versioned)

- `~/ridepilot-health.log` — full timestamped report each run (trimmed to 4000 lines).
- `~/ridepilot-health-ALERTS.log` — one line **only when something is wrong** (`WACKY — N issue(s): …`). Tail this for problems only.
- `~/ridepilot-health-cron.log` — cron stdout/stderr capture.
- `~/ridepilot-scheduler.log` — written by the separate nightly `scheduler:run` cron (below).

## Install on a fresh host

No copying — point the cron and the hook straight at this checkout. Only the
crontab and the `.claude/settings.local.json` hook live outside git (the latter
is gitignored personal settings), so they are the only things to recreate.

```sh
# ensure the scripts are executable (git preserves the +x bit, but just in case)
chmod +x /home/philz/rptest/ridepilot/ops/monitoring/*.sh

# crontab (user philz) — health check at 00:30, 30 min after the nightly scheduler
crontab -e
```

```cron
PATH=/usr/local/bin:/usr/bin:/bin
# RidePilot nightly scheduler: recurring trips, run status, standby->unmet, GPS archive
0 0 * * * /usr/bin/docker exec ridepilot_app_1 bundle exec rake scheduler:run >> /home/philz/ridepilot-scheduler.log 2>&1
# RidePilot daily health check (runs from the repo checkout). Alerts -> ridepilot-health-ALERTS.log
30 0 * * * /home/philz/rptest/ridepilot/ops/monitoring/ridepilot-healthcheck.sh >> /home/philz/ridepilot-health-cron.log 2>&1
```

Register the `SessionStart` hook in `.claude/settings.local.json` (gitignored),
under a top-level `"hooks"` key:

```json
"hooks": {
  "SessionStart": [
    { "hooks": [ { "type": "command", "command": "/home/philz/rptest/ridepilot/ops/monitoring/ridepilot-alerts-hook.sh", "timeout": 15 } ] }
  ]
}
```

## Notes

- **Repo is the live source**: a `git checkout`/branch switch that changes these
  files changes what cron and the hook run. They're tracked, so `git clean` won't
  remove them, but be aware the running scripts follow the working tree.
- Depends on: `docker` CLI, `python3` (hook JSON emit), a running `ridepilot_app_1`
  for the sidekiq `rails runner` probe. No `jq` required.
- The scheduler-thread-death check counts deaths only **after the last sidekiq boot**
  (`docker logs -t` timestamps + awk compare), so a fixed-and-restarted scheduler does
  not show as a residual alert. See the `sidekiq-connection-pool` context for why this
  check exists (connection_pool 3.0 vs sidekiq 7.3.9).
- Expected containers checked: `ridepilot_{web,app,db,redis,sidekiq,optimizer,osrm}_1`
  and `osm-tiles`. Update the `EXPECTED` list in the script if the compose service set changes.
