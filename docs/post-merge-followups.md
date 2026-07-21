# Post-merge follow-ups

Findings from the pre-merge reviews of the feature branches consolidated into
`victoria-transit-rails7` on 2026-07-14. None were merge-blockers for the
integration branch (the one true blocker — plaintext DB creds — was fixed before
merge). The items below must be addressed **before the respective features are
enabled in production.** (GitHub Issues are disabled on this repo, so this file
is the tracker.)

## 🔴 Security — must fix before production

### busavl MySQL password rotation (exposed in public repo)
The busavl MySQL fallback creds (`dbmojo`/`igotmojo`) were committed to this
**public** repo in `e4f8a2f8` and appeared in `cad_controller.rb` and the AVL
poller. Working-tree fixes are done (moved to
`ENV['BUSAVL_DB_USERNAME']`/`ENV['BUSAVL_DB_PASSWORD']`: poller via #5,
`cad_controller.rb` via `dae9ee0d`), **but the values remain in git history.**
- [ ] Rotate the busavl MySQL password (neutralizes the exposed value without a
      history rewrite — preferred over BFG/filter-repo force-push on a public repo).
- [ ] Set `BUSAVL_DB_USERNAME` / `BUSAVL_DB_PASSWORD` in the deployment environment.

### SMS / rider portal (#7) hardening
- [ ] **RunEtaChannel IDOR** (`app/channels/run_eta_channel.rb:3`) —
      `stream_from "run_eta_#{params[:run_id]}"` does no authorization; `run_id`
      is sequential, so any connected client can stream any run's ETA + broadcast
      `driver_lat`/`driver_lng`. Authorize that the subscriber belongs to the run.
- [ ] **Twilio inbound webhook has no signature validation**
      (`app/controllers/twilio_sms_controller.rb`) — verify `X-Twilio-Signature`
      via `Twilio::Security::RequestValidator` before acting. Currently anyone can
      POST `Body=STOP&From=<victim phone>` to opt a customer out.
- [ ] **Portal ActionCable auth rejects passwordless riders** —
      `ApplicationCable::Connection#find_verified_user` requires a Warden user or
      API token; magic-link portal riders (`CustomerAuth`) have neither, so the
      live-ETA + driver-map feature never receives data for the riders it's built
      for. Reconcile cable auth for the portal.
- [ ] NIT: STOP handler matches last-10-digits `LIKE '%digits'` — can disable
      multiple customers sharing a phone suffix.
- [ ] NIT: leftover `console.log` in `app/assets/javascripts/channels/run_eta.coffee:12,15`.

## 🟡 Correctness / robustness

### Route optimization (#6)
- [ ] **Double-optimize race** (`app/jobs/overnight_optimize_job.rb:50-65`) —
      enqueues both a per-run `RouteOptimizeJob` and a per-provider
      `FleetOptimizeJob` over the same trips, both async, both writing
      `estimated_pickup_time`/`manifest_order`; results clobber each other
      non-deterministically. Pick one level or sequence them.
- [ ] **Stale manifest after reassignment**
      (`app/services/fleet_optimizer_service.rb:220-246`) — `apply_result` only
      resets manifests for runs that received assignments; a run whose trips were
      all moved away keeps a stale `manifest_order`. Also uses `update_all`
      (bypasses provider-scoping/capacity validations).
- [ ] `open_timeout` not set on optimizer HTTP calls
      (`route_optimizer_service.rb:305`, `fleet_optimizer_service.rb:152`);
      `FleetOptimizeJob`/`OvernightOptimizeJob` have no `retry_on`.
- [ ] NIT: `total_distance_m` returns the time-based objective value, not meters.
- [ ] NIT: 1472-line internal handover doc committed to the tree — consider moving out.

### AVL poller (#5)
- [ ] **Dedup one-sided range** (`app/worker/avl_poller_worker.rb`) —
      `.where("log_time >= ?", log_time - 2.seconds)` matches rows newer than the
      incoming fix, so clustered/out-of-order timestamps can silently drop legit
      GPS points. Bound both sides.
- [ ] **Fragile boot rescue** (`config/initializers/avl_poller.rb:6`) —
      `Provider.where(...).exists?` at Sidekiq boot is only guarded by
      `rescue LoadError`; broaden it so an unmigrated/unreachable DB can't break startup.
- [ ] **Self-re-enqueue dies at zero providers** — the poll loop only re-enqueues
      `if providers.any?`; if no provider has `use_external_avl` at tick time,
      polling stops until process restart.

## 🔴 Database schema needs a deliberate rebuild (do NOT blind-dump)

After merging the feature branches, `db/schema.rb` is stale and inconsistent, and
**regenerating it by dumping from the dev DB would make things worse.** Assessed
2026-07-14; deliberately deferred rather than done wrong:

- `db/schema.rb` is missing `customer_auths` (SMS) and its version line is the
  malformed `202103162114206` (16 digits; real Rails versions are 14). It has been
  hand-edited and is not a faithful dump.
- The dev DB has all feature migrations applied (`up`), but also carries several
  `NO FILE` migrations from *other* branches (2023/2024). Dumping `schema.rb` from
  it would import those other-branch changes onto `victoria-transit-rails7`.
- `20260218140000_create_gps_locations_view` runs raw SQL (`CREATE VIEW
  gps_locations_view`). The project uses the default `schema_format = :ruby`, which
  **cannot represent a SQL view** — so `schema.rb` is structurally incapable of
  describing this schema, and a `db:schema:load` on a fresh DB would omit the view.

**Recommended fix (dedicated task, clean environment):**
- [ ] Switch to `config.active_record.schema_format = :sql` so `db/structure.sql`
      captures the `gps_locations_view` (and any future views/partitioning/PostGIS).
- [ ] Rebuild from migrations in a throwaway/clean DB (not the polluted dev DB),
      then commit the regenerated `structure.sql`.
- [ ] The one genuinely-pending migration on the dev DB is
      `20260713120000_add_omniauth_to_users` (#10, O365) — apply it as part of the
      clean rebuild.

## Integration testing still outstanding
The AVL (#5), optimizer (#6), and SMS (#7) features were **static-reviewed only** —
not runtime-verified. Before production they need live testing against their
sidecars: OpenTransit/busavl GPS source, the Python OR-Tools/OSRM optimizer
service, and Twilio.
