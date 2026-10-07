#!/usr/bin/env bash
# Restart RidePilot with a countdown banner for signed-in staff, then check it is
# back. Two kinds of restart:
#
#   full (default)  stops and starts the app and Sidekiq containers: about 15 s
#                   when nobody can use RidePilot. Staff see a banner counting
#                   down to the time, "restarting now", then "RidePilot is back".
#                   Needed for config/puma.rb, Gemfile, docker or nginx changes.
#   --phased        Puma replaces its worker processes one at a time while the
#                   others keep serving: nobody is interrupted and no banner is
#                   shown. Enough for ordinary code changes (app/, config/locales,
#                   views). Refused when the change needs a full restart.
#
#   ops/restart/ridepilot-restart.sh --at 18:00 [--message "RidePilot will restart for updates"]
#   ops/restart/ridepilot-restart.sh --in 5
#   ops/restart/ridepilot-restart.sh --phased
#   add --dry-run to check everything and post nothing.
#   --cancel takes a posted notice down; a countdown in progress then stops
#   without restarting (it checks every 10 s). Only one restart runs at a time.
#
# Before anything is posted it checks: code committed, the new code boots (a
# separate `rails runner`, so a broken change never takes the live app down), and
# nginx's config is valid. After the restart it waits up to 3 minutes for RidePilot
# to answer; if it doesn't, the banner says so, an alert line goes to
# ~/ridepilot-health-ALERTS.log and the script exits 1. Log: ~/ridepilot-restart.log
#
# Environment overrides (used by the staging test on .15): APP, SIDEKIQ, WEB, APPDIR, URL.
set -uo pipefail
APP=${APP:-ridepilot_app_1}
SIDEKIQ=${SIDEKIQ-ridepilot_sidekiq_1}   # empty = no Sidekiq container (staging)
WEB=${WEB:-ridepilot_web_1}
APPDIR=${APPDIR:-/home/philz/rptest/ridepilot}
URL=${URL:-http://localhost:3000/}
LOG=${LOG:-$HOME/ridepilot-restart.log}
ALERTS=${ALERTS:-$HOME/ridepilot-health-ALERTS.log}
NOTICE_DIR=/var/www/notice
MESSAGE="RidePilot will restart for updates"
AT=""; IN=""; PHASED=0; DRY=0; CANCEL=0; FORCE=0

log() { echo "$(TZ=America/Chicago date '+%F %T %Z') $*" | tee -a "$LOG"; }
die() { log "STOP: $*"; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --at) AT="$2"; shift 2 ;;
    --in) IN="$2"; shift 2 ;;
    --message) MESSAGE="$2"; shift 2 ;;
    --phased) PHASED=1; shift ;;
    --dry-run) DRY=1; shift ;;
    --cancel) CANCEL=1; shift ;;
    --force) FORCE=1; shift ;;   # skip the "everything committed" check
    *) die "unknown option $1 (see the top of this file)" ;;
  esac
done

post_notice() {   # $1 = epoch seconds of the restart, $2 = "late" when it hasn't come back
  local iso label late=false
  [ "${2:-}" = late ] && late=true
  iso=$(date -u -d "@$1" '+%Y-%m-%dT%H:%M:%SZ')
  label=$(TZ=America/Chicago date -d "@$1" '+%-l:%M %p')
  printf '{"at":"%s","label":"%s","message":"%s","late":%s}\n' "$iso" "$label" "${MESSAGE//\"/}" "$late" |
    docker exec -i "$WEB" sh -c "mkdir -p $NOTICE_DIR && cat > $NOTICE_DIR/restart-notice.json.tmp && mv $NOTICE_DIR/restart-notice.json.tmp $NOTICE_DIR/restart-notice.json"
}
take_down_notice() { docker exec "$WEB" rm -f "$NOTICE_DIR/restart-notice.json"; }

if [ "$CANCEL" = 1 ]; then
  # the countdown below checks every 10 s that its notice is still up, so taking
  # it down also stops a restart that is already counting down
  take_down_notice && log "notice taken down: any countdown in progress stops within 10 s"; exit 0
fi

# one restart at a time
exec 9>"${LOCK:-$HOME/ridepilot-restart.lock}"
flock -n 9 || die "another ridepilot-restart is already running (see $LOG)"

