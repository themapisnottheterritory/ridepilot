# Fare Card Design Recommendation

Written 2026-09-10 for RidePilot at GCRPC / Victoria Transit. Updated same day after reviewing tap to pay.
Status: everything built and configured (sections 11 to 16); all policy questions answered (section 14). Pilot hardware next.
Budget assumption: near zero. Existing driver tablets, existing RidePilot server, cheap off-the-shelf parts.
Fare today: $1.50, and the goal is to bring it down, not up.

**Decisions so far**

- Account-based ledger in RidePilot, token-agnostic (section 4). This is the part every option shares.
- **Frequency: 13.56 MHz, decided 2026-09-10.** Philz and Andrew both concur (section 2.2). MIFARE / NTAG cards,
  the ESP32 + RC522 prototype, and 13.56 MHz USB HID readers. The 125 kHz EH301 and its EM4100 cards are out.
- Pilot two tokens on the same backend: RFID card on one bus, QR code on another (section 8).
- **Phase 1 built 2026-09-10** (section 11): migration, ledger, office pages, activity report.
- **Phase 2 built 2026-09-10** (section 12): tap endpoint, tablet scanner, offline queue, QR sheets, fare settings.
  QR codes are read by a **USB 2D barcode scanner**, not the tablet camera: same keyboard-wedge path as the RFID reader.
- **Phase 3 built 2026-09-10** (section 13): demand-response pickup tap, online reload job (Stripe pull, not yet configured).
- Tap to pay (bank card / phone wallet) explored and **paused** (section 10). Percentage fees do not fit a $1.50 fare.
- Connectivity is not the constraint. Every bus has a Pepwave MAX BR1 LTE router and the tablets have their own LTE.
  Offline is a fallback path, not the design center.
- **Fare policy settled 2026-09-10** (section 17): published fixed-route fares; distance-band rural table; ADA
  paratransit $1.50 flat inside Victoria; 60+ is the senior threshold everywhere; 10-ride 10% off, 20-ride 20% off,
  monthly unlimited $30 / $15 reduced; transfers 90 minutes onto a different route, one per paid fare; balance
  may go to -$5.00. All set in production.

---

## 1. What is left of the earlier attempt

Searched every checkout on 10.0.0.16 (rptest, rpmaster, rplite, pzdev, ~/ridepilot) plus git history,
branches and stashes.

| Where | What |
|---|---|
| `db/schema.rb` | Two orphan tables: `fare_cards` (card_id, customer_id) and `fare_card_data` (fare_card_id, bus_id, msg_direction, latitude, longitude). No model, migration, controller, view, or route uses them. They came in through the Rails 7 upgrade schema dump, so a DB built from migrations would not have them. |
| `ops/git-hooks/pre-commit` and its README | Name both tables explicitly so the test-DB schema dump does not silently delete them. |
| Production DB `ridepilot` | 6 rows in `fare_cards`, all for test customers (Gabriel Acosta, Thalia Acosta, Elmer Street), issued 2023-12-21 to 2024-01-05. `fare_card_data` is empty. |
| Older checkouts | Nothing. |

The six stored card IDs tell you which prototype produced them:

| card_id | Looks like |
|---|---|
| `0009350016` | 10-digit decimal, classic 125 kHz EM4100 output. The FissaiD EH301. |
| `0431539525214987`, `1579487351240384`, `3034190240013754` | 7-byte MIFARE UID in decimal. The ESP32 + RC522 (13.56 MHz). |
| `12345678910123457`, `12345678910123356` | Typed by hand. |

**Recommendation:** drop both tables in a real migration when the new schema (section 4) lands.
The old design had no balance, no ledger and no reload path, so there is nothing worth keeping
except the idea "card maps to customer, log every tap".

---

## 2. Core decisions

### 2.1 Account-based, not card-based

The card carries nothing but its factory UID. The balance lives in RidePilot on the **customer**, not
on the card. Consequences:

- No writers, ever. Every cheap reader can read a UID.
- No keys, no encryption, no card personalisation step. Issuing a card is "scan it, pick the customer".
- Lost card = flip the row to `blocked`, hand out a new card, balance follows the customer.
- Multiple active cards per customer is fine (rider plus caregiver, for instance).
- The token does not have to be a card. A printed QR code, or later a bank-card reference, hangs off the same
  customer and the same ledger. Section 4 models this as `fare_tokens` with a `kind`.

### 2.2 Frequency: 13.56 MHz (decided)

The two prototypes use different frequencies and their cards are not interchangeable.

| | 125 kHz (EH301, EM4100 cards) | 13.56 MHz (RC522, MIFARE / NTAG cards) |
|---|---|---|
| Blank card cost | similar | similar, $0.15 to $0.40 printable |
| USB HID keyboard readers | plentiful | plentiful |
| Phone can read it | no | yes (Android NFC, iPhone) |
| Clone difficulty | trivial (T5577 blanks, $20 cloner) | easy for UID-only, but harder |
| Future options | none | rider self-check with phone, NTAG URL, secure sectors later |

**Decided 2026-09-10: 13.56 MHz.** Andrew concurs. The ESP32 + RC522 prototype is already on the right frequency. The EH301 is
still useful as a mounted, enclosed reader on a desk or at a balance-check station if you buy a
13.56 MHz variant of the same style; the 125 kHz unit you have can stay a bench tool.

Whatever the reader, it must emit the UID in **one canonical format**. Standardise on the uppercase
hex UID (e.g. `04A3B2C1D9E6F0`), not the decimal conversion, and convert on the way in if a reader
insists on decimal. Store the canonical form once and look up by it.

### 2.3 No Pi on the bus, at least to start

The driver tablets already run the RideAVL driver app and talk to `/api/v1/...`. A USB HID reader on
an OTG cable behaves as a keyboard and types the UID into whatever field has focus. The driver app
adds a hidden always-focused capture field and posts the UID.

- One cable and one reader per bus. No second device to power, network, mount or keep patched.
- Run context, driver identity, GPS all come for free from the tablet.
- Connectivity: Pepwave MAX BR1 on every bus plus LTE in the tablet. Taps go straight to the server;
  the offline queue only has to cover dead spots and router reboots.
