#!/usr/bin/env bash
# Nightly reset of the RidePilot TRAINING box (10.0.0.15).
#
#   1. pull last night's production backup and restore it (the standby pull
#      script already does exactly this — "the sync is the reset"),
#   2. scrub every rider to a fictitious one and drop chat / GPS / logs,
#   3. seed trainee drivers and today's runs,
#   4. restart the app so it picks up the restored schema.
#
# Cron on the training box (user philz):
#   30 3 * * * /home/philz/rptest/ridepilot/ops/training/training-reset.sh >> /home/philz/ridepilot-training-reset.log 2>&1
#
# The rake tasks refuse to run unless TRAINING_MODE=true is in the app's
# environment (config/application.yml on the training box). Never install
# this cron on the production box.
set -u
APPDIR=/home/philz/rptest/ridepilot
PULL=$APPDIR/ops/backup/ridepilot-standby-pull.sh
LOG=/home/philz/ridepilot-training-reset.log
log() { echo "$(date '+%F %T') $*"; }

if [ "${SKIP_RESTORE:-0}" != "1" ]; then
  if [ -x "$PULL" ]; then
    log "restoring last production backup"
    "$PULL" || { log "restore FAILED, not scrubbing a half-restored database"; exit 1; }
  else
    log "no pull script at $PULL; run SKIP_RESTORE=1 to scrub+seed the current database"; exit 1
  fi
fi

log "migrating (restored schema may be behind this checkout)"
docker exec ridepilot_app_1 bundle exec rake db:migrate || { log "migrate FAILED"; exit 1; }

log "scrub + seed"
docker exec -e TRAINING_MODE=true ridepilot_app_1 bundle exec rake training:reset || { log "training:reset FAILED"; exit 1; }

log "restarting app (schema cache)"
docker restart ridepilot_app_1 >/dev/null && docker restart ridepilot_sidekiq_1 >/dev/null 2>&1
log "done"
