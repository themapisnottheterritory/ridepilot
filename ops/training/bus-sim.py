#!/usr/bin/env python3
"""
Simulated bus positions for the RidePilot TRAINING box.

Serves an OpenTransit-style feed that RidePilot's AvlPollerWorker already
understands (provider avl_source='opentransit_api', opentransit_url=this):

    GET /api/vehicles  -> [{"vehicle_id":"1705","lat":..,"lon":..,"speed":..,"heading":..,"timestamp":..}, ...]

Every run on today's board gets a moving bus:
  * fixed-route runs follow the route's road-matched shape from the
    authoring tool, stop to stop on the published timetable, one direction
    then the other, with a short layover;
  * demand-response runs drive the OSRM road path through their manifest
    points (depot -> pickups/dropoffs -> depot) with a dwell at each.
Positions loop continuously so buses are always moving during a demo,
whatever the clock says. Stdlib only; runs on the training host itself.

    python3 bus-sim.py            (port 8090)
    curl http://10.0.0.15:8090/   status page
"""
import json, math, os, random, subprocess, threading, time, urllib.request, urllib.parse
from bisect import bisect_right
from datetime import datetime, timezone, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT      = int(os.environ.get("PORT", 8090))
TOOL_URL  = os.environ.get("TOOL_URL", "http://10.0.0.16:8080").rstrip("/")
OSRM_URL  = os.environ.get("OSRM_URL", "http://10.0.0.15/osrm").rstrip("/")
PSQL      = os.environ.get("PSQL", "docker exec ridepilot_db_1 psql -U postgres -d ridepilot -tA -F|").split()
REFRESH_S = int(os.environ.get("REFRESH_S", 60))      # re-read today's board
DR_SPEED  = float(os.environ.get("DR_SPEED_MPS", 9))  # ~20 mph between paratransit stops
DWELL_S   = int(os.environ.get("DWELL_S", 90))        # at paratransit stops
LAYOVER_S = int(os.environ.get("LAYOVER_S", 120))     # at the end of a fixed-route direction
TZ        = timezone(timedelta(hours=-5))             # Central Daylight Time
DEPOT     = (28.812645, -96.989695)   # the bus yard at 1908 N Laurent (centre of the fenced lot)

def haversine(lat1, lon1, lat2, lon2):
    R = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = math.radians(lat2 - lat1), math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * R * math.asin(math.sqrt(a))

def bearing(lat1, lon1, lat2, lon2):
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dl = math.radians(lon2 - lon1)
    x = math.sin(dl) * math.cos(p2)
    y = math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl)
    return (math.degrees(math.atan2(x, y)) + 360) % 360

def hms(s):
    h, m, *rest = s.split(":")
    return int(h) * 3600 + int(m) * 60 + (int(float(rest[0])) if rest else 0)

class Path:
    """A polyline (lat, lon) with cumulative metres and a time profile:
    a list of (t_seconds_into_cycle, distance_m) knots, piecewise linear."""
    def __init__(self, points, knots):
        self.points = points
        self.cum = [0.0]
        for (a, b) in zip(points, points[1:]):
            self.cum.append(self.cum[-1] + haversine(a[0], a[1], b[0], b[1]))
        self.knots = knots
        self.cycle = knots[-1][0] if knots else 1

    def at(self, t):
        t = t % self.cycle
        i = bisect_right([k[0] for k in self.knots], t) - 1
        i = max(0, min(i, len(self.knots) - 2))
        (t0, d0), (t1, d1) = self.knots[i], self.knots[i + 1]
        f = 0 if t1 == t0 else (t - t0) / (t1 - t0)
        d = d0 + (d1 - d0) * f
        speed = 0.0 if t1 == t0 else abs(d1 - d0) / (t1 - t0)
        return self.point_at(d), speed

    def point_at(self, d):
        d = max(0.0, min(d, self.cum[-1]))
        j = bisect_right(self.cum, d) - 1
        j = max(0, min(j, len(self.points) - 2))
        seg = self.cum[j + 1] - self.cum[j]
        f = 0 if seg == 0 else (d - self.cum[j]) / seg
        a, b = self.points[j], self.points[j + 1]
        return (a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, bearing(a[0], a[1], b[0], b[1]))

# ---- builders ---------------------------------------------------------------

_tool_cache = {}
def tool_route(rid):
    if rid not in _tool_cache:
        with urllib.request.urlopen(f"{TOOL_URL}/api/routes/{rid}", timeout=10) as r:
            _tool_cache[rid] = json.load(r)
    return _tool_cache[rid]

def fixed_route_path(external_ids):
    """One cycle = each direction's first timetabled trip in turn, layover between."""
    points, knots, t, dist_base = [], [], 0.0, 0.0
    for rid in external_ids:
        d = tool_route(rid)
        shape = [(lat, lon) for lon, lat in d["shape"]["coordinates"]]
        cum = d.get("shape_cumulative_m") or Path(shape, [(0, 0), (1, 0)]).cum
        stops = d["stops"]
        runs = d.get("runs") or []
        run_id = runs[0]["run_id"] if runs else None
        timed = [(s["distance_along_shape_m"], hms(s["scheduled_times_by_run"][run_id]))
                 for s in stops if run_id and s.get("scheduled_times_by_run", {}).get(run_id)]
        if len(timed) < 2:  # no timetable: assume 20 mph end to end
            timed = [(0.0, 0), (cum[-1], cum[-1] / 9.0)]
        t0 = timed[0][1]
        # direction segment: append shape, shift its cumulative distances after the previous direction
        start_idx = len(points)
        points.extend(shape)
        if start_idx and points[start_idx - 1] != shape[0]:
            pass  # the jump between directions is instant (both end at the depot area)
        for dist, sec in timed:
            knots.append((t + (sec - t0), dist_base + dist))
        t += timed[-1][1] - t0
        knots.append((t + LAYOVER_S, dist_base + timed[-1][0]))
        t += LAYOVER_S
        dist_base += cum[-1]
    return Path(points, knots)