- The ESP32 + RC522 build becomes the **rider-facing validator** option later: it can act as a USB HID
  keyboard itself (ESP32-S2/S3 native USB) and beep / light green or red, and still just types the UID
  into the tablet. That keeps the tablet as the only thing that talks to the server.

A Pi only earns its place as a standalone station (section 6), never as bus-side middleware.

---

## 3. Hardware and cost

| Item | Qty | Unit cost | Notes |
|---|---|---|---|
| USB 13.56 MHz HID reader (reads MIFARE / NTAG UID as keystrokes) | 1 per bus + 2 office | $10 to $20 | Buy the same model everywhere. Confirm it outputs hex UID, or is configurable. |
| USB-C OTG cable | 1 per bus | $5 | Match the tablet port. |
| Blank white PVC MIFARE Classic 1K or NTAG213 cards | 200 | $0.15 to $0.40 | Printable if you want a logo; a Sharpie serial is fine to start. |
| ESP32-S3 + RC522 rider-facing validator with buzzer and LED | optional, per bus | $8 to $15 | You already have this working. Enclosure is the real cost. |
| Pi Zero 2 W + reader + small display, balance-check station | optional | $50 to $60 | Transit center lobby. |

Total for a 6-bus pilot with the office end: well under $300.

**Do not buy:** card writers, encoders, cash-accepting kiosks (bill validator alone is $150 to $300 plus
a vandal-proof enclosure), or any reader tied to vendor software.

---

## 4. Data model

Replace the two orphan tables with an append-only ledger. Balance = sum of the ledger; a cached copy
sits on the customer for speed.

```
fare_tokens                   (was fare_cards; renamed so QR and RFID share one table)
  id
  kind             enum: rfid | qr | bank_card_ref
  uid              string, unique, canonical form per kind:
                     rfid          uppercase hex UID, e.g. 04A3B2C1D9E6F0
                     qr            random 12-char base32 token printed as the QR payload
                     bank_card_ref processor token (Stripe pm_...), never a PAN. Unused while tap to pay is paused.
  serial           string, short printed number on the card / QR sheet, unique (lookup without a reader)
  customer_id      -> customers
  status           enum: active | lost | blocked | retired
  issued_at, issued_by_user_id
  deleted_at (acts_as_paranoid), timestamps, paper_trail

fare_transactions             (append only, never updated or deleted)
  id
  customer_id      -> customers
  fare_token_id    -> fare_tokens, nullable (office adjustments have no token)
  kind             enum: load | debit | refund | adjust | transfer_in | transfer_out
  amount           decimal(8,2), positive for load/refund/transfer_in, negative for debit/transfer_out
  balance_after    decimal(8,2)
  provider_id
  run_id           nullable
  trip_id          nullable        (UDR)
  fixed_route_boarding_id nullable (fixed route)
  payment_method   enum: cash | check | card_online | none   (loads only)
  reference        string          (check number, Stripe payment id, receipt number)
  recorded_by_user_id / driver_id
  client_uuid      string, unique  (idempotent retries from the tablet, same pattern as boardings)
  recorded_at, created_at

customers  (add)
  fare_balance     decimal(8,2), default 0, cached, recomputed from ledger
  fare_balance_floor decimal(8,2), nullable, per-customer override of the provider floor
  pass_expires_on  date, nullable   (monthly unlimited pass, no debit while valid)
  default_rider_category_id -> rider_categories (drives the fixed-route fare)

providers (add, or a fare_settings table)
  card_fare_default        decimal(6,2)
  card_negative_floor      decimal(6,2), e.g. -5.00
  transfer_window_minutes  integer, e.g. 90
```

Add a `Card` row to the existing `fare_types` lookup so fixed-route reporting can separate
card boardings from cash and pass.

---

## 5. Tap flow

### 5.1 Fixed route (the easy one)

One tap = one boarding. Driver app is on the walk-on screen. An RFID reader types the UID; a QR is read by
the tablet camera. Both land on the same endpoint.

```
POST /api/v1/runs/:id/token_taps   { uid, client_uuid, recorded_at, latitude, longitude, stop_id? }
```

Server:

1. Look up `fare_tokens` by uid. Unknown, lost or blocked -> 404/422, tablet shows red, driver falls back
   to the normal cash / pass buttons.
2. Resolve customer -> default rider category -> fare from the fixed-route lookup amounts (already in
   `fare_types.fare_factor` and the route default fare added 2026-09-04).
3. Transfer check (decided 2026-09-10): a **paid** tap by this rider inside `transfer_window_minutes`
   (90), on a **different route** when `fare_transfer_different_route_only` is set (it is), and no
   transfer already used on that fare -> fare 0, boarding recorded as Free / Transfer. Chaining Red ->
   Pink -> Red pays on the way home.
4. Pass check: `pass_expires_on >= today` -> fare 0.
5. Write one `FixedRouteBoarding` (boarded_count 1, fare_type Card, fare_amount) and one
   `fare_transactions` debit in a transaction. Return new balance so the tablet can show it for 2 seconds.
6. Below the negative floor -> 422 with balance; tablet shows red plus the balance; driver takes cash.

Offline (fallback only, given the Pepwave and tablet LTE): at run start the tablet fetches
`{ uid, customer_name, rider_category_id, balance, pass_ok }` for all active tokens (a few hundred rows). Taps are accepted locally and queued with `client_uuid`,
same as boardings today. On sync the server recomputes; a tap that ends up under the floor is recorded
anyway and the account is flagged for the office.

### 5.2 UDR / demand response (a little more complex)

The trip already knows the customer, the fare and has `fare_collected_time`. A tap at pickup is a
**confirmation and a debit**, not a lookup.

```
POST /api/v1/trips/:id/token_tap   { uid, client_uuid, recorded_at }
```

Server:

1. Resolve token -> customer.
2. If the customer is the trip's customer: debit `trip.fare_amount`, set `fare_collected_time`, set
   `trip.fare` to a payment fare. This reuses the logic in `update_fare`.
3. If the card belongs to someone else: return 409 with both names. Tablet asks the driver "Charge
   Elmer Street's card for Thalia Acosta's trip?" Yes -> debit that customer, record both ids on the
   transaction. This covers caregivers paying for riders.
