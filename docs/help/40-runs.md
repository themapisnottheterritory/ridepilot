# Runs: buses, drivers, hours

**Where**: **Runs** in the top menu lists runs by date (use the filters on the left, e.g. Service mode = Demand response, and the dates). Click View on a run to open it. The list can take a few seconds to load.

**Subscription runs**: the weekday runs are created automatically from **Subscription Run** templates (**View Subscription Run Templates** on the Runs page). Changing a template affects runs RidePilot creates from then on; runs already created for the coming weeks keep their old settings, so change those days one by one or ask GCRPC I.T. to update them all.

**Demand-response runs**: Monday-Friday, 8:00 AM - 5:00 PM.
- Victoria Transit: UDR1-10, RVIC1-3, RGON1-3, DeWitt1-3, RCAL1-3, MATA1-3, JACK1-3.
- Goliad County Rural Transit: Rgol1 (bus R8), Rgol2 (GOL 14), Rgol3 (GOL 15), Rgol4 (GOL 16), Rgol5 (GOL 18).
- Lavaca County Transit: Hville1 (LAV 38), Hville2 (LAV 45), Hville3 (LAV 47), Hville4 (LAV 49), Yoakum1 (LAV 52), Yoakum2 (LAV 53), Gonzales1 (LAV 54).
The bus listed is the anticipated vehicle; change it on the run when fleet assigns a different one.

**Bus and driver**: open the run, click **Edit**, choose the vehicle and the driver, save. A run needs both before trips can be assigned and before the manifest can be published. The run's start and end location comes from the bus's home garage automatically.

**Driver not available**: if RidePilot says the driver is unavailable, check the driver's availability hours (Drivers page, the driver's Recurring Availability) cover the run's hours.

**Don't make a run per rider**: a run is a bus's day, not one person's ride. Put a regular rider's trips on the day's run (a Subscription Trip for standing rides), rather than creating a run named after the rider.
