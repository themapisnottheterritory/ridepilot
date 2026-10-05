# Booking a trip

1. Click **Trips** in the top menu, then **New Trip** (or use **+** on a run's panel on the Dispatch page to book straight onto that run).
2. Pick the customer by typing their name.
3. **Trip Essentials**: set the **Pickup Time**, the **Appointment Time** if the rider must arrive by a certain time, the pickup address and the drop-off address. Choose saved addresses where you can.
4. Add mobility needs, guests and attendants (PCA) if any, and notes for the driver.
5. Save. RidePilot asks "Would you like to create a return trip?" Say yes for a round trip, or use **Create Return** on the trip page later.

**Fare to quote**: the trip form and trip page show a "Fare to quote" panel with the amount to tell a rider who pays cash, based on trip distance and the rider's fare category. If it says the Adult fare was assumed, set the customer's Fare category (see Customers). See the Fares guide for the table.

**Copy a trip**: open an existing trip and click **Clone** to book the same ride on another day.

**AM or PM**: times are entered with AM/PM; 12:00 AM is midnight and 12:00 PM is noon. If a pickup or appointment time is between 12:00 AM and 4:59 AM, RidePilot asks "Did you mean PM?" before saving: choose **Change it** to fix the time, or keep it if the early time is right.

**Standing trips** (same ride on set days, e.g. dialysis): use **Create New Subscription Trip** (Trips page, or **View Subscription Trip Templates** to see existing ones). Fill in the customer and **Trip Essentials** as for a normal trip, then in the **Repetitions** panel set the **Start Date**, an optional **Stop Date**, tick the **Days of Week** (e.g. Tuesday and Thursday), and set **Repeat every** 1 **Weeks** (2 for every other week). Save. RidePilot generates the daily trips ahead of time. A single trip can't be turned into a subscription; create the Subscription Trip, and cancel any one-off trips it duplicates. **Changing a subscription's days**: untick a day and save, and RidePilot removes the trips it had already made for that day (only future ones that have no result yet) and lists them in the message at the top of the page. Ticking a new day adds its trips. Changing the subscription's time or addresses only affects trips it makes from then on: trips already made for the coming weeks keep the old details, so change those one by one.

**Changing a trip after it happened**: use the trip's Result (for example **Mark as no-show**, cancelled, turned down). RidePilot may ask for a comment explaining the change.

## Will-call trips

A will-call trip is one where the rider will call when they're ready, usually the ride home from an appointment. On the trip form, tick **Will call** (under the appointment time) and enter your best estimate for the pickup time. The trip shows a **Will call** label on the Trips list, the Dispatch trips list and the run manifest, and the driver's tablet shows "WILL CALL: the rider calls when ready" at the top of that pickup's notes. When the rider calls, open the trip, set the real pickup time, untick **Will call**, and save. Subscription trips have the same checkbox, and the trips they create carry it.


**Saved places and "Not on map"**: a saved place only comes up when booking if it has a map pin. Picking the address from the suggestions as you type gives it one. If you type an address the suggestions don't know (a rural house number, for example), RidePilot asks the US Census address lookup when you save, and if that finds the exact address it pins it there and says so: check the pin on the map. Places named like a home, or by their street address alone, aren't looked up. Anything still marked **Not on map** on the Addresses page needs editing (pick the address from the suggestions), or ask GCRPC I.T. to place it. Each morning RidePilot tries the Census lookup again for saved places still without a pin and tells GCRPC I.T. what it placed.
