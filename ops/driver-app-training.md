# RideAVL Driver Tablet — Training Guide

*The complete driver workflow, verified end-to-end on the pilot tablet 2026-08-05. Every step below was confirmed landing on the RidePilot server.*

---

## Before the shift
- The tablet's **WireGuard tunnel** must be **ON** (it auto-connects). Everything else on the tablet (Play Store, browser, etc.) works normally — only RidePilot rides the tunnel.
- Open **RideAVL** and **sign in** with your username + password.

## 1. Pick your run
- The **Runs** list shows the runs assigned to you for **today**. A fixed route shows its colour and name (e.g. **Fixed route · Red**).
- Tap your run to open it.

## 2. Start the run  (records your starting odometer + does the pre-trip inspection)
- **Start Odometer** — type the vehicle's current odometer reading.
- **Full Vehicle Inspection (DVIR)** — tap it to do the **pre-trip inspection**:
  - For each item, tap **OK**, **Defect**, or **N/A**.
  - If **Defect**: add a note, and a **photo** if useful.
  - Enter odometer / lift / gallons as prompted, then **sign** and **Submit**.
  - *Any item marked **Defect** automatically opens a maintenance ticket for the shop.*
- Tap **Start Run**. You'll land on the **Manifest**.

> The inspection you see (which items, and whether they're pre-trip/post-trip) is configured by the office — drivers don't manage the list.

## 3. Work the manifest  (one stop at a time)
The **Manifest** lists every stop in order — pickups and dropoffs. Tap a stop to open it.

**On each stop you'll see:**
- A **map** with your live location (blue dot) and the **route** to the stop, plus the address and rider info.
- **Navigate** — opens turn-by-turn (external maps) if you want it; the in-app map already shows the route.

**Then work the stop with the buttons at the bottom, in order:**

| Stop type | Button sequence |
|---|---|
| **Pickup** | **Depart** → **Arrive** → **Pick Up**  *(or **No Show** if the rider isn't there)* |
| **Dropoff** | **Depart** → **Arrive** → **Drop Off** |

- **Depart** — you've left for the stop.
- **Arrive** — you're at the location (this reveals Pick Up / Drop Off / No Show).
- **Pick Up** / **Drop Off** — the rider is on board / delivered. **This is how you acknowledge the trip.**
- **No Show** (pickups only) — the rider didn't show.
- **Undo** — backs out your last action if you tapped the wrong one.

Each tap saves to the office immediately and advances the stop; when done it shows **Completed**. Move to the next stop and repeat.

## 3b. Fixed route  (Red, Gold, Green, Pink, Purple, Blue, and the Inteplast commuters)
On a fixed route you don't get a manifest. After the pre-trip you land on the **route screen**: the route name and your unit at the top, **Boarded today / Alighted** counts, one big **Walk-on** button, and your recent walk-ons below.

**Confirm your unit first.** Before the pre-trip the tablet shows the unit dispatch assigned you. If you're in a different bus, tap **Different unit** and pick the one you're actually in — dispatch is told automatically.

**At every stop, once the bus is stopped:**
1. Tap **Walk-on**. (It's greyed out while the bus is moving — that's on purpose. Never touch the tablet while driving.)
2. The **nearest stop** is already selected. If it's wrong, tap the right one (switch direction at the top if needed).
3. Tap **+** next to each rider type that boarded — Adult, Senior, Student… — once per rider.
4. Pick the **fare type** if it isn't already right.
5. Under **Dropped off**, tap **+** once per person who got off.
6. Tap **Save**. One tap — no confirmation screen. The counts at the top update.

Nobody boarded and nobody got off? Don't log anything.

**Made a mistake?** Find the walk-on under **Recent** and tap the **undo arrow**. It's gone, and dispatch sees that it was undone.

**No signal?** Keep logging. Walk-ons show as **queued** and send themselves when the tunnel is back — you'll see a small number in the top bar until they do. They can never double-count.

End the day as usual: **post-trip inspection**, then **End Run** with the ending odometer.

## 4. End the run
- After the last stop, **End Run**: enter the **End Odometer** and do the **post-trip inspection** (same as pre-trip).

---

## If something looks wrong
- **Map is gray / no map** — make sure you're on the current app version and the tunnel is on. Tiles are served from RidePilot (self-hosted), so no internet/Google is needed.
- **"My location" does nothing** — allow the **location permission** when the app asks (or Settings → Apps → RideAVL → Permissions → Location → Allow).
- **Navigate opens a maps app with no map** — that's the external maps app needing internet; the **in-app map + route** works without it.
- **Wrong button** — use **Undo**.

## Verified on the pilot tablet (2026-08-05 / 06)
- Pre-trip DVIR inspection submitted (report saved, odometer captured).
- Start Run recorded.
- All manifest stops walked Depart → Arrive → Pick Up / Drop Off; every action saved (HTTP 200) and each stop marked Completed; trips marked completed.
- Live location + self-hosted route line rendered on each stop's map.
- **Defect → maintenance verified:** marking items **Defect** created a **maintenance ticket per defect** automatically (with the item name + odometer), and the **defect photos (~2 MB each) attached** to the report.
