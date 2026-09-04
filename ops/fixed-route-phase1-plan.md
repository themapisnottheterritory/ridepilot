# Fixed Route in RidePilot — Phase 1 plan

Written 2026-09-03. Replaces the fixed-route part of the Shah driver app at the September 2026
cutover, using the RidePilot driver app the paratransit drivers already have.

## 1. What Phase 1 delivers

- A fixed-route driver logs in to the RidePilot driver app, confirms the unit they are actually
  driving, does the DVIR pre-trip, starts the run, logs walk-ons stop by stop through the day,
  does the post-trip, and ends the run.
- Every walk-on is a row in RidePilot. Dispatch sees the day's boardings on the run page.
- The NTD report can be produced for the fixed-route mode with the same button as demand response.
- No navigation, no schedule adherence, no fares reconciliation. Those are Phase 2.

What it replaces from Shah, feature for feature: one all-day "trip" per route (becomes a run),
"Add Walkon" (becomes the Walk-on sheet), the walk-on's stop / category / count / fare / dropped-off
fields, and the Post Inspection tab (already DVIR).

## 2. How fixed route maps onto RidePilot

| Shah | RidePilot Phase 1 |
|---|---|
| Driver login "NORTH,RED" (one login per route/direction) | A real driver, a real vehicle, a run named after the route |
| All-day trip 07:00–18:00 depot to depot | A **repeating run** per route, generated nightly by `scheduler:run` |
| Add Walkon | **Walk-on sheet** on the run screen → `fixed_route_boardings` rows |
| Select Bus Stop | Stop list synced from the fixed-route authoring tool into RidePilot |
| Category / Count / Fare / Fare Type | Two new lookup tables: rider categories and fare types |
| No of Persons Dropped Off | `alighted_count` on the same boarding record |
| Odometer per walk-on | Dropped. Run start/end odometer already captured, GPS gives position |
| Unit number written on the paper run log | Driver **confirms the unit** at run start; the run, DVIR, odometer and AVL all follow the real bus |
| Post Inspection | DVIR post-trip, already built |

The one new concept is a **service mode** on runs: `demand_response` (default, everything today)
or `fixed_route`. Everything downstream branches on it, and demand-response behaviour is untouched.

## 3. Why the NTD report needs its own fixed-route path

