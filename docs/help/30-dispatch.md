# The Dispatch page: putting trips on runs

Click **Dispatch** in the top menu and pick the day.

- **Runs** panel: the day's runs. Click a run to open its panel with its manifest (stops in order).
- **Trips** panel: trips for the day that are not on a run yet (Unscheduled; you can also view Standby and Cab).

**Put a trip on a run**: drag the trip from the Trips panel onto the run's panel, or use the trip's **Assign to** menu and choose the run. A run needs a bus and a driver before trips can go on it (RidePilot says "no vehicle assigned" otherwise).

**Run panel icons** (top right of each run's panel):
- red cloud: **Publish Manifest**. Shown when the stop list changed. Click it so the driver's tablet gets the new list.
- clock: recalculate arrival times (ETA).
- power: cancel the run.
- pencil: edit the run (bus, driver, times).
- **+**: book a new trip straight onto this run.
- arrow box: open the run's full page.

**Take a trip off a run**: use the run panel's unschedule menu and choose Unscheduled, Standby or Cab.

**Before the day starts**: every run in use has a bus and a driver, every trip that should go is on a run, and each run's manifest is published (no red cloud left).

**"Trip schedule does not fit in run schedule"**: the trip's pickup time is before the run starts or after it ends (demand-response runs are 8:00 AM - 5:00 PM Monday-Friday). Put it on a run whose hours cover it, or change the trip time. A 7:30 AM pickup cannot go on an 8:00 run.

**Messages from drivers (the chat bubbles in the header)**: when a driver sends a message from the tablet, every dispatcher of that agency gets a pop-up in the bottom-left corner with a soft chime, on any RidePilot page and on CAD/AVL. Press **Reply** to open the chat with that driver, or **Dismiss** to close the pop-up. The chat-bubbles icon at the top of the page shows how many driver messages nobody has looked at yet; click it for today's list. As soon as any dispatcher opens or answers a driver's chat, that driver's messages count as seen for everyone and show "Seen by <name> <time>", so two people don't both call the driver. In the list, **Sound** turns the chime off or on for you, and **Turn on desktop alerts** lets the computer pop up a notice when RidePilot isn't the window in front (the tab title also flashes). Emergency alerts sound even when the chime is off.

**Emergency alerts**: a red bar across the top of every page with an alarm, until someone presses **Got it!**; the driver's tablet then shows who received it. An alert nobody has answered comes back on every page you open, so it can't be missed.

**Will call ready**: when a will-call rider phones to say they're ready, find their pickup on the run in **Dispatch** and press **Ready** next to the **Will call** label. The driver's tablet shows the rider's name, pickup address and phone, with a **Go to stop** button; the button in Dispatch changes to **Ready** and the time it was sent. The trip has to be on a run with a driver.

**No-shows**: drivers mark a no-show themselves on the tablet (no approval needed). Dispatch gets a driver-message pop-up, "No-show: <rider> at <address>", so you know.

**Has the driver seen my message?** In a driver's chat window, a green **Seen by the driver <time>** line appears once they've opened chat or pressed OK on the message (Demand Response tablets on version 1.0.21 or later).
