# The Route Optimizer

**What it does**: works out the best order of pickups and drop-offs for one demand-response run, including shared rides, and rewrites that run's manifest in that order.

**How to use it**:
1. Put the day's trips on the run (Dispatch page) and make sure the run has its bus.
2. Open the run (Runs, then View; or the arrow box on its Dispatch panel) and click **Optimize Route** at the top. The button appears once the run has at least 2 trips.
3. Confirm. A progress bar shows while it works (about 15 seconds).
4. Read the message at the top of the run page, check the stop order, then publish the manifest.

**What it respects**: pickup within 5 minutes before to 10 minutes after the booked time; drop-off by the appointment time; nobody on board too long (the longer of 1.5 times the direct trip or the direct trip plus 20 minutes); 2 minutes of boarding per stop; the bus's seats and wheelchair spaces; the run's hours.

**The messages**:
- "Route optimized: 4 trips, 8 stops, about 16 mi and 36 min of driving": done; stops reordered and estimated pickup times updated.
- "Not changed: [riders] can't be served on this run...": those trips don't fit the rules above, so nothing changed. Move them to another run or change their times, then optimize again.
- "This run has started...": it never changes a run the driver has started.

**Limits**: one run at a time (it doesn't move trips between runs). Times are estimates; traffic and slow boardings change the real day. It does not text riders.