`NtdReport` builds miles and hours from `run_distances`, which `RunStatsCalculator` computes by
walking a run's trip itineraries. Unlinked passenger trips are `customer_space_count + guest_count +
attendant_count` summed over trips. A fixed-route run has no trips, so today it would contribute
zero miles, zero hours, zero riders, and would still count toward "vehicles operated in maximum
service". Phase 1 gives the fixed mode odometer-based miles, clock-based hours, and boarding-based
riders, and filters fixed runs out of the demand-response figures.

| NTD row | Demand response (unchanged) | Fixed route (new) |
|---|---|---|
| Time service begins / ends | avg earliest / latest run | same, filtered by mode |
| Vehicles operated in max service | max distinct vehicles on a day | same, filtered by mode |
| Vehicles available for max service | `Vehicle.update_monthly_tracking` | same figure (decision D6) |
| Unlinked passenger trips | sum of trip sizes | sum of `boarded_count` |
| Days operated | distinct run dates | same, filtered by mode |
| Total actual miles | `run_distances.ntd_total_miles` | `end_odometer − start_odometer` |
| Vehicle revenue miles | `run_distances.ntd_total_revenue_miles` | odometer diff minus deadhead (Phase 1: deadhead 0, decision D3) |
| Passenger miles | itinerary capacity × distance | left blank (decision D4) |
| Total vehicle hours | proportional to NTD mileage | `actual_end_time − actual_start_time` |
| Vehicle revenue hours | total × revenue ratio | total hours − unpaid break |

The report form gets a **Mode** select (Demand Response / Fixed Route). One workbook per mode,
which is how NTD wants it filed anyway.

## 4. Data model

New columns:

- `runs.service_mode` string, default `demand_response`, indexed. `runs.fixed_route_id` integer, nullable.
- `repeating_runs.service_mode` and `repeating_runs.fixed_route_id`, same shape. `RepeatingRun.generate!` copies both onto each child run.
- `runs.vehicle_confirmed_at` datetime. Set when the driver confirms or changes the unit at run start. `Run` already has `has_paper_trail`, so a driver-side vehicle change is recorded with the old and new unit.

New tables:

- `fixed_routes` — provider_id, name ("Red"), color (hex from the map), kind (`city` / `commuter`), external_route_ids (the authoring-tool ids, e.g. `fy2027-red-east`, `fy2027-red-west`), active, timestamps.
- `fixed_route_stops` — fixed_route_id, direction ("East"), sequence, name, latitude, longitude, external_stop_id, timepoint.
- `rider_categories` — lookup table (name, active). Registered in `lookup_tables` so it is editable under Lookup Tables like Trip Purpose.
- `fare_types` — lookup table (name, active). Same.
- `fixed_route_boardings` — provider_id, run_id, fixed_route_id, fixed_route_stop_id (nullable), stop_name (snapshot), direction, driver_id, vehicle_id, rider_category_id, fare_type_id (nullable), boarded_count, alighted_count, fare_amount decimal(8,2) nullable, recorded_at, latitude, longitude, client_uuid, deleted_at, timestamps. Unique index on (client_uuid, rider_category_id) so offline retries never double-count. Index on run_id and recorded_at.

One walk-on submission from the tablet becomes one boarding row per rider category that has a
non-zero count, all sharing the submission's `client_uuid`. `alighted_count` is stored on the
first row only.

## 5. Work packages, in build order

Each is one PR against master, deployable on its own.

### WP1 — Schema, models, lookups (Rails)
**Status: BUILT 2026-09-04** — branch `fixed-route-wp1`, PR #34 (with WP2). Migration applied on production; app restarted.

Migrations above. `Run#fixed_route?`, `Run.fixed_route` / `Run.demand_response` scopes,
`belongs_to :fixed_route, optional: true`. `FixedRouteBoarding` with `has_paper_trail` (compliance
records, same posture as DVIR). Lookup-table registration for rider categories and fare types with
a seed of proposed defaults (decision D1). Rails 7 gotcha from the DVIR work applies: every new
`belongs_to` on a nullable key needs `optional: true`.

### WP2 — Route sync from the authoring tool (rake task)
**Status: BUILT 2026-09-04** — `rake fixed_routes:sync[1]` run on production: 13 routes (6 city, 7 commuter), 240 stops. `rake fixed_routes:seed_lookups` seeded the D1 defaults.

`rake fixed_routes:sync` reads `GET /api/routes` and `/api/routes/:id` from the authoring tool on
:8080 and upserts `fixed_routes` + `fixed_route_stops`. It only takes the FY2027 and Inteplast
routes; DRAFT and Retired entries are skipped. Idempotent, dry-run flag, same shape as
`ProviderCommonAddress.load_addresses`. The authoring tool stays the place routes are drawn;
RidePilot is the place they are operated. Route colours come from the six map PDFs (Blue, Gold,
Green, Pink, Purple, Red).

### WP3 — Unit confirmation at run start (all modes, Rails + tablet)
**Status: BUILT 2026-09-03** — ridepilot branch `unit-confirmation` (commit `92ff6eaf`), rideavl-v2 branch `unit-confirmation` (commit `2ca07fb`, app 1.0.6). Verified end to end in a headless browser against the live server. Deploy note: the migration adds a column, so puma must be restarted after migrating or saves silently drop the timestamp.

Applies to demand response too, and ships on its own ahead of the rest. Today the run payload
carries the assigned vehicle and the DVIR pre-trip silently inspects it; nothing asks the driver
whether that is the bus they are sitting in.

- Tablet: the pre-trip screen opens with a **Confirm unit** step. The assigned unit number is shown large ("Unit 1734"), with two buttons: **This is my unit** and **Different unit**. Different unit opens a searchable list of the provider's active vehicles by unit number. Nothing else on the screen is usable until the unit is confirmed.
- API: `PATCH runs/:id/vehicle` with the chosen vehicle id. Runs the existing overlapping-run vehicle availability check; on success sets `vehicle_confirmed_at`, saves through paper trail, and posts a `RoutineMessage` to dispatch through the existing driver chat: "Started run Red on unit 1737 instead of 1734". Confirming the assigned unit only sets `vehicle_confirmed_at`.
- The DVIR template and prior-defect lookup reload for the confirmed vehicle before the checklist renders, so the inspection, odometer, maintenance events and NTD miles all land on the real bus. AVL matching keys on `vehicles.name` (the Pepwave unit number), so the run's GPS trail follows the real bus as well.
- Dispatcher run page shows "Unit confirmed by driver at 06:58" or "Changed by driver from 1734 to 1737 at 06:58".