# ---- checks before anything is posted --------------------------------------
cd "$APPDIR" || die "no $APPDIR"
docker ps --format '{{.Names}}' | grep -qx "$APP" || die "$APP is not running"
if [ "$FORCE" = 0 ] && [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  die "uncommitted changes in $APPDIR: commit first so the footer version names the live code (or --force)"
fi
# 60 s: the first page after a JS/CSS change recompiles the asset bundle (development mode)
running=$(curl -s -m 60 "$URL" -L | grep -o 'Version [^<(]*([0-9a-f]*)' | grep -o '([0-9a-f]*)' | tr -d '()')
head=$(git rev-parse --short=8 HEAD)
log "running build ${running:-unknown}, HEAD $head"

if [ "$PHASED" = 1 ]; then
  [ -n "$running" ] || die "can't read the running build from the footer, so can't tell what changed: use a full restart"
  # nginx.conf is applied by a reload below, and docker-compose.yml only by
  # recreating containers (neither kind of restart does that), so neither
  # needs a full restart
  needs_full=$(git diff --name-only "$running" HEAD -- config/puma.rb Gemfile Gemfile.lock docker/app config/environments config/initializers config/application.rb 2>/dev/null)
  [ -z "$needs_full" ] || die "these changes need a full restart, not --phased: $(echo $needs_full)"
  started=$(docker inspect -f '{{.State.StartedAt}}' "$APP")
  workers=$(docker logs --since "$started" "$APP" 2>&1 | grep -o 'Process workers: [0-9]*' | tail -1 | grep -o '[0-9]*$')
  [ -n "$workers" ] || die "Puma isn't in cluster mode (workers), so there is nothing to phase: use a full restart"
fi

log "checking the new code boots (separate process; the live app keeps running)"
docker exec "$APP" bin/rails runner 'puts "boot-ok"' 2>/dev/null | grep -q boot-ok || die "the new code does not boot: fix it before restarting (try: docker exec $APP bin/rails runner 'puts 1')"
# nginx must see the repo's nginx.conf (it didn't from 2026-10-05 to 10-07: the
# file itself was mounted, and git's new copy never reached the container)
if [ -f docker/web/nginx.conf ] && [ "$WEB" = ridepilot_web_1 ]; then
  want=$(md5sum < docker/web/nginx.conf | cut -c1-32)
  seen=$(docker exec "$WEB" sh -c 'md5sum < /etc/nginx/conf.d/nginx.conf' 2>/dev/null | cut -c1-32)
  [ "$want" = "$seen" ] || die "nginx in $WEB isn't reading docker/web/nginx.conf (recreate it once: docker-compose up -d --no-deps web)"
fi
docker exec "$WEB" nginx -t >/dev/null 2>&1 || die "nginx config test failed (docker exec $WEB nginx -t)"
if [ -n "$running" ] && [ -n "$(git diff --name-only "$running" HEAD -- docker-compose.yml 2>/dev/null)" ]; then
  log "note: docker-compose.yml changed since $running; a restart doesn't apply it: recreate the service (docker-compose up -d --no-deps <service>)"
fi

if [ "$DRY" = 1 ]; then log "dry run: all checks passed, nothing posted or restarted"; exit 0; fi

# apply nginx.conf changes: a reload is graceful (open connections finish)
docker exec "$WEB" nginx -s reload >/dev/null 2>&1 && log "nginx reloaded" || log "nginx reload reported an error (config tested fine): check docker logs $WEB"

wait_back() {   # up to 180 s for the app to answer with a 200/302
  local i code
  for i in $(seq 1 90); do
    code=$(curl -s -o /dev/null -w '%{http_code}' -m 5 "$URL")
    case "$code" in 200|302) return 0 ;; esac
    sleep 2
  done
  return 1
}

# ---- phased: no banner, workers swap one at a time --------------------------
if [ "$PHASED" = 1 ]; then
  log "phased restart: replacing $workers Puma workers one at a time"
  since=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  docker kill -s USR1 "$APP" >/dev/null || die "could not signal $APP"
  for i in $(seq 1 120); do
    booted=$(docker logs --since "$since" "$APP" 2>&1 | grep -c 'booted.*phase')
    [ "$booted" -ge "$workers" ] && break
    sleep 5
  done
  [ "$booted" -ge "$workers" ] || { echo "$(date -u '+%F %T UTC') ridepilot-restart: only $booted of $workers workers rebooted after phased restart" >> "$ALERTS"; die "only $booted of $workers workers came back within 10 minutes: check docker logs $APP"; }
  wait_back || { echo "$(date -u '+%F %T UTC') ridepilot-restart: app not answering after phased restart" >> "$ALERTS"; die "app not answering after phased restart"; }
  v=$(curl -s -m 60 "$URL" -L | grep -o 'Version [^<]*' | head -1)
  log "all $workers workers replaced; serving: $v"
  exit 0
fi

# ---- full: banner, countdown, restart ---------------------------------------
if [ -n "$AT" ]; then
  target=$(TZ=America/Chicago date -d "today $AT" +%s) || die "can't read --at $AT (use HH:MM, Central)"
  [ "$target" -gt "$(date +%s)" ] || die "--at $AT is already past"
elif [ -n "$IN" ]; then
  target=$(( $(date +%s) + IN * 60 ))
else
  target=$(( $(date +%s) + 5 * 60 ))
fi
post_notice "$target" || die "could not post the notice to $WEB"
log "notice posted: restart at $(TZ=America/Chicago date -d "@$target" '+%-l:%M %p %Z'); staff see it within 30 s"

n=0
while [ "$(date +%s)" -lt "$target" ]; do
  if [ $((n % 10)) -eq 0 ] && ! docker exec "$WEB" test -f "$NOTICE_DIR/restart-notice.json"; then
    log "notice was taken down: restart called off, nothing restarted"; exit 0
  fi
  n=$((n+1)); sleep 1
done

log "restarting $APP and $SIDEKIQ (30 s for requests and jobs to finish)"
docker restart -t 30 "$APP" ${SIDEKIQ:+"$SIDEKIQ"} >/dev/null || log "docker restart reported an error; waiting to see if the app answers"
if wait_back; then
  v=$(curl -s -m 60 "$URL" -L | grep -o 'Version [^<]*' | head -1)
  log "back after $(( $(date +%s) - target )) s: $v"
  # leave the notice up 3 minutes so every open page notices RidePilot is back
  sleep 180; take_down_notice; log "notice taken down"
  exit 0
else
  MESSAGE="RidePilot is taking longer than expected to come back. I.T. has been alerted"
  post_notice "$target" late
  echo "$(date -u '+%F %T UTC') ridepilot-restart: app not answering 3 min after restart" >> "$ALERTS"
  die "app not answering 3 minutes after the restart: check docker logs $APP"
fi
