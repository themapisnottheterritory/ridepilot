# Victoria Transit trip planner (plan.gcrpc.org)

OpenTripPlanner 2 with a GCRPC-branded, phone-first web client. Built 2026-09-11 on 10.0.0.32 and
**live at https://plan.gcrpc.org the same day** (Let's Encrypt via certbot, auto-renews; http redirects).
The public A record points at 64.123.96.229, which pfSense forwards to 10.0.0.32; the LAN hairpins the
public address, so no internal DNS override is needed.
Repo copy of everything here: `ridepilot/ops/trip-planner/`.

    data/   gcrpc-fixed.gtfs.zip         the FY2027 feed (from ~/gtfs_fy2027/GCRPC-Fixed-FY2027.zip)
            golden-crescent.osm.pbf      OpenStreetMap, eight-county clip of the Geofabrik Texas extract
            build-config.json            OSM + GTFS sources, time zone
            router-config.json           walk speed, transfer slack
            graph.obj                    the built graph (regenerate when the feed or the map changes)
    web/    index.html, gcrpc-seal.png   the client; nginx serves it as static files
            places.json                  common destinations the office maintains (PLACES.md)
            stops.json                   every bus stop with its routes, generated from the feed
    otp-planner.service                  systemd unit: runs OTP in Docker on 127.0.0.1:8081
    nginx-plan.gcrpc.org.conf            the site; nginx-plan-http.conf goes in conf.d (rate limit, tile cache)

## Rebuild the graph (after a new GTFS feed or map)

    cp ~/gtfs_fy2027/GCRPC-Fixed-FY2027.zip data/gcrpc-fixed.gtfs.zip
    docker run --rm -v ~/otp/data:/var/opentripplanner -e JAVA_OPTS=-Xmx6G \
      opentripplanner/opentripplanner:2.6.0 --build --save
    sudo systemctl restart otp-planner

Takes a minute or two for this area. Also regenerate `web/stops.json` from the new feed
(`ops/trip-planner/make_stops.py` in the RidePilot repo). `--build --save` writes `data/graph.obj`; the service starts with
`--load --serve`.

## Refresh the map (yearly is plenty)

    curl -L -o data/texas-latest.osm.pbf https://download.geofabrik.de/north-america/us/texas-latest.osm.pbf
    docker run --rm -v ~/otp/data:/data stefda/osmium-tool osmium extract \
      -b -97.6,28.2,-95.9,29.7 -o /data/golden-crescent.osm.pbf --overwrite /data/texas-latest.osm.pbf
    rm data/texas-latest.osm.pbf     # 1.4 GB, not needed after the clip

## How the client talks to things

- `/otp/gtfs/v1` -> OTP's GraphQL (proxied by nginx, same origin)
- `/geocode`, `/reverse` -> Nominatim on 10.0.0.18:8088, boxed to the service area and rate limited
- `/tiles/` -> the OSM tile server on 10.0.0.16, cached by nginx

Nothing on the LAN is reachable from the internet except through those three proxied paths.

## Branding

`web/index.html`, the `:root` block at the top: navy #12264F, gold #CC9900, Copperplate Gothic headings
(falls back to Georgia where not installed), Open Sans body. Phone number and the route-maps link are in
the HTML.

## Realtime (not yet)

`~/gtfs_realtime` on this box produces GTFS-RT. Add to router-config.json:

    "updaters": [ { "type": "stop-time-updater", "frequency": "30s", "feedId": "gcrpc", "url": "http://127.0.0.1:<port>/tripupdates.pb" } ]

and restart; the client already shows `realTime` legs when present.
