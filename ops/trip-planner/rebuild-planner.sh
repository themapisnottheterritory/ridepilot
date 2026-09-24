#!/usr/bin/env bash
# Rebuild the trip planner's graph from the city GTFS zip and restart OTP.
# Lives at /home/philz/otp/rebuild-planner.sh on 10.0.0.32; called by
# gcrpc-fixedroute/ops/publish-gtfs.sh after every feed publish, or by hand:
#
#     ~/otp/rebuild-planner.sh [path/to/GCRPC-Fixed.zip]     # default ~/gtfs_fy2027/GCRPC-Fixed-FY2027.zip
#
# Steps: copy the zip into ~/otp/data, build the graph in the OTP container
# (a minute or two), restart otp-planner (needs the one-line sudoers rule in
# otp-planner.sudoers: restart only, no password), wait until it answers,
# regenerate web/stops.json for the client. Keeps the previous graph as
# graph.obj.prev so a bad feed is one `mv` from undone.
set -euo pipefail
ZIP=${1:-/home/philz/gtfs_fy2027/GCRPC-Fixed-FY2027.zip}
OTP=/home/philz/otp
[ -s "$ZIP" ] || { echo "no such feed zip: $ZIP" >&2; exit 1; }
python3 -c "import zipfile,sys; z=zipfile.ZipFile(sys.argv[1]); assert 'stop_times.txt' in z.namelist()" "$ZIP" || { echo "$ZIP is not a GTFS zip" >&2; exit 1; }

echo "== feed -> $OTP/data/gcrpc-fixed.gtfs.zip"
cp -f "$ZIP" "$OTP/data/gcrpc-fixed.gtfs.zip"
[ -f "$OTP/data/graph.obj" ] && cp -f "$OTP/data/graph.obj" "$OTP/data/graph.obj.prev"

echo "== building the graph"
docker run --rm -v "$OTP/data:/var/opentripplanner" -e JAVA_OPTS=-Xmx6G \
  opentripplanner/opentripplanner:2.6.0 --build --save 2>&1 | grep -E "ERROR|Exception|Graph written|Transit feed|trips" | tail -6

echo "== restarting otp-planner"
sudo -n /usr/bin/systemctl restart otp-planner
# OTP 2 answers the GraphQL endpoint (what the client uses); the old REST
# index paths are 404, so that is the readiness probe.
up() { curl -sf --max-time 3 -o /dev/null -X POST -H 'Content-Type: application/json' -d '{"query":"{ agencies { name } }"}' http://127.0.0.1:8081/otp/routers/default/index/graphql; }
for _ in $(seq 1 60); do up 2>/dev/null && break; sleep 3; done
up || { echo "OTP did not come back; previous graph is $OTP/data/graph.obj.prev" >&2; exit 2; }

echo "== web/stops.json"
python3 "$OTP/make_stops.py" "$OTP/data/gcrpc-fixed.gtfs.zip" > "$OTP/web/stops.json.new" && mv -f "$OTP/web/stops.json.new" "$OTP/web/stops.json"
echo "planner rebuilt and serving; $(python3 -c "import json,sys; print(len(json.load(open(sys.argv[1]))))" "$OTP/web/stops.json") stops in web/stops.json"
