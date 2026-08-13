#!/usr/bin/env bash
# RidePilot daily stack health check.
# Appends a full timestamped report to $LOG; on any anomaly also writes a
# one-line entry to $ALERTS (tail that file to see only problems).
# Installed via host crontab (user philz). Companion to the scheduler:run cron.
# Related context: memory sidekiq-connection-pool (the scheduler-thread bug this watches for).
set -uo pipefail
export PATH=/usr/local/bin:/usr/bin:/bin

LOG=/home/philz/ridepilot-health.log
ALERTS=/home/philz/ridepilot-health-ALERTS.log
TS="$(date '+%Y-%m-%d %H:%M:%S %Z')"
BODY="$(mktemp)"
WACKY=()

sec() { printf '\n-- %s\n' "$1" >>"$BODY"; }

# 1) containers ------------------------------------------------------------
sec "containers"
EXPECTED="ridepilot_web_1 ridepilot_app_1 ridepilot_db_1 ridepilot_redis_1 ridepilot_sidekiq_1 ridepilot_optimizer_1 osm-tiles ridepilot_osrm_1"
UP="$(docker ps --format '{{.Names}}' 2>/dev/null)"
echo "$UP" >>"$BODY"
for c in $EXPECTED; do
  echo "$UP" | grep -qx "$c" || WACKY+=("container down: $c")
done

# 2) app 500s / exceptions -------------------------------------------------
sec "app 500s/exceptions (last 3000 log lines)"
APPERR="$(docker exec ridepilot_app_1 sh -c 'tail -3000 /var/www/ridepilot/log/development.log 2>/dev/null | grep -E "Completed 5[0-9][0-9]|Exception|NoMethodError" | grep -viE "deprecat"' 2>/dev/null | tail -15)"
if [ -n "$APPERR" ]; then echo "$APPERR" >>"$BODY"; WACKY+=("app log: 500s/exceptions present"); else echo "(none)" >>"$BODY"; fi

# 3) nginx error log -------------------------------------------------------
sec "nginx error log (error-level, last 10)"
NGINX="$(docker exec ridepilot_web_1 sh -c 'tail -80 /var/www/ridepilot/log/nginx.error.log 2>/dev/null' 2>/dev/null | grep -iE '\[error\]|\[crit\]|\[alert\]' | tail -10)"
if [ -n "$NGINX" ]; then echo "$NGINX" >>"$BODY"; WACKY+=("nginx error-level entries present"); else echo "(clean)" >>"$BODY"; fi

# 4) sidekiq health --------------------------------------------------------
sec "sidekiq"
RUBY='
require "sidekiq/api"
now=Time.now.to_f
ss=Sidekiq::ScheduledSet.new
pd=ss.select{|j| j.at.to_f<now}.size
st=Sidekiq::Stats.new
ps=Sidekiq::ProcessSet.new
beat=ps.map{|p| now - p["beat"].to_f}.min
puts "HKPROCS=#{ps.size}"
puts "HKBEATAGE=#{beat ? beat.round : -1}"
puts "HKPASTDUE=#{pd}"
puts "HKSCHED=#{ss.size}"
puts "HKFAILED=#{st.failed}"
puts "HKRETRY=#{st.retry_size}"
puts "HKDEAD=#{st.dead_size}"
puts "HKMAXSCHED=#{RepeatingTrip.maximum(:scheduled_through)}"
puts "HKFUTURE=#{Trip.where("pickup_time > ?", Time.now).count}"
'
SK="$(docker exec ridepilot_app_1 bundle exec rails runner "$RUBY" 2>/dev/null | grep '^HK')"
val() { echo "$SK" | sed -n "s/^$1=//p" | head -1; }
PROCS=$(val HKPROCS); BEATAGE=$(val HKBEATAGE); PASTDUE=$(val HKPASTDUE)
SCHED=$(val HKSCHED); FAILED=$(val HKFAILED); RETRY=$(val HKRETRY); DEAD=$(val HKDEAD)
MAXSCHED=$(val HKMAXSCHED); FUTURE=$(val HKFUTURE)
echo "procs=$PROCS heartbeat_age=${BEATAGE}s scheduled=$SCHED past_due=$PASTDUE failed=$FAILED retry=$RETRY dead=$DEAD" >>"$BODY"
echo "repeating_trip max scheduled_through=$MAXSCHED  future_trips=$FUTURE" >>"$BODY"

if [ -z "$SK" ]; then
  WACKY+=("sidekiq api unreachable (could not read Sidekiq stats)")