4. Guests and attendants: policy decision. Simplest rule: **one tap covers the whole trip fare** as
   RidePilot already computes it. Per-person taps can be added later if the fare structure needs it.
5. Below floor -> same as fixed route. Never strand anyone; flag the account.

Offline works the same as fixed route because the trip fare is already on the tablet.

---

## 6. Recharge, cheapest first

1. **Front desk in RidePilot.** A staff page: scan the card (same USB reader on the PC, types into the
   search field) or type the printed serial, see customer and balance, enter amount, pick cash / check,
   print a receipt. One reader. This is the entire MVP.
2. **Driver reload on the bus.** Same ledger, driver enters amount and takes cash. Reconciles against
   the run's cash total in the existing driver run reports. Common in rural systems, but it is cash in
   drivers' hands. Your call.
3. **Online.** Stripe or Square payment links, no monthly fee. A scheduled job inside the network pulls
   completed payments and posts `load` transactions. **Nothing inbound**, which keeps to the house rule
   that internal apps never face the internet. The customer needs a way to identify their account on the
   payment page: the printed card serial is enough. Card-not-present fees are 2.9% + $0.30, so a $10 load
   costs $0.59 (5.9%) and a $20 load $0.88 (4.4%). Encourage $20 loads with a small bonus if it matters.
4. **Balance-check station.** Pi Zero 2 W, reader, small screen, in the transit center lobby. Shows
   balance and last five rides. Cheap, riders like it, no cash inside so no security problem.
5. **Cash kiosk: skip it.** The bill validator and a vandal-resistant enclosure cost more than the rest
   of this project combined, and the front desk already takes cash.

---

## 7. Risks accepted

- **UID cloning.** A phone can clone a UID-only card. At a couple of dollars a ride and with a ledger
  that makes duplicate patterns visible, this is not worth engineering against. If it becomes a
  problem, NTAG / MIFARE secure sectors are available on the same cards and readers with a firmware
  change on the ESP32 validator.
- **Reader output format drift.** Different readers decimal vs hex, with or without leading zeros.
  Solved by normalising to hex on the server and by buying one reader model.
- **Negative balances.** Bounded by the floor. Visible on a report.
- **Tablet port wear.** OTG cable stays plugged in; strain-relieve it.

---

## 8. Build order

| Phase | What | Proves |
|---|---|---|
| 0 | Buy 2 USB HID 13.56 MHz readers, 50 cards, OTG cable. Confirm the UID types correctly into a tablet field and a Windows browser field. | Hardware path |
| 1 | Migration for `fare_cards`, `fare_transactions`, customer columns, `Card` fare type. Drop the two orphan tables. Staff pages: issue card, load value, balance, history, block/replace. Balance and daily cash reports. | Office can run it |
| 2 | **Done 2026-09-10.** Fixed-route tap endpoint plus tablet capture on the walk-on screen. **Pilot two tokens on the same backend: RFID reader on one bus, a USB 2D barcode scanner for QR sheets on another.** Offline queue as fallback. Watch which one riders and drivers reach for. | Bus side, token choice |
| 3 | **Done 2026-09-10.** UDR pickup tap, mismatch confirm, guest rule. | Demand response |
| 4 | Stripe pull job for online loads (**built 2026-09-10**, needs a Stripe account and key). Lobby balance-check station. ESP32 rider-facing validator if wanted. | Nice to have |

---

## 9. Open questions (not blocking phases 0 and 1)

1. ~~Are the driver tablets on LTE, or Wi-Fi only?~~ Answered: Pepwave MAX BR1 on every bus, LTE in the tablets. Offline is a fallback.
2. Stored value only, or also a monthly unlimited pass?
3. Is driver-handled reload cash acceptable?
4. Does one tap cover guests and attendants on a UDR trip?
5. ~~Which interface does the EH301 on hand actually have?~~ Moot: it is 125 kHz and the frequency decision
   retires it. Only revisit if a 13.56 MHz unit in the same enclosure is wanted for a desk.

---

## 10. Tap to pay: explored and paused

"Tap to pay" here means the rider taps a bank card or phone wallet. Two ways to do it were looked at on
2026-09-10, and both are parked. The account-based ledger in section 4 is built so either can be added
later without touching the tables.

### What was looked at

| Option | How it works | Recurring cost | Hardware |
|---|---|---|---|
| Stripe (or Square) Tap to Pay on Android | The driver tablet's own NFC becomes a card terminal. Driver starts a charge, rider taps. Needs internet at the moment of the tap. | 2.7% + $0.15 per tap, no monthly fee | none |
| Transit open loop (Littlepay-type processor + bus validator) | Rider taps a validator, processor aggregates and applies fare capping and transfers. | about $0.25 per tap, roughly 7% of revenue at Far North Transit Group (four rural California agencies) | validator per bus, several hundred dollars each, plus a merchant acquirer |
| Mobile ticketing app (Token Transit and similar) | Rider buys in the app, driver validates by looking at the phone. | a percentage of sales, quote needed | none |

### Why it is paused: the numbers at a $1.50 fare

Percentage-plus-fixed fees are designed for coffee, not for a fare we are trying to push below $1.50.

| Channel | Fee on one $1.50 fare | Share of fare | Net to agency |
|---|---|---|---|
| Cash or RFID / QR tap (closed loop) | $0.00 | 0% | $1.50 |
| Stripe Tap to Pay on Android | $0.19 | 12.7% | $1.31 |
| Transit open loop, Far North figure | $0.25 | 16.7% | $1.25 |
| Same Stripe fee if the fare drops to $1.00 | $0.18 | 17.7% | $0.82 |

Scaled to 10,000 fares, which is $15,000 gross:

| Channel | Fees on 10,000 fares | Left over |
|---|---|---|
| Closed loop RFID / QR (after ~$300 one-time hardware) | $0 | $15,000 |
| Stripe Tap to Pay, per fare | $1,905 | $13,095 |
| Transit open loop, per fare | $2,500 | $12,500 |
| Stripe tap used only to **reload** $10 at a time | $630 | $14,370 |
| Stripe tap used only to reload $20 at a time | $518 | $14,482 |
| Online Stripe link, $10 loads (2.9% + $0.30) | $885 | $14,115 |
| Online Stripe link, $20 loads | $660 | $14,340 |

