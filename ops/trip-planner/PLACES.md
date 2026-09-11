# Common destinations (places.json)

`web/places.json` is the list of named places the trip planner suggests before it asks the
geocoder: type "HEB", "hospital", "mall", "courthouse" and the right spot appears with a pin. The
office can edit it; no rebuild is needed, the page picks it up on the next load.

Each entry:

    { "name": "Citizens Medical Center", "aliases": ["Citizens", "hospital"], "lat": 28.8128, "lon": -96.97776,
      "address": "2701 Hospital Drive" }

- `name` is what the rider sees and what goes in the box when picked.
- `aliases` are other things people type. Every word typed must appear in the name or an alias.
- `lat`/`lon`: the front door or the closest curb, not the middle of a parking lot. Get them from
  Google Maps (right-click, copy coordinates) or the geocoder.
- `"verify": true` marks entries placed by street address without a check on the ground. Five of the
  first 25 are marked; remove the flag once someone confirms the pin.

`web/stops.json` is every bus stop from the GTFS feed with the routes that serve it. Regenerate it
when the feed changes (see README, rebuild section); do not edit by hand.