else
  [ "${PROCS:-0}" -lt 1 ] 2>/dev/null && WACKY+=("sidekiq: no live process registered")
  { [ "${BEATAGE:--1}" -lt 0 ] || [ "${BEATAGE:-999}" -gt 120 ]; } 2>/dev/null && WACKY+=("sidekiq: heartbeat stale (${BEATAGE}s)")
  [ "${PASTDUE:-0}" -gt 3 ] 2>/dev/null && WACKY+=("sidekiq: $PASTDUE past-due scheduled jobs (poller not draining?)")
  TODAY=$(date +%F)
  if [ -n "${MAXSCHED:-}" ] && [ "${MAXSCHED%% *}" \< "$TODAY" ]; then WACKY+=("recurring trips: scheduled_through ($MAXSCHED) is in the past"); fi
  [ "${FUTURE:-0}" -eq 0 ] 2>/dev/null && WACKY+=("no future trips scheduled")
fi

# scheduler thread deaths SINCE THE LAST POLLER START.
# The scheduler thread dies at boot (Scheduled::Poller#initial_wait), so only a
# death recorded AFTER the most recent "connecting to Redis" boot line means the
# CURRENT process's scheduler is dead. Deaths before that boot belong to
# superseded processes (e.g. a fixed-and-restarted one) and are ignored, so a
# recovery no longer shows as a residual alert. docker -t prepends an RFC3339Nano
# capture timestamp (fixed width -> lexically comparable); awk keeps only death
# lines at/after the boot timestamp. If no boot marker is found in the window
# (very stable process, boot scrolled off), b=="" counts all deaths in-window as
# a conservative fallback -- and a long-dead scheduler is caught anyway by the
# past-due backlog check above.
SKLOG_T="$(docker logs -t --since 336h ridepilot_sidekiq_1 2>&1)"
LASTBOOT="$(printf '%s\n' "$SKLOG_T" | grep 'connecting to Redis' | tail -1 | awk '{print $1}')"
SKDEATH="$(printf '%s\n' "$SKLOG_T" | grep -E '@sidekiq\.scheduler.*terminated with exception' | awk -v b="$LASTBOOT" 'b=="" || $1 >= b' | wc -l)"
echo "scheduler-thread deaths since last start (${LASTBOOT:-no boot marker}): $SKDEATH" >>"$BODY"
[ "${SKDEATH:-0}" -gt 0 ] 2>/dev/null && WACKY+=("sidekiq scheduler thread died $SKDEATH time(s) since last start (connection_pool regression?)")

# 5) scheduler cron (nightly rake) -----------------------------------------
sec "scheduler:run cron"
SCHEDLOG=/home/philz/ridepilot-scheduler.log
if [ -f "$SCHEDLOG" ]; then
  AGE=$(( ( $(date +%s) - $(stat -c %Y "$SCHEDLOG") ) / 3600 ))
  echo "scheduler log last updated ${AGE}h ago" >>"$BODY"
  [ "$AGE" -gt 25 ] && WACKY+=("scheduler cron log not updated in ${AGE}h (nightly run may not have fired)")
  SERR="$(tail -50 "$SCHEDLOG" | grep -iE 'rake aborted|Traceback|StandardError|NoMethodError')"
  if [ -n "$SERR" ]; then echo "$SERR" >>"$BODY"; WACKY+=("scheduler cron log shows errors"); fi
else
  echo "(no scheduler log found)" >>"$BODY"; WACKY+=("scheduler cron log missing at $SCHEDLOG")
fi

# 6) disk ------------------------------------------------------------------
sec "disk"
df -h / | tail -1 >>"$BODY"
USE=$(df --output=pcent / 2>/dev/null | tail -1 | tr -dc '0-9')
[ "${USE:-0}" -gt 85 ] 2>/dev/null && WACKY+=("disk / at ${USE}%")

# verdict + write ----------------------------------------------------------
if [ "${#WACKY[@]}" -gt 0 ]; then
  VERDICT="WACKY — ${#WACKY[@]} issue(s): ${WACKY[*]}"
  echo "[$TS] $VERDICT" >>"$ALERTS"
else
  VERDICT="OK — all clear"
fi

{
  echo "==================== RidePilot health @ $TS ===================="
  echo "VERDICT: $VERDICT"
  cat "$BODY"
  echo
} >>"$LOG"
rm -f "$BODY"

# keep the rolling log bounded
tail -n 4000 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"