Three things fall out of that table:

1. **Per-fare card processing costs an eighth to a sixth of revenue.** That is the same money a fare cut
   would give riders. It goes to the processor instead.
2. **Fees are mostly the fixed cents, not the percentage.** The $0.15 fixed part is 10% of a $1.50 fare on
   its own. Charging a bank card once per $10 or $20 load, rather than once per ride, cuts the fee to 3 to 4%.
3. **Closed loop is free per tap** and the whole hardware bill is under $300. The trade is staff time at the
   front desk to take cash and checks, which we already spend today.

### The other reasons

- Riders. A rural, older, disabled and lower-income ridership carries fewer bank cards and smartphones.
  A token we issue at the desk works for everyone; a bank card does not.
- Transit logic. Stripe and Square terminals know nothing about transfers, reduced fares, or passes.
  All of that would still be built in RidePilot, so tap to pay saves no engineering, it only changes the
  token.
- Flow. A merchant terminal makes the driver start a charge for an amount before the rider taps. That is
  slower at the door than a validator or a reader that just reads.

### If it comes back

The cheap re-entry is Stripe Tap to Pay on the tablet **as a reload channel**: the driver taps a rider's bank
card once to add $10 or $20 to their account, then the rider uses their RFID card or QR for each ride. It
removes cash from the bus, costs one fee per load, and needs no validator. In the schema it is one
`fare_transactions` load row with `payment_method: card_online` and the Stripe id in `reference`. The
`bank_card_ref` token kind exists for the day a rider wants their bank card itself to act as their token,
at which point the per-tap fee argument has to be re-run at whatever the fare is then.

---

## 11. Phase 1 as built (2026-09-10)

Branch `fixed-route-wp8`, commit "Fare cards phase 1". Everything below is office-side; nothing touches the
tablet yet.

**Deploy**

```sh
docker exec ridepilot_app_1 sh -c 'cd /var/www/ridepilot && bin/rails db:migrate && bin/rake ridepilot:add_v2_custom_reports'
```

The migration drops `fare_cards` / `fare_card_data` (six test rows) and the pre-commit hook comment was
updated to match. Commit the schema with `--no-verify`, as the hook says to for a real drop.

**Schema** (as in section 4, with these names)

- `fare_tokens`: provider_id, customer_id, kind (rfid | qr | bank_card_ref), uid, serial, status
  (active | lost | blocked | retired), note, issued_at, issued_by_user_id, deleted_at. Unique uid among
  live rows; unique serial per provider.
- `fare_transactions`: append-only, no updated_at. provider_id, customer_id, fare_token_id, kind, signed
  amount, balance_after, payment_method (cash | check | card_online, loads only), reference, note, run_id,
  trip_id, fixed_route_boarding_id, recorded_by_user_id, driver_id, client_uuid (unique), recorded_at.
- `customers`: fare_balance (cached), fare_balance_floor, fare_pass_expires_on, default_rider_category_id.
- `providers`: fare_negative_floor (default 0), fare_transfer_window_minutes (default 90).
- `fare_types`: a `Card` row, fare_factor 1.0.

**Code**

- `app/services/fare_ledger.rb` is the only thing that changes a balance: `load!`, `debit!`, `refund!`,
  `adjust!`, `transfer!`. Row lock on the customer, floor check on debits (`allow_below_floor:` for a tap
  that already happened offline), idempotent on `client_uuid`. Phase 2's tap endpoint calls `debit!`.
- `FareToken.lookup(raw)` resolves what a reader typed: separators stripped, upcased, then the other
  radix with the usual zero padding, so an office reader set to decimal still finds a card the bus reader
  reads in hex. Serial lookup is done by the controller (`#55` or `55`).
- QR tokens mint their own 12-character uid (no vowels, never starts with a digit). Printing the QR is
  phase 2.
- `FareTransaction` is read-only once saved. Corrections are further rows.

**Pages**

- Fare Cards (top nav): scan box with focus, so a USB HID reader goes straight to the rider. Today's
  loads by method, balances outstanding, every rider with a token or a balance.
- Rider fare account (`/customers/:id/fare_account`, also a button on the rider record): balance and
  pass, tokens with Lost / Block / Reactivate / Retire, issue form (kind, uid from the reader, printed
  serial), load form with $5 / $10 / $20 buttons and cash / check, refund and adjustment behind a
  disclosure with a required reason, paged ledger. Optional printable receipt.
- Fare Card Activity report (Reports): date range, grouped by day / payment method / type / posted by /
  rider. Cash in, checks in, fares, refunds, adjustments, net, and the total riders hold on account.

**Permissions**: editors at a scheduling provider get manage on FareToken and FareTransaction; read-only
roles see the pages without the forms.

**Specs**: `spec/models/fare_token_spec.rb`, `spec/services/fare_ledger_spec.rb`,
`spec/controllers/fare_accounts_controller_spec.rb`, `spec/controllers/reports/fare_card_activity_controller_spec.rb`.
`spec/support/fare_card_helpers.rb#create_rider` builds a customer with the associations Rails 7 now
requires, because the old customer factory cannot.

**Left for phase 2**: driver API tap endpoints (`debit!` is ready for them), tablet capture field, offline
snapshot, QR printing, the pass product's office UI (the column exists), rider category on the customer
form (the column exists).

---

## 12. Phase 2 as built (2026-09-10)

RidePilot branch `fixed-route-wp8`, commit "Fare cards phase 2 (server)". Tablet: rideavl-v2 **1.0.8**,
commit "Fare card taps on the fixed-route screen", APK at `~/ridepilot-ops/rideavl-1.0.8-fare-cards.apk`
(not yet copied to `public/rideavl-pilot.apk`; that is the deploy step).

**One decision changed from the plan: QR is read by a USB 2D barcode scanner, not the tablet camera.**
A $25 keyboard-wedge scanner types the QR's text exactly the way the RFID reader types a UID, so both
tokens share one code path on the tablet and nothing needs the camera, a Capacitor plugin or a
permission prompt. Camera scanning can still come later if a bus wants it.

**Deploy**

