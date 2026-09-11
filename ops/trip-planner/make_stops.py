#!/usr/bin/env python3
"""Regenerate web/stops.json from a GTFS zip: python3 make_stops.py gcrpc-fixed.gtfs.zip > stops.json"""
import csv, io, json, sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
rd = lambda n: list(csv.DictReader(io.TextIOWrapper(z.open(n), encoding="utf-8-sig")))
routes = {r["route_id"]: ((r.get("route_short_name") or "") + " " + (r.get("route_long_name") or "")).strip() for r in rd("routes.txt")}
trips = {t["trip_id"]: t["route_id"] for t in rd("trips.txt")}
by = {}
for x in rd("stop_times.txt"):
    by.setdefault(x["stop_id"], set()).add(routes[trips[x["trip_id"]]])
out = [{"name": s["stop_name"], "lat": round(float(s["stop_lat"]), 5), "lon": round(float(s["stop_lon"]), 5), "routes": sorted(by.get(s["stop_id"], []))} for s in rd("stops.txt")]
json.dump(out, sys.stdout, separators=(",", ":"))
