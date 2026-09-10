# Fare Card Design Recommendation

Written 2026-09-10 for RidePilot at GCRPC / Victoria Transit. Updated same day after reviewing tap to pay.
Status: proposal, nothing built yet.
Budget assumption: near zero. Existing driver tablets, existing RidePilot server, cheap off-the-shelf parts.
Fare today: $1.50, and the goal is to bring it down, not up.

**Decisions so far**

- Account-based ledger in RidePilot, token-agnostic (section 4). This is the part every option shares.
- **Frequency: 13.56 MHz, decided 2026-09-10.** Philz and Andrew both concur (section 2.2). MIFARE / NTAG cards,
  the ESP32 + RC522 prototype, and 13.56 MHz USB HID readers. The 125 kHz EH301 and its EM4100 cards are out.
- Pilot two tokens on the same backend: RFID card on one bus, QR code on another (section 8).
- **Phase 1 built 2026-09-10** (section 11): migration, ledger, office pages, activity report.
- Tap to pay (bank card / phone wallet) explored and **paused** (section 10). Percentage fees do not fit a $1.50 fare.
- Connectivity is not the constraint. Every bus has a Pepwave MAX BR1 LTE router and the tablets have their own LTE.
  Offline is a fallback path, not the design center.

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
3. Transfer check: a debit for this customer inside `transfer_window_minutes` -> fare 0, still record
   the boarding.
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
| 2 | Fixed-route tap endpoint plus tablet capture on the walk-on screen. **Pilot two tokens on the same backend: RFID reader on one bus, QR via the tablet camera on another.** Offline queue as fallback. Watch which one riders and drivers reach for. | Bus side, token choice |
| 3 | UDR pickup tap, mismatch confirm, guest rule. | Demand response |
| 4 | Stripe pull job for online loads. Lobby balance-check station. ESP32 rider-facing validator if wanted. | Nice to have |

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