```sh
docker exec ridepilot_app_1 sh -c 'cd /var/www/ridepilot && bundle install && bin/rails db:migrate'
# tablets: install ~/ridepilot-ops/rideavl-1.0.8-fare-cards.apk (or copy it to public/rideavl-pilot.apk and commit)
```

`bundle install` is for `rqrcode`; gems live in the `bundle_cache` volume, so no image rebuild.

**Server**

- `POST /api/v1/runs/:id/token_taps` `{ uid, client_uuid, recorded_at, stop_id?, stop_name?, direction?,
  latitude?, longitude?, offline? }`. Answers with the usual boardings payload plus `tap:` (rider name,
  category, fare type, fare, balance, transfer / pass / double_tap / duplicate flags). Failures carry a
  `code`: `unknown_token` (404, with the normalised uid), `token_not_usable`, `below_floor` (with balance
  and fare), `tap_failed`.
- `GET /api/v1/runs/:id/fare_tokens`: every active token with rider name, category fare, balance, floor
  and pass status. The tablet caches it per run for offline answers.
- `app/services/fare_tap.rb` holds the rules from section 5.1: unknown / blocked / inactive refused;
  same run inside 2 minutes ignored; valid pass -> Pass fare type, $0; earlier tap inside the provider's
  transfer window -> Free / Transfer, $0; otherwise category default fare x Card factor, debited through
  FareLedger. Below the floor is refused unless `offline: true`. A printed serial works in place of a uid.
  Phase 3's UDR trip tap reuses `resolve!`.
- Undoing a tapped walk-on (`DELETE boardings/:client_uuid`) refunds the debit, idempotently.
- `fixed_route_boardings` gained `customer_id` and `fare_token_id`; `submission_json` now carries
  `rider_name` and `tapped`.
- Office: rider category, pass expiry and per-rider floor on the fare account page (`PATCH
  customers/:id/fare_account`). `GET fare_tokens/:id/print` is a card-sized QR sheet (rqrcode SVG).

**Tablet (rideavl-v2 1.0.8)**

- `HidScannerService`: document-level keydown listener. A burst of keys under 80 ms apart, at least 4
  long, ending in Enter, is a scan. Keys typed into a real input are ignored, and the soft keyboard never
  appears because nothing holds focus.
- `TokenTapService` + `TokenTapSyncService`: post the tap, or queue it in IndexedDB and replay with
  `offline: true`. Same idempotency as walk-ons.
- Fixed-route screen: green card (name, category, fare, balance; pass / transfer / already tapped) for
  4 s, red card (unknown, refused, balance too low, take cash) for 7 s. A toolbar card button lets the
  driver type the printed number. Tapped walk-ons show the rider's name in Recent, and undo refunds.
- Version 1.0.8 / code 9.

**Specs**: `spec/services/fare_tap_spec.rb`, `spec/controllers/api/v1/driver/token_taps_controller_spec.rb`
(45 fare examples in all, green). The tablet has no automated tests for this; the pilot bus is the test.

**Hardware to order for the pilot**

| Bus | Reader | Cards |
|---|---|---|
| RFID pilot bus | USB 13.56 MHz HID reader, hex output, Enter suffix | MIFARE Classic 1K or NTAG213 blanks |
| QR pilot bus | USB 2D barcode scanner (HID keyboard mode, Enter suffix) | QR sheets printed from the account page, laminated |
| Office | one of each, same models | |

Both readers plug into the tablet with a USB-C OTG cable. Set the RFID reader to output the UID in hex;
the server copes with decimal too, but hex is the canonical form.

**Left for phase 3**: UDR pickup tap (`POST trips/:id/token_tap`, mismatch confirm, guest rule), and the
online reload job.

---

## 13. Phase 3 as built (2026-09-10)

RidePilot branch `fixed-route-wp8`, commit "Fare cards phase 3 (server)". Tablet: rideavl-v2 **1.0.9**,
APK at `~/ridepilot-ops/rideavl-1.0.9-fare-cards.apk` (supersedes 1.0.8; still not copied to
`public/rideavl-pilot.apk`).

**Deploy**

```sh
docker exec ridepilot_app_1 sh -c 'cd /var/www/ridepilot && bundle install && bin/rails db:migrate'
```

Then set the demand-response card fare on the provider page (General, Fare related settings): three new
fields, the card fare per demand-response trip, the lowest balance allowed, and the transfer window.
Until the card fare is set, a tap at pickup uses the amount on the trip, and failing that the rider's
category fare.

**Demand-response pickup tap** (section 5.2 as designed, with these details)

- `POST /api/v1/trips/:id/token_tap` `{ uid, client_uuid, recorded_at?, amount?, confirm_mismatch? }`.
  The trip must be on one of the driver's runs. Amount precedence: what the driver typed, the amount on
  the trip, the provider's demand-response card fare, the rider's category fare.
- Someone else's card answers **409 `mismatch`** with both names. The tablet asks "Charge X's card for
  Y's trip?" and resends with `confirm_mismatch: true`; the ledger row notes who it paid for.
- **One tap covers the whole trip**, guests and attendants included. A valid pass is free but still marks
  the fare collected. Free and donation trips refuse a tap. Already collected refuses a tap.
- `DELETE /api/v1/trips/:id/token_tap` refunds and clears the collected mark. Undoing the pickup itself on
  the tablet does the same, so the ledger never disagrees with the trip.
- The itinerary JSON now carries `default_amount`, `card_on_file`, `card_balance` and `paid_by_card`, so
  the pickup screen prefills the fare box, shows "has a card · $12.50" when a tap is expected, and shows
  "paid by card" with an undo afterwards.
- Card payments at pickup are **online only**, like every other manifest action. Offline the tablet says
  take cash. The Pepwave makes this rare.

**Online reloads** (section 6.3 as designed)

- `StripeReloadSync` and `rake fare_cards:sync_online_reloads` pull paid Checkout Sessions from the last
  7 days and post one `card_online` load per session, idempotent on the session id
  (`client_uuid = stripe-<session id>`). Nothing inbound; the job runs from cron inside the network.
- The rider is matched by the **card number** they type into the Payment Link's custom field (the printed
  serial). A number nobody has, or a non-USD session, is listed as UNMATCHED in the job output for the
  office to load by hand from the receipt email.