### WP4 — Dispatcher web UI (Rails)
**Status: BUILT 2026-09-04** — branch `fixed-route-wp4` (stacked on WP1). Found and fixed on the way: paper trail never recorded the author of web edits (missing whodunnit before_action).

- Run and repeating-run forms: a Service Mode radio; when Fixed Route, a Fixed Route select replaces the garage address fields and the trip list.
- Run show page: for fixed runs, a **Boardings panel** in place of the trip list. Rows by time and stop, totals by rider category, day total. Editors can correct or void a row (paper-trailed).
- Runs index: a mode filter and a small colour swatch on fixed runs.
- Run completion: unchanged. Dispatch marks the run complete the way they do now; the NTD report only counts complete runs.

### WP5 — Driver API (Rails, `api/v1/driver`)
**Status: BUILT 2026-09-04** — branch `fixed-route-wp5` (stacked on WP4). Undo is by submission `client_uuid` rather than row id, so one tap undoes one tap.

- Run payload gains `service_mode` and `fixed_route {id, name, color}`.
- `GET runs/:id/fixed_route` returns stops grouped by direction, rider categories, fare types. Cached on the tablet, refreshed on run open.
- `POST runs/:id/boardings` takes one walk-on submission (client_uuid, stop, direction, entries by category, alighted_count, recorded_at, lat/lng). Idempotent on client_uuid.
- `DELETE boardings/:id` for undo, limited to the driver's own run, same day.
- `GET runs/:id/boardings` returns today's rows and totals so the screen rehydrates after an app restart.

### WP6 — Driver tablet (rideavl-v2, Ionic/Angular)
**Status: BUILT 2026-09-04** — rideavl-v2 branch `fixed-route-wp6` (stacked on training-flavour), app 1.0.7. Verified headless against the live server incl. offline queue + sync.

- Runs list: fixed runs show the route colour and name. Tapping an un-started run goes to unit confirmation, then the DVIR pre-trip exactly as today; pre-trip submit starts the run.
- New **Fixed Route page** replaces the manifest for fixed runs. Top: boarded / alighted today and totals by category. Middle: one large **Walk-on** button. Bottom: the last few walk-ons with an undo. Toolbar keeps chat, post-trip inspection, and End Run.
- **Walk-on sheet** mirrors Shah's dialog so drivers recognise it: Stop (nearest stop pre-selected from GPS, list grouped by direction), a row per rider category with − / count / +, fare type, Dropped off count, Save. Saves in one tap; no confirmation screens.
- **Stationary gate**: the Walk-on button is only enabled while GPS speed is under walking pace. Moving shows "Stop the bus to log riders". This is the fixed-route app's no-touch-in-motion rule carried across.
- Offline: submissions go through the existing `OfflineQueueService` / sync path built for DVIR, keyed by client_uuid. Totals update locally at once.
- Build and ship as the next APK version on the existing signing key.

### WP7 — NTD and ridership reporting (Rails)
**Status: BUILT 2026-09-04** — branch `fixed-route-wp7` (stacked on WP5). Demand-response NTD workbook proven cell-for-cell identical to the pre-change baseline; fixed workbook verified against a hand-computed fixture.

- `NtdReport.new(provider, year, month, mode:)`. Demand-response path unchanged except runs are filtered to mode. Fixed path implements the right-hand column of the table in §3.
- Report form: Mode select. Filename becomes `NTD_<year>_<month>_<mode>.xlsx`.
- New V2 custom report **Fixed Route Ridership**: date range, route, group by day / stop / rider category / fare type; HTML, CSV, PDF through the shared export path fixed in August. Seeded through `db/tasks/seed_v2_custom_reports.rb` like the others.

### WP8 — Seed, pilot, go live
**Status: TOOLING BUILT 2026-09-04** — branch `fixed-route-wp8`. Sync + lookups done on production; `fixed_routes:seed_repeating_runs` dry-run reviewed but NOT run on production (that is D2 with Erika); training box (.15) has fixed runs for trainee05/06, a ridership day, and the repeating-run blocks for dispatcher practice; driver guide updated. Pilot week not started.