def osrm_path(coords):
    """coords = [(lat, lon), ...] visited in order; OSRM road geometry between them."""
    q = ";".join(f"{lon},{lat}" for lat, lon in coords)
    url = f"{OSRM_URL}/route/v1/driving/{q}?overview=full&geometries=geojson&steps=false"
    with urllib.request.urlopen(url, timeout=15) as r:
        j = json.load(r)
    route = j["routes"][0]
    pts = [(lat, lon) for lon, lat in route["geometry"]["coordinates"]]
    p = Path(pts, [(0, 0), (1, 0)])
    # knots: drive each leg at DR_SPEED, dwell at each intermediate point
    knots, t, d = [(0.0, 0.0)], 0.0, 0.0
    for leg in route["legs"]:
        d += leg["distance"]; t += leg["distance"] / DR_SPEED
        knots.append((t, d))
        t += DWELL_S; knots.append((t, d))
    p.knots, p.cycle = knots, knots[-1][0]
    return p

# ---- board -------------------------------------------------------------------

buses = {}     # unit -> {"path": Path, "offset": s, "run_id": .., "kind": ..}
lock = threading.Lock()

def psql(sql):
    out = subprocess.run(PSQL + ["-c", sql], capture_output=True, text=True, timeout=30)
    return [line.split("|") for line in out.stdout.strip().splitlines() if line.strip()]

def refresh():
    rows = psql("select r.id, v.name, r.service_mode, coalesce(array_to_string(f.external_route_ids, ','), '') "
                "from runs r join vehicles v on v.id=r.vehicle_id left join fixed_routes f on f.id=r.fixed_route_id "
                "where r.date=current_date and r.deleted_at is null and r.end_odometer is null and (r.cancelled is null or r.cancelled=false)")
    new = {}
    for run_id, unit, mode, ext in rows:
        try:
            if unit in buses and buses[unit]["run_id"] == run_id:
                new[unit] = buses[unit]; continue
            if mode == "fixed_route" and ext:
                path = fixed_route_path(ext.split(","))
            else:
                pts = psql(f"select round(ST_Y(a.the_geom::geometry)::numeric,6), round(ST_X(a.the_geom::geometry)::numeric,6) "
                           f"from itineraries i join addresses a on a.id=i.address_id where i.run_id={int(run_id)} and a.the_geom is not null "
                           f"order by i.time, i.leg_flag")
                coords = [(float(a), float(b)) for a, b in pts]
                if len(coords) < 2:
                    coords = [DEPOT, (DEPOT[0] + 0.01, DEPOT[1] - 0.01), DEPOT]
                if coords[0] != coords[-1]:
                    coords.append(coords[0])
                path = osrm_path(coords)
            new[unit] = {"path": path, "offset": (int(unit) * 137) % max(1, int(path.cycle)), "run_id": run_id, "kind": mode}
            print(f"[{datetime.now():%H:%M:%S}] unit {unit}: run {run_id} {mode} cycle {int(path.cycle)}s over {int(path.cum[-1])} m", flush=True)
        except Exception as e:
            print(f"[{datetime.now():%H:%M:%S}] unit {unit}: skipped ({e})", flush=True)
    with lock:
        buses.clear(); buses.update(new)

def refresher():
    while True:
        try: refresh()
        except Exception as e: print(f"refresh failed: {e}", flush=True)
        time.sleep(REFRESH_S)

def positions():
    now = time.time()
    out = []
    with lock:
        items = list(buses.items())
    for unit, b in items:
        (lat, lon, hdg), speed = b["path"].at(now + b["offset"])
        # a couple of metres of GPS wobble
        lat += random.uniform(-2e-5, 2e-5); lon += random.uniform(-2e-5, 2e-5)
        out.append({"vehicle_id": unit, "lat": round(lat, 6), "lon": round(lon, 6),
                    "speed": round(speed, 1), "heading": round(hdg), "timestamp": datetime.now(TZ).isoformat(timespec="seconds"),
                    "run_id": b["run_id"], "kind": b["kind"]})
    return out

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _json(self, obj, code=200):
        body = json.dumps(obj).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
    def do_GET(self):
        p = urllib.parse.urlparse(self.path).path
        if p == "/api/vehicles":
            return self._json(positions())
        if p.startswith("/api/vehicles/"):
            unit = p.rsplit("/", 1)[1]
            v = [x for x in positions() if x["vehicle_id"] == unit]
            return self._json(v[0] if v else {}, 200 if v else 404)
        if p == "/":
            rows = "".join(f"<tr><td>{v['vehicle_id']}</td><td>{v['kind']}</td><td>{v['run_id']}</td><td>{v['lat']}, {v['lon']}</td><td>{v['speed']} m/s</td></tr>" for v in positions())
            body = f"<html><body style='font-family:sans-serif'><h3>bus-sim: {len(buses)} simulated buses</h3><table border=1 cellpadding=4><tr><th>unit</th><th>kind</th><th>run</th><th>position</th><th>speed</th></tr>{rows}</table><p>Feed: <a href='/api/vehicles'>/api/vehicles</a></p></body></html>".encode()
            self.send_response(200); self.send_header("Content-Type", "text/html"); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body); return
        self._json({"error": "not found"}, 404)

if __name__ == "__main__":
    threading.Thread(target=refresher, daemon=True).start()
    print(f"bus-sim listening on :{PORT} (tool {TOOL_URL}, osrm {OSRM_URL})", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), H).serve_forever()