- Not yet configured: there is no Stripe account or key. To turn it on:
  1. Create a Stripe account for the provider. Products: "Fare card reload $10" and "$20" (or one product
     with customer-chosen amount).
  2. Payment Link -> Advanced -> **custom field**, type text, label "Fare card number", required.
  3. Put `STRIPE_SECRET_KEY=sk_live_...` in `docker/.env` and recreate the app container.
  4. Cron, next to the nightly scheduler:
     `*/30 * * * * /usr/bin/docker exec ridepilot_app_1 bundle exec rake fare_cards:sync_online_reloads PROVIDER_ID=1 >> /home/philz/ridepilot-fare-reloads.log 2>&1`
  5. Print the link's QR on the card sheet and the balance receipt.
- Fee reminder from section 10: 2.9% + $0.30 card-not-present, so nudge riders to $20 loads.

**Specs**: `spec/services/fare_tap_trip_spec.rb`, `spec/controllers/api/v1/driver/trips_token_tap_spec.rb`,
`spec/services/stripe_reload_sync_spec.rb` (stubbed Stripe client). 61 fare examples in all, green.

**Everything in the plan is now built except hardware.** What remains is the pilot itself: order the
readers and cards (section 12), issue cards at the desk, install 1.0.9 on the two pilot buses, and watch
the Fare Card Activity report for a month.

---

## 14. Open questions for the transit team (2026-09-10)

Checked the published fare pages at gcrpc.org (urban fare schedule, rural fare schedule, commuter,
paratransit) against what is in production. Fixed route matches exactly. The rest needs decisions
before the pilot buses go live; sent to the transit team by email the same day.

| # | Question | Where it stands | Needs |
|---|---|---|---|
| 1 | Do fixed-route fares match the website? | Yes: Youth 0-5 free with paying adult, Youth 5-17 $0.75, Adult $1.00, Senior 60+ $0.50, Disabled $0.50. A tap charges exactly these. | nothing |
| 2 | Transfer policy? | **Decided 2026-09-10: 90 minutes, different route only, one transfer per paid fare.** A paid tap on Green then a tap on Pink inside 90 minutes is free; tapping Green again on the way home pays. Set in production (`fare_transfer_window_minutes`, `fare_transfer_different_route_only`). Still to publish on the fare page. | done |
| 3 | Paratransit (ADA demand-response) fare? | **Answered 2026-09-10: $1.50 flat**, from the "Fare Structure as of September 1st, 2026" sheet (photo `~/IMG_1917.HEIC`). Rule: rider is ADA eligible and both ends of the trip are in the urban service area. Built and set in production, see section 15. | done |
| 4 | Demand-response and commuter fares with a card? | **Built 2026-09-10 (section 15).** Per-provider schedule of mileage band x rider category, seeded from the published Victoria/DeWitt rural table; prices a trip from its `drive_distance`, rider plus one adult fare per guest, attendants free. Editable on the provider page. Commuter service is the same table shape but not wired yet (fixed-route walk-ons have no per-rider distance). | done |
| 5 | Senior is 60+ on fixed route, 65+ (plus a Medicare column) on the commuter. Which? | **Answered by the 2026-09-01 fare sheet: 60+ everywhere** ("Elderly/Disabled (60+)" for fixed route and rural). The commuter web page's 65+ is the outlier. One category on the card is right. | done |
| 6 | The website says 10-trip, 20-trip and monthly passes are "available soon". | **Built and priced 2026-09-10 (section 16).** Philz's prepay table adopted: 10-ride 10% off, 20-ride 20% off, monthly $30. Set in production. **Reduced-fare monthly $15** for senior, disabled and youth added the same day. Monthly is unlimited rides through month end. | done |
| 7 | Which services does the card cover? | Victoria Transit fixed route, and demand response in Victoria and DeWitt counties (the one active provider). Calhoun, Goliad, Lavaca, Jackson, Matagorda run their own schedules. Gonzales is free. | nothing |
| 8 | How do riders reload? | Front desk, cash or check, printed receipt (live). Online by card is built (section 13) but off: needs a Stripe account, carries 2.9% + $0.30, steer riders to $20 loads. | decision on Stripe, later |
| 9 | What happens when a card is low? | **Decided 2026-09-10: floor is -$5.00** (`providers.fare_negative_floor`, set in production). A rider can owe up to $5.00 and is settled at the next reload; below that the tap is refused and the driver takes cash. The office sees negative balances in red on the Fare Cards page. | done |
| 10 | What should the website say? | After 2, 3, 5, 6 and 9: describe the card, where to get and reload it, the transfer rule, pass prices; drop "available soon". Draft it with the pilot launch. | after decisions |

**All ten answered.** Setup is complete; what remains is ordering the pilot readers and cards (section 12) and the fare page text (question 10).

The internal sheet "Fare Structure as of September 1st, 2026" (photo `~/IMG_1917.HEIC`, thumbnail only) also
says Gonzales County fares are reinstated 2026-10-01; that is another provider's service, nothing to do here.

---

## 15. Distance-band fare schedule as built (2026-09-10)

Answers question 4 of section 14. Commit "Fare cards: distance-band fare schedule" on `fixed-route-wp8`.
**Seeded into production the same day** from the published Victoria / DeWitt rural table, so the pickup
screen's fare box and a card tap at pickup now price demand-response trips by distance.

**Model**: `fare_schedule_rows` (provider_id, service, up_to_miles, rider_category_id, fare). One row is one
cell of the published table. `up_to_miles` is the band's upper edge and NULL is "anything longer"; a trip
falls in the first band, in edge order, that its `drive_distance` (OSRM, miles) does not exceed. `service`
is `demand_response` today; `commuter` is allowed for later.

**Pricing** (`app/services/fare_schedule.rb`): the rider pays their category's fare for the band; each
guest pays the Adult fare for the same band; attendants ride free. Returns nil when the provider has no
rows or the trip has no distance, so the flat `fare_udr_default` still applies as the fallback.

**Where it is used**

- A card tap at pickup: amount precedence is now driver-typed, then the amount on the trip, then the
  schedule, then the flat default, then the rider's category fare.
- The itinerary JSON's `default_amount`, so the tablet's fare box prefills the scheduled amount for
  cash riders too.