1. Run `fixed_routes:sync`; confirm 6 city routes + 7 commuter routes and their stop counts against the authoring tool.
2. Seed rider categories and fare types from the confirmed list (D1).
3. Create one repeating run per route block with Erika: driver, vehicle, days, span (D2). Nightly `scheduler:run` generates the daily runs from then on; check the first morning's runs exist.
4. Pilot one route for a week on unit 1770 with a driver who did the August training runs. Compare a day's boardings against the paper tally.
5. Run the September NTD report in both modes and hand the fixed-route workbook to Kristie for a sanity read.
6. Add a fixed-route section to `~/ridepilot-ops/driver-app-training.md`.

## 6. Decisions needed from GCRPC

| # | Question | Proposed default |
|---|---|---|
| D1 | Rider categories and fare types | Take the live lists from Shah's Walk-on dialog. Fallback seed: Adult, Senior, Disabled, Student, Child, Transfer; Cash, Pass, Free / Transfer, No fare. |
| D2 | Route blocks: does one driver run one route (both directions) all day, and what are the spans per route? Shah has Red North 07:00–18:00. | One repeating run per route per service day, both directions, 07:00–18:00 city, commuter per GTFS (AM 05:55–06:45, PM 17:55–18:45). |
| D3 | Does revenue service start at the depot? Shah labels the depot stop START REVENUE. | Yes. Deadhead 0, revenue miles = odometer difference. |
| D4 | Fixed-route passenger miles for NTD | Blank in Phase 1. Needs an average-trip-length sampling method; plan it with Kristie. |
| D5 | Should commuter (Inteplast) routes go live in Phase 1 too? | Yes, same mechanism. Check the 05:55 departures against driver availability rules on runs. |
| D6 | Vehicles available for maximum service, per mode | Report the fleet figure for both modes until vehicles are tagged by service. |
| D7 | Who may edit or void a boarding on the web | Editor role and above, paper-trailed. |
| D8 | Driver picks a unit that is already on another run today | Allow it if that other run has not started, and tell dispatch. Block it if the other run is in progress, with "Unit 1737 is on Erika's run. Call dispatch." |

## 7. Out of scope (Phase 2)

- Porting the navigation and schedule-adherence logic from the fixed-route app (`positioning.js`, forward-window snap, early-departure rules).
- Automatic stop arrival and departure timestamps.
- Fare reconciliation and cash-drawer counts.
- Carrying pre-trip defects forward into post-trip (DVIR Phase 2, separate track).

## 8. Verification

- [ ] Migrations run clean on a copy of the live DB; `rake fixed_routes:sync --dry-run` lists 13 routes.
- [ ] Repeating fixed run generates a child run overnight with mode and route copied.
- [ ] Tablet: confirm the assigned unit → pre-trip DVIR → run starts → three walk-ons at three stops → undo one → post-trip → End Run. Rows and totals match on the run page.
- [ ] Tablet: choose a different unit at run start → run, inspection report and maintenance event all carry the new unit, dispatch chat gets the message, run page shows the change.
- [ ] Same flow with the tunnel down: walk-ons queue, drain on reconnect, no duplicates (unique client_uuid).
- [ ] Walk-on button disabled at driving speed, enabled when stopped.
- [ ] NTD demand-response workbook for August is byte-identical to today's output (regression).
- [ ] NTD fixed-route workbook for the pilot week shows the pilot's riders, miles, and hours.
- [ ] Fixed Route Ridership report exports HTML, CSV, PDF.

## 9. Rough effort

| Package | Days |
|---|---|
| WP1 schema and models | 1 |
| WP2 route sync | 0.5 |
| WP3 unit confirmation | 1 |
| WP4 dispatcher UI | 1 |
| WP5 driver API | 1 |
| WP6 tablet | 2.5 |
| WP7 NTD and report | 1.5 |
| WP8 seed, pilot, training | 1 + a pilot week |

About nine build days, then a pilot week. WP3 can go to the paratransit drivers as soon as it is done, before the rest. The build can start as soon as D1 and D2 are answered;
D3 to D7 can land during the pilot.
