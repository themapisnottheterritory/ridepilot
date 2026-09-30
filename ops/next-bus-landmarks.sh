#!/bin/bash
# Seed Next Bus stop landmarks from the map (Nominatim's database on 10.0.0.18,
# container nominatim-2026-09): named shops, restaurants, schools, churches,
# clinics... within 200 m of every stop in the published city timetable.
# Adds only what's new; staff-added and staff-hidden landmarks are kept as
# they are (StopLandmark.seed_from). Re-run after a map update or when the
# timetable gets new stops. Needs ssh to philz@10.0.0.18 (docker group).
set -euo pipefail
FEED=${NEXT_BUS_GTFS_URL:-https://gtfs.gcrpc.org/gtfs/GCRPC-Fixed.zip}
NOMINATIM_HOST=${NOMINATIM_HOST:-10.0.0.18}
CONTAINER=${NOMINATIM_CONTAINER:-nominatim-2026-09}
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

curl -sfk "$FEED" -o "$work/feed.zip"
unzip -p "$work/feed.zip" stops.txt > "$work/stops.txt"
python3 - "$work/stops.txt" > "$work/q.sql" <<'PY'
import csv, sys
rows = list(csv.DictReader(open(sys.argv[1], encoding="utf-8-sig")))
print("WITH s(id, lat, lon) AS (VALUES " + ", ".join(f"('{r['stop_id']}', {float(r['stop_lat'])}, {float(r['stop_lon'])})" for r in rows) + ")")
print("""SELECT s.id, p.class, p.type, p.name->'name', coalesce(p.name->'brand', ''),
       round(ST_Y(p.centroid)::numeric, 6), round(ST_X(p.centroid)::numeric, 6),
       round(ST_Distance(p.centroid::geography, ST_SetSRID(ST_MakePoint(s.lon, s.lat), 4326)::geography))
FROM s CROSS JOIN LATERAL (
  SELECT * FROM placex p
  WHERE p.geometry && ST_Expand(ST_SetSRID(ST_MakePoint(s.lon, s.lat), 4326), 0.0025)
    AND p.name ? 'name' AND p.rank_search >= 26
    AND p.class IN ('amenity','shop','leisure','tourism','office','healthcare','building','craft','club','historic')
    AND ST_DWithin(p.centroid::geography, ST_SetSRID(ST_MakePoint(s.lon, s.lat), 4326)::geography, 200)
) p;""")
PY
scp -q "$work/q.sql" "$NOMINATIM_HOST:/tmp/next-bus-landmarks.sql"
ssh "$NOMINATIM_HOST" "docker cp /tmp/next-bus-landmarks.sql $CONTAINER:/tmp/q.sql && docker exec -u postgres $CONTAINER psql -d nominatim -tA -F'|' -f /tmp/q.sql; rm -f /tmp/next-bus-landmarks.sql" > "$work/landmarks.txt"
echo "$(wc -l < "$work/landmarks.txt") candidates from the map"
docker cp "$work/landmarks.txt" ridepilot_app_1:/tmp/next-bus-landmarks.txt
docker exec ridepilot_app_1 bin/rails runner '
rows = File.readlines("/tmp/next-bus-landmarks.txt").map { |l| l.chomp.split("|", -1) }.select { |r| r.size >= 8 }
puts "added #{StopLandmark.seed_from(rows)} landmarks; #{StopLandmark.shown.select(:stop_id).distinct.count} stops now have one"' 2>&1 | tail -1
docker exec ridepilot_app_1 rm -f /tmp/next-bus-landmarks.txt