**Office**: Providers -> General -> "Demand-response fare schedule", a grid with one row per band and one
column per rider category, add / remove bands, blank cells are $0.00. Saving replaces the table and is
paper-trailed. `rake fare_cards:seed_schedule PROVIDER_ID=1` loads the published table (FORCE=1 to
overwrite).

**Seeded table** (gcrpc.org rural fare schedule, DeWitt & Victoria, read 2026-09-10)

| Up to | Adult | Senior 60+ | Disabled | Youth 5-17 | Youth 0-5 |
|---|---|---|---|---|---|
| 5 mi | $1.00 | $0.50 | $0.50 | $0.75 | free |
| 10 mi | $2.00 | $1.00 | $1.00 | $1.75 | free |
| 15 mi | $3.00 | $1.50 | $1.50 | $2.50 | free |
| 20 mi | $4.00 | $2.00 | $2.00 | $2.50 | free |
| over | $5.00 | $2.50 | $2.50 | $3.00 | free |

**Paratransit (added the same day, answering question 3).** An ADA-eligible rider whose trip starts and
ends inside the urban service area pays a flat fare whatever the distance; each guest pays the same, as
ADA companions do; attendants ride free. Two provider settings on the same page: `fare_paratransit`
($1.50 in production) and `fare_urban_cities` ("Victoria"; comma separated; both trip addresses must have
one of these as their city, which is clean in the data: 771 of the last 90 days' pickups say Victoria).
There is no urban polygon in the system (`regions` is empty and `in_district` means the eight-county
area), so city names are the rule. `FareSchedule#trip_fare` checks paratransit before the distance
table, so the tap at pickup and the tablet's fare box both get $1.50.

**Office follow-up**: only **2** active riders carry the ADA eligible flag today. Paratransit riders must be
flagged on their customer record (Eligibility panel) or they will be charged the distance fare.

**Specs**: `spec/services/fare_schedule_spec.rb` (pricing, edges, guests, replace, tap precedence, grid
save, paratransit). 71 fare examples in all, green.

---

## 16. Pass sales as built (2026-09-10)

Answers the mechanics of question 6; the prices are still the team's call. Commit "Fare cards: sell
10-trip, 20-trip and monthly passes" on `fixed-route-wp8`. Live in production, with both prices at their
defaults (no discount, no monthly price, so the monthly button is hidden until one is set).

**10-ride and 20-ride** are stored value. The card is credited rides x the rider's category fare (a
senior's 10-ride is $5.00 of value; the tap takes $0.50 a ride). Each pass has its own provider discount;
the card still gets the full value and the office takes less cash; the ledger row records the cash
actually taken in a new `tendered` column, and the activity report's cash and check totals sum from it.
Refuses a rider whose category fare is $0.00.

**Prices adopted 2026-09-10** (Philz's prepay table, set on Victoria Transit): 10-ride 10% off, 20-ride
20% off, monthly $30.00. What each rider pays at the desk:

| Category (fare) | 10-ride, value / price | 20-ride, value / price | Monthly (unlimited) |
|---|---|---|---|
| Adult ($1.00) | $10.00 / **$9.00** | $20.00 / **$16.00** | $30.00 |
| Youth 5-17 ($0.75) | $7.50 / **$6.75** | $15.00 / **$12.00** | **$15.00** |
| Senior 60+, Disabled ($0.50) | $5.00 / **$4.50** | $10.00 / **$8.00** | **$15.00** |

The monthly is unlimited rides through the end of the month on both fixed route and demand response.
The reduced price (`fare_monthly_pass_price_reduced`, $15) applies to any category whose one-trip fare
is below Adult's, so it follows the fare sheet with no extra flag. Youth 0-5 ride free and get no
monthly button. Break-even: 30 rides for everyone.

**Monthly** is the expiry date on the customer. Selling one posts a load of the pass price and a `pass`
debit of the same amount in one transaction, so the money is on the ledger, the balance is unchanged, and
the report shows pass revenue in its own column. The form offers this month or next (defaulting to next
from the 24th); expiry is the last day of that month. Both the fixed-route tap and the pickup tap already
honour the expiry (free, still recorded).

**Office**: "Sell a pass" panel on the rider's fare account page with the three buttons priced for that
rider, paid by cash or check, reference, optional receipt (which shows the pass and, if discounted, what
was paid). Provider fare page: `fare_monthly_pass_price`, `fare_monthly_pass_price_reduced`, `fare_pass_10_discount_pct`, `fare_pass_20_discount_pct`.

**Specs**: pass sales in `spec/services/fare_ledger_spec.rb` and the buttons in
`spec/controllers/fare_accounts_controller_spec.rb`. 80 fare examples in all, green.

---

## 17. Policy as configured (2026-09-10)

One table of everything the transit team decided, where it is set, and where it is described. All of it is
live on Victoria Transit (provider 1) in production. Sources: gcrpc.org fare pages, the internal "Fare
Structure as of September 1st, 2026" sheet, Philz's prepay proposal, and the decisions in this session.

| Policy | Chosen | Where it is set | Section |
|---|---|---|---|
| **Fixed-route one-trip fares** | Under 5 free (with paying adult), Youth 5-17 $0.75, Adult 18-59 $1.00, Senior 60+ $0.50, Disabled $0.50 | Lookup Tables -> Rider categories (`default_fare`) | 5.1, 14 q1 |
| **Senior threshold** | 60+ on every service (the commuter page's 65+ is superseded) | rider category name | 14 q5 |
| **Rural / demand-response fares** | Distance bands x category from the published Victoria-DeWitt table: up to 5 mi $1.00 / $0.75 / $0.50; up to 10 mi $2.00 / $1.75 / $1.00; up to 15 mi $3.00 / $2.50 / $1.50; up to 20 mi $4.00 / $2.50 / $2.00; over $5.00 / $3.00 / $2.50 (Adult / Youth / Senior-Disabled), under 5 free | Providers -> General -> Demand-response fare schedule | 15 |
| **Guests and attendants** | Each guest pays the Adult fare for the band (paratransit: the same flat fare); attendants ride free | in the pricing rule | 15 |
| **ADA paratransit** | $1.50 flat when the rider is ADA eligible and both ends of the trip are in Victoria | Providers -> General -> Fare related settings: paratransit fare $1.50, urban cities "Victoria"; rider's ADA flag on the customer record | 15 |
| **Card fare at pickup, fallback order** | driver-typed amount, then amount on the trip, then paratransit rule, then distance table, then flat default ($0, unused), then category fare | code (`FareTap`, `FareSchedule`) | 13, 15 |
| **10-ride pass** | 10 rides of value at the rider's fare, 10% off: Adult $9.00, Youth $6.75, Senior/Disabled $4.50 | provider: 10-ride discount 10% | 16 |
| **20-ride pass** | 20 rides of value, 20% off: Adult $16.00, Youth $12.00, Senior/Disabled $8.00 | provider: 20-ride discount 20% | 16 |
| **Monthly pass** | Unlimited rides through month end, fixed route and demand response. $30.00 adult, $15.00 senior / disabled / youth | provider: monthly $30, reduced monthly $15 | 16 |
| **Transfers** | Free within 90 minutes of a paid tap, onto a different route only, one transfer per paid fare | provider: transfer window 90, different route only on | 5.1, 14 q2 |
| **Double tap** | A second tap on the same run within 2 minutes is ignored | code (`FareTap::DOUBLE_TAP_SECONDS`) | 5.1 |
| **Low balance** | May go as low as -$5.00; below that the tap is refused and cash is taken; settled at next reload | provider: lowest balance -5.00 (per-rider override on the account page) | 14 q9 |
| **Reload channels** | Front desk cash or check with receipt (live); online by card via Stripe pull (built, not configured) | office pages; `STRIPE_SECRET_KEY` | 6, 13 |
| **Tokens** | 13.56 MHz RFID card or printed QR sheet, both read by USB keyboard-wedge readers on the tablet's OTG cable; a printed serial works when the reader is down | Fare account page: issue / print QR | 2, 12 |
| **Services covered** | Victoria Transit fixed route; demand response in Victoria and DeWitt counties | one active provider | 14 q7 |
| **Tap to pay (bank card)** | Paused | none | 10 |

**Still to do, none of it software**: order the pilot readers and cards (section 12), install rideavl 1.0.9 on the
two pilot buses, flag ADA-eligible riders on their customer records (2 flagged today), and publish the fare page
text (section 18) on gcrpc.org.

---

## 18. Fare page draft for gcrpc.org (2026-09-10)

Answers question 10. Also kept on its own at `docs/fare-page-draft.md` for handing to whoever maintains the
website (which is a Next.js app, not WordPress; its source is not on 10.0.0.16). Replaces the current
Victoria Transit fare schedule page and its "available soon" pass note. Three deliberate choices: the office
address is a placeholder; the -$5.00 credit is not advertised (the "running low" paragraph says pay cash, and
the credit stays an office courtesy); transfers are described for the card only, since cash riders cannot
prove a paid trip without paper transfers.

### Fares effective September 1, 2026

#### Victoria Transit fixed route

| Rider | One trip |
|---|---|
| Under 5 (with a paying adult) | Free |
| Youth 5 to 17 | $0.75 |
| Adult 18 to 59 | $1.00 |
| Senior 60 and over | $0.50 |
| Riders with a disability | $0.50 |

Exact change, please. Drivers do not carry change.

#### ADA paratransit in Victoria

$1.50 per trip for ADA-eligible riders. One personal care attendant rides free. Companions pay the same fare.

#### Golden Crescent Transit rural service, Victoria and DeWitt counties

Fares are by trip distance and rider category.

| Trip distance | Youth 5 to 17 | Adult 18 to 59 | Senior 60+ / Disability |
|---|---|---|---|
| Up to 5 miles | $0.75 | $1.00 | $0.50 |
| 6 to 10 miles | $1.75 | $2.00 | $1.00 |
| 11 to 15 miles | $2.50 | $3.00 | $1.50 |
| 16 to 20 miles | $2.50 | $4.00 | $2.00 |
| Over 20 miles | $3.00 | $5.00 | $2.50 |

Children under 5 ride free with a paying adult. Guests pay the adult fare for the same distance. One
personal care attendant rides free with a rider with a disability.

Fares for Calhoun, Goliad, Gonzales, Jackson, Lavaca and Matagorda counties are set by those providers and
listed on the Golden Crescent Transit rural fare page. Gonzales County fares resume October 1, 2026.

---

### The Victoria Transit fare card

No more exact change. Load money on a card at the transit office, then tap the card on the reader as you
board. The fare comes off your balance and the driver's screen shows what is left.

**Getting a card.** Bring a photo ID to the transit office at [ADDRESS]. Tell us your rider category
(senior, disability, youth) and we will set it on the card so you always pay the right fare. Cards are free.
Lost your card? Tell us and we will block it and give you a new one. Your balance moves to the new card.

**Loading money.** At the transit office with cash or check. Any amount. You get a printed receipt with your
balance.

**Rides and passes.** Buy ten or twenty rides at once and save, or ride all you want for a month.

| | Adult | Youth 5 to 17 | Senior 60+ / Disability |
|---|---|---|---|
| Single ride | $1.00 | $0.75 | $0.50 |
| 10 rides, 10% off | $9.00 | $6.75 | $4.50 |
| 20 rides, 20% off | $16.00 | $12.00 | $8.00 |
| Monthly pass, unlimited rides | $30.00 | $15.00 | $15.00 |

The monthly pass is good through the last day of the month on every Victoria Transit bus and on rural
demand-response trips in Victoria and DeWitt counties.

**Transfers.** Changing buses to finish one trip is free. Tap your card on the second bus within 90 minutes
of paying on the first. The transfer is good for a different route only, once per paid fare. Riding the same
route back is a new fare.

**Using the card on demand-response and paratransit trips.** Tap the card when the driver picks you up. The
trip fare comes off your balance.

**Checking your balance.** The driver's screen shows it every time you tap, and it is on every receipt. Or
call the office.

**Running low.** If your balance cannot cover a fare, the driver will tell you. You can pay cash for that ride
and reload at the office.

---

Questions: 361-578-8775, Monday to Friday, 8:00 a.m. to 5:00 p.m.
