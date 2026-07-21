# RidePilot User Guide

**Greater Victoria Regional Transit — Paratransit Scheduling System**

---

## Table of Contents

1. [Getting Started](#1-getting-started)
2. [For Call Center Reps: Managing Trips](#2-for-call-center-reps-managing-trips)
3. [For Dispatchers: Scheduling & Dispatch](#3-for-dispatchers-scheduling--dispatch)
4. [For Dispatchers: Route Optimization](#4-for-dispatchers-route-optimization)
5. [For Administrators: Provider Settings](#5-for-administrators-provider-settings)
6. [For Administrators: AVL / GPS Tracking](#6-for-administrators-avl--gps-tracking)
7. [For Customers: Client Portal & SMS](#7-for-customers-client-portal--sms)
8. [Appendix: Keyboard Shortcuts & Tips](#appendix-keyboard-shortcuts--tips)

---

## 1. Getting Started

### Logging In

Navigate to your RidePilot URL in a web browser. You will see the login screen.

> ![Screenshot: Login page with email and password fields](screenshots/login.png)
>
> *The RidePilot login screen. Enter your email and password, then click "Sign In".*

After logging in, you will land on the **dashboard** for your provider. The left sidebar contains navigation links that vary based on your role:

| Role | Sections Available |
|------|-------------------|
| Call Center Rep | Trips, Customers, Reports |
| Dispatcher | Trips, Customers, Runs, Dispatch, Reports |
| Administrator | All of the above + Providers, Users, Vehicles, Drivers, Settings |

> ![Screenshot: Dashboard/home page showing sidebar navigation](screenshots/dashboard.png)
>
> *The main dashboard. Your available sections appear in the left sidebar.*

---

## 2. For Call Center Reps: Managing Trips

### 2.1 Creating a New Trip

From the sidebar, click **Trips** then **New Trip**.

```
┌─────────────────────────────────────────────────────┐
│  NEW TRIP FORM                                      │
│                                                     │
│  ┌─ Customer ─────────────────────────────────────┐ │
│  │  Customer Name: [autocomplete field______]     │ │
│  │  Phone: (auto-filled)  Mobility: (auto-filled) │ │
│  └────────────────────────────────────────────────┘ │
│                                                     │
│  ┌─ Trip Details ─────────────────────────────────┐ │
│  │  Date:        [__/__/____]                     │ │
│  │  Pickup Time: [HH] : [MM] [AM/PM]             │ │
│  │  Appt. Time:  [HH] : [MM] [AM/PM] (optional)  │ │
│  │  Pickup:      [address autocomplete_______]    │ │
│  │  Dropoff:     [address autocomplete_______]    │ │
│  │  Trip Purpose:[dropdown______________]         │ │
│  └────────────────────────────────────────────────┘ │
│                                                     │
│              [ Save ]    [ Cancel ]                  │
└─────────────────────────────────────────────────────┘
```

**Step-by-step:**

1. **Select a Customer** — Start typing the customer's name. The autocomplete will search active customers. Once selected, their phone number, mobility needs, funding source, and default addresses are auto-populated.

> ![Screenshot: Customer autocomplete dropdown showing matching names](screenshots/trip-customer-autocomplete.png)
>
> *As you type, matching customers appear. Click to select.*

2. **Set the Date** — Click the date field and pick from the calendar. (This field does not appear for repeating trips.)

3. **Set Pickup Time** — Use the hour, minute, and AM/PM dropdowns. This is the time the customer wants to be picked up.

4. **Set Appointment Time** (optional) — If the customer has an appointment at the destination, enter it here. The system uses this to calculate the latest acceptable pickup time.

5. **Enter Pickup Address** — Start typing an address. Two types of suggestions appear:

   - **Saved Addresses** — Previously used addresses for this customer (shown first)
   - **Nominatim Suggestions** — New addresses looked up from the map database

   Select a suggestion to auto-fill the latitude/longitude.

> ![Screenshot: Address picker showing saved addresses and Nominatim suggestions in two sections](screenshots/trip-address-picker.png)
>
> *The address picker shows saved addresses first, then Nominatim search results below.*

   **Tip:** If you need to enter a location that doesn't have a street address (e.g., a park entrance), click the **Lat/Lon** checkbox to switch to manual coordinate entry.

6. **Enter Dropoff Address** — Same process as pickup.

7. **Select Trip Purpose** — Choose from the dropdown (e.g., Medical, Shopping, Work).

8. **Click Save** — The trip is created and ready for scheduling.

### 2.2 Additional Trip Options

After the basic details, you can expand additional panels:

#### Mobility Panel
Shows the customer's mobility accommodations (wheelchair, scooter, walker, etc.). These are inherited from the customer profile but can be adjusted per trip.

> ![Screenshot: Mobility panel with checkboxes for accommodation types](screenshots/trip-mobility.png)

#### Fare Panel
Set how the trip is paid for:
- **Free** — No charge
- **Donation** — Enter donation amount
- **Payment** — Enter fare amount

> ![Screenshot: Fare panel showing fare type dropdown and conditional amount field](screenshots/trip-fare.png)

#### ETA Settings Panel
Fine-tune timing parameters:
- **Passenger Load Time** (minutes) — How long to board the passenger
- **Passenger Unload Time** (minutes) — How long to deboard
- **Early Pickup Allowed** — Check this if the customer is OK being picked up early

> ![Screenshot: ETA settings panel with load/unload times and early pickup checkbox](screenshots/trip-eta-settings.png)

#### Notes Panel
- **Pickup Address Notes** — Special instructions for the driver at pickup (max 30 characters, e.g., "Side door entrance")
- **Dropoff Address Notes** — Instructions at dropoff
- **Trip Notes** — General notes visible to dispatchers

### 2.3 Viewing and Editing Trips

From the **Trips** list, click any trip to view it. In view mode, you'll see action buttons at the top:

| Button | What it does |
|--------|-------------|
| **Edit** | Opens the trip for editing |
| **Delete** | Removes the trip (with confirmation) |
| **Clone Trip** | Creates a copy with the same details for a new date |
| **Create Return Trip** | Creates an opposite-direction trip (swaps pickup/dropoff) |

> ![Screenshot: Trip view page showing action buttons at top](screenshots/trip-view-actions.png)
>
> *The trip detail view. Use "Clone Trip" to quickly book recurring rides, or "Create Return Trip" for round trips.*

### 2.4 Trip Results

Once a trip has been completed (or not), set the **Trip Result**:

- **Completed** — Passenger was picked up and dropped off
- **No-Show** — Passenger was not at pickup location
- **Cancelled** — Trip was cancelled (you'll be prompted for a reason)
- **Turned Down** — Agency could not accommodate the trip

> ![Screenshot: Trip result dropdown with result options](screenshots/trip-result.png)

---

## 3. For Dispatchers: Scheduling & Dispatch

### 3.1 The Dispatch Screen

The dispatch screen is your command center. Click **Dispatch** in the sidebar.

```
┌──────────────────────────────────────────────────────────────────────┐
│  Date: [03/16/2026]                                                  │
├────────────────────────────────────┬─────────────────────────────────┤
│         RUNS PANEL (80%)           │    UNASSIGNED TRIPS (20%)       │
│                                    │                                 │
│  ┌─ Run: Morning Route A ────────┐ │  ┌─ Unscheduled ─────────────┐ │
│  │  Driver: John  Vehicle: #1745 │ │  │  Smith, J  9:00 AM        │ │
│  │  ┌──────────────────────────┐ │ │  │  123 Main → 456 Oak       │ │
│  │  │ PU Adams, M    8:30  ETA│ │ │  │                            │ │
│  │  │ DO Adams, M    8:45  ETA│ │ │  │  Jones, R  10:15 AM       │ │
│  │  │ PU Baker, S    9:00  ETA│ │ │  │  789 Pine → 321 Elm       │ │
│  │  │ DO Baker, S    9:20  ETA│ │ │  │                            │ │
│  │  └──────────────────────────┘ │ │  │  (drag trips to a run →)  │ │
│  │  [Optimize] [Publish] [ETA]   │ │  │                            │ │
│  └───────────────────────────────┘ │  └────────────────────────────┘ │
│                                    │                                 │
│  ┌─ Run: Afternoon Route B ──────┐ │  Type: [Unscheduled ▼]        │
│  │  ...                          │ │  [Assign to ▼] [+ New Trip]   │
│  └───────────────────────────────┘ │                                 │
└────────────────────────────────────┴─────────────────────────────────┘
```

> ![Screenshot: Full dispatch screen showing runs on left and unassigned trips on right](screenshots/dispatch-overview.png)
>
> *The dispatch screen. Runs are on the left (80% of screen), unassigned trips on the right (20%). The divider is draggable.*

### 3.2 Assigning Trips to Runs

**Drag and drop** is the primary way to schedule trips:

1. Find the trip in the **Unassigned Trips** panel on the right
2. Click and drag it to the desired run on the left
3. Drop it into the run's manifest table
4. The trip is now scheduled on that run

> ![Screenshot: A trip being dragged from unassigned panel to a run manifest](screenshots/dispatch-drag-assign.png)
>
> *Drag a trip from the unassigned panel and drop it onto a run to schedule it.*

**To unschedule a trip:** Drag it from the run manifest back to the unassigned panel, or select trips with checkboxes and click **"Unschedule Selected"**.

### 3.3 Reordering the Manifest

Within a run, you can **drag trips up and down** to change the stop order. The system enforces that every pickup must come before its corresponding dropoff — if you try to place a dropoff before its pickup, the move will be rejected.

> ![Screenshot: Manifest table with drag handles on rows](screenshots/dispatch-reorder.png)
>
> *Drag rows within the manifest to reorder stops. Pickups must always come before their dropoffs.*

### 3.4 The Run Manifest Table

Each run shows a detailed manifest with these columns:

| Column | Description |
|--------|-------------|
| **Action** | PU (pickup) or DO (dropoff), plus badges: "New", "Recur", "Mobility?" |
| **Customer** | Passenger name |
| **Address** | Stop address |
| **Scheduled** | Originally scheduled time |
| **ETA** | Estimated time of arrival (live-updated) |
| **Capacity** | Seat and wheelchair space usage |
| **Comments** | Trip notes |
| **Result** | Trip completion status |
| **Phone** | Customer phone number (clickable) |
| **Driver Notified** | Checkbox — did the driver acknowledge this trip? |

> ![Screenshot: Run manifest table showing all columns with sample data](screenshots/dispatch-manifest-table.png)

### 3.5 Run Action Buttons

At the top of each run panel, you'll find these action buttons:

| Button | What it does |
|--------|-------------|
| **Publish Manifest** | Sends the current manifest to the driver (appears red when there are unpublished changes) |
| **Recalculate ETA** | Refreshes estimated arrival times for all stops |
| **Optimize Route** | Runs the route optimizer to suggest the best stop order (see [Section 4](#4-for-dispatchers-route-optimization)) |
| **Cancel Run** | Cancels the entire run (with warning about affected trips) |
| **Edit Run** | Opens run settings (driver, vehicle, times) |
| **+ New Trip** | Creates a new trip pre-assigned to this run |

> ![Screenshot: Run panel header showing action buttons](screenshots/dispatch-run-buttons.png)
>
> *Run action buttons. The red "Publish" icon appears when the manifest has changed since last publish.*

### 3.6 Batch Operations

Select multiple trips using checkboxes, then use the dropdown menus:

- **"Set trips as..."** — Bulk-change trip results (e.g., mark multiple as No-Show)
- **"Unschedule Selected"** — Remove selected trips from the run
- **"Assign to..."** — Move selected trips to another run or status

> ![Screenshot: Multiple trips selected with checkboxes, batch action dropdown visible](screenshots/dispatch-batch-actions.png)

### 3.7 Real-Time ETA Updates

If your provider has AVL/GPS tracking enabled, ETAs update automatically in the dispatch view. You'll see the ETA column refresh as vehicles move. This is powered by WebSocket connections — no need to refresh the page.

A **"New"** badge appears on trips that have been added or changed since the driver last received the manifest.

### 3.8 Creating and Editing Runs

Click **"Create New Run"** at the top of the runs panel, or go to **Runs → New Run** in the sidebar.

```
┌─────────────────────────────────────────────────────┐
│  NEW RUN                                            │
│                                                     │
│  ┌─ Date & Time ──────────────────────────────────┐ │
│  │  Date:           [__/__/____]                  │ │
│  │  Scheduled Start: [HH] : [MM] [AM/PM]         │ │
│  │  Scheduled End:   [HH] : [MM] [AM/PM]         │ │
│  └────────────────────────────────────────────────┘ │
│                                                     │
│  ┌─ Driver ───────────────────────────────────────┐ │
│  │  Driver: [dropdown____________]                │ │
│  └────────────────────────────────────────────────┘ │
│                                                     │
│  ┌─ Vehicle ──────────────────────────────────────┐ │
│  │  Vehicle: [dropdown____________]               │ │
│  └────────────────────────────────────────────────┘ │
│                                                     │
│              [ Save ]    [ Cancel ]                  │
└─────────────────────────────────────────────────────┘
```

> ![Screenshot: New run form with date, time, driver, and vehicle fields](screenshots/run-new-form.png)
>
> *Create a new run by setting the date, time window, driver, and vehicle.*

**Notes:**
- Changing the date will reload the available drivers and vehicles for that day
- Changing the time will also refresh driver availability
- If you change the date on an existing run, **all trips will be unscheduled** (you'll see a warning)

### 3.9 Completing a Run

When a run is finished for the day:

1. Open the run (click run name or **Edit**)
2. Fill in completion fields:
   - **Start Odometer** reading
   - **End Odometer** reading
   - **Actual Start/End Times**
   - **Unpaid Driver Break Time** (if applicable)
   - **Paid** status (Yes/No)
3. Click **"Complete"**

> ![Screenshot: Run completion panel with odometer and time fields](screenshots/run-complete.png)
>
> *Fill in the actual odometer readings and times before marking the run complete.*

The **"Complete"** button is disabled if:
- Any trips on the run have no result set
- Required fields (configured by admin) are empty

If a run was completed by mistake, click **"Set as Incomplete"** to reopen it.

---

## 4. For Dispatchers: Route Optimization

RidePilot includes an automatic route optimizer that reorders stops on a run to minimize drive time while respecting all constraints (time windows, vehicle capacity, pickup-before-dropoff, maximum ride times).

### 4.1 Optimizing a Single Run

1. Open a run that has **2 or more trips** assigned
2. Click the **"Optimize Route"** button

> ![Screenshot: Run detail view with "Optimize Route" button highlighted](screenshots/optimize-button.png)
>
> *The "Optimize Route" button appears on runs with 2+ trips.*

3. Confirm the dialog: *"Optimize trip order for this run?"*
4. The optimization runs in the background (typically takes 1–5 seconds for a 10–30 stop run)
5. The manifest updates with the new stop order and refreshed ETAs

```
  BEFORE OPTIMIZATION              AFTER OPTIMIZATION
  ──────────────────              ───────────────────
  PU Adams     8:30               PU Baker     8:25
  DO Adams     8:50               PU Adams     8:35
  PU Baker     9:00               DO Adams     8:50
  DO Baker     9:25               DO Baker     9:00
  PU Clark     9:15               PU Clark     9:05
  DO Clark     9:45               DO Clark     9:30

  Total drive: 48 min             Total drive: 35 min
                                  Saved: 13 min ✓
```

### 4.2 What the Optimizer Considers

The optimizer respects all of these constraints automatically:

| Constraint | What it means |
|-----------|---------------|
| **Pickup before dropoff** | Every passenger must be picked up before being dropped off |
| **Pickup time window** | Pickup must be within the scheduled time ± allowed slack |
| **Appointment time** | Dropoff must happen before the customer's appointment |
| **Run start/end times** | All stops must fall within the run's scheduled window |
| **Seat capacity** | Never exceeds the vehicle's seating capacity |
| **Wheelchair capacity** | Never exceeds the vehicle's mobility device spaces |
| **Passenger load/unload time** | Accounts for boarding and deboarding time at each stop |
| **Maximum ride time** | No passenger rides longer than the provider's max ride time setting |
| **Garage start/end** | Route starts and ends at the vehicle's garage address |

### 4.3 Overnight Batch Optimization

Each night, the system automatically optimizes all runs for the next day:

1. **Individual run optimization** — Each run with 2+ trips is optimized
2. **Fleet-wide optimization** — Trips may be reassigned between runs for overall efficiency
3. **ETA notifications** — Customers with SMS enabled receive their estimated pickup time window

This runs automatically — no dispatcher action needed. You'll see the optimized manifests when you log in the next morning.

### 4.4 Real-Time Re-optimization

As a run progresses during the day, the system re-optimizes remaining stops when:
- A trip is completed (pickup or dropoff)
- A trip is cancelled or no-showed
- The driver's actual position is significantly different from planned

Updated ETAs are pushed live to the dispatch screen and customer portal via WebSocket — no page refresh needed.

### 4.5 SMS Notifications After Optimization

If an optimization changes a customer's estimated pickup time by more than 5 minutes, the system automatically sends an SMS notification:

> *"Your pickup time has been updated to 9:15 AM. Please be ready 10 minutes early. Call [provider phone] with questions."*

This only applies to customers with SMS notifications enabled and a valid phone number on file.

---

## 5. For Administrators: Provider Settings

### 5.1 Accessing Provider Settings

Go to **Providers** in the sidebar, then click your provider name, then the **General** tab.

> ![Screenshot: Provider settings page showing the General tab](screenshots/provider-settings-general.png)

### 5.2 Operating Hours

Set your provider's daily operating hours. These determine when runs can be scheduled.

> ![Screenshot: Operating hours form with day-by-day time selectors](screenshots/provider-operating-hours.png)

### 5.3 Advance Day Scheduling

Choose how far in advance trips can be scheduled:
- **7 days**
- **14 days**
- **21 days**

> ![Screenshot: Advance day scheduling dropdown](screenshots/provider-advance-days.png)

### 5.4 Run Tracking

Enable or disable GPS-based run tracking. When enabled, the system records vehicle positions and calculates ETAs.

### 5.5 Required Fields for Run Completion

Check which fields dispatchers/drivers **must** fill in before a run can be marked complete:

- Start Odometer
- End Odometer
- Unpaid Driver Break Time
- Paid status

> ![Screenshot: Checkboxes for required run completion fields](screenshots/provider-required-fields.png)

### 5.6 Region Boundaries

Define your service area by setting the northwest and southeast corners of a bounding box. This is used to:
- Filter address search results to your area
- Display the correct region on maps

```
  NW Corner ●─────────────────────●
             │                     │
             │   YOUR SERVICE      │
             │      AREA           │
             │                     │
             ●─────────────────────● SE Corner
```

Enter coordinates or click on the Leaflet map preview to set the corners.

> ![Screenshot: Region boundaries form with lat/lon fields and map preview](screenshots/provider-region-boundaries.png)
>
> *Set your service area boundaries. The map preview updates as you enter coordinates.*

### 5.7 Max Ride Time

Set the maximum time (in minutes) any passenger should be on the vehicle. The route optimizer uses this as a constraint — it will not create routes where a passenger rides longer than this limit.

---

## 6. For Administrators: AVL / GPS Tracking

### 6.1 Overview

RidePilot supports two GPS data sources:

| Source | How it works |
|--------|-------------|
| **Tablet GPS** (default) | Driver tablets report GPS via the RidePilot CAD app |
| **Pepwave AVL** | Pepwave routers in vehicles report GPS via the OpenTransit system |

You can switch between them per provider. Both feed into the same GPS pipeline — all existing features (live maps, ETAs, breadcrumb trails, distance calculations) work identically regardless of source.

### 6.2 Configuring AVL

Navigate to **Providers → General** and scroll to the **"AVL / GPS Source"** section.

> ![Screenshot: AVL/GPS Source settings section with toggles and fields](screenshots/avl-settings.png)
>
> *The AVL configuration section. Toggle between tablet GPS and external AVL.*

**Step-by-step:**

1. **Use External AVL** — Select "Yes (Pepwave AVL)" to switch from tablet GPS to Pepwave

2. **AVL Data Source** — Choose how RidePilot connects to the GPS data:

   - **OpenTransit REST API** — Polls a REST endpoint for vehicle positions
   - **MySQL Direct (busavl)** — Connects directly to the BusAVL database

3. **If using OpenTransit:**
   - Enter the **OpenTransit Server URL** (e.g., `http://10.0.0.18:8080`)
   - The system polls this URL every 15 seconds

4. **If using MySQL Direct:**
   - Enter the **MySQL Host** (e.g., `10.0.0.40`)
   - Enter the **Database Name** (default: `busavl`)
   - Enter **Username** and **Password**

5. Click **"Save AVL Settings"**

```
  ┌──────────────────────────────────────────────┐
  │  AVL / GPS Source                            │
  │                                              │
  │  Use External AVL:  [Yes (Pepwave AVL) ▼]   │
  │                                              │
  │  AVL Data Source:   [OpenTransit REST API ▼] │
  │                                              │
  │  OpenTransit URL:   [http://10.0.0.18:8080]  │
  │                                              │
  │  Status: ● AVL Active                        │
  │  Polling every 15 seconds                    │
  │                                              │
  │          [ Save AVL Settings ]               │
  └──────────────────────────────────────────────┘
```

### 6.3 How Vehicle Matching Works

Pepwave routers transmit a unit number (e.g., "1745"). RidePilot matches this to vehicles using the **Vehicle Name** field. For this to work:

- Each vehicle's **Name** in RidePilot must match its Pepwave unit number
- Example: Vehicle Name = "1745" matches Pepwave unit ID "1745"
- No additional configuration is needed per vehicle

### 6.4 GPS Data Flow

```
  Pepwave Router          OpenTransit Server         RidePilot
  in Vehicle              (or BusAVL MySQL)
       │                        │                       │
       │──── GPS data ─────────▶│                       │
       │     (every 1s)         │                       │
       │                        │◀── poll every 15s ────│
       │                        │                       │
       │                        │──── vehicle locations ▶│
       │                        │                       │
       │                        │                 ┌─────▼──────┐
       │                        │                 │gps_locations│
       │                        │                 │   table     │
       │                        │                 └─────┬──────┘
       │                        │                       │
       │                        │              ┌────────┼────────┐
       │                        │              ▼        ▼        ▼
       │                        │           Live Map   ETAs   Distance
       │                        │           (CAD)    (updates)  Calc
```

### 6.5 Coexisting with Tablet GPS

Both GPS sources can coexist within your organization:
- Toggle is **per provider**, so different providers can use different sources
- Driver tablets continue to be used for **manifest workflow** (marking pickups, dropoffs, arrive, depart) regardless of GPS source
- Only the GPS position data source changes

---

## 7. For Customers: Client Portal & SMS

### 7.1 Client Portal

Customers can view their upcoming trips and track their driver through a web portal. No login is required — access is via a secure link sent by SMS.

> ![Screenshot: Client portal showing next trip with ETA and upcoming trips list](screenshots/client-portal.png)
>
> *The customer portal shows your next ride with an estimated arrival time, plus upcoming trips.*

**What customers see:**

- **Next Trip Card** — Pickup time, pickup address, dropoff address, and estimated driver arrival time
- **Driver Map** — Live map showing the driver's current location (when available)
- **Upcoming Trips** — List of future scheduled trips with dates and addresses

```
  ┌─────────────────────────────────────┐
  │  🚐 Your Next Ride                  │
  │                                     │
  │  Pickup: 9:30 AM                    │
  │  From:   123 Main Street            │
  │  To:     Victoria General Hospital  │
  │                                     │
  │  Estimated arrival: 9:25 AM         │
  │                                     │
  │  ┌─────────────────────────────┐    │
  │  │                             │    │
  │  │      [ Driver Map ]         │    │
  │  │                             │    │
  │  └─────────────────────────────┘    │
  │                                     │
  │  ─── Upcoming Trips ───             │
  │  Wed 18 Mar 2:30 PM                 │
  │  456 Oak Ave → Community Center     │
  │                                     │
  │  Fri 20 Mar 10:00 AM               │
  │  123 Main St → Pharmacy             │
  └─────────────────────────────────────┘
```

### 7.2 SMS Notifications

Customers who opt in to SMS receive automated text messages throughout the trip lifecycle:

| When | Message |
|------|---------|
| **Trip booked** | Confirmation with pickup time and address |
| **Day before** | Reminder with pickup time and agency phone number |
| **After optimization** | Updated ETA window (±10 minutes) |
| **ETA change > 5 min** | Notification of schedule change with new time |
| **Driver approaching** | "Your driver is X minutes away" with vehicle description |
| **Trip cancelled** | Cancellation notice with phone number to rebook |

**Example messages:**

> *"Your ride is confirmed for Mar 16 at 9:30 AM. Pickup at 123 Main Street. Reply STOP to opt out."*

> *"Reminder: You have a ride tomorrow at 9:30 AM. Call 250-555-0100 to make changes."*

> *"Your driver is approximately 5 minutes away. Look for a white 2019 Ford Transit."*

**Bilingual support:** Messages are sent in English or Spanish based on the customer's preferred language setting.

### 7.3 Opting Out of SMS

Customers can opt out at any time by replying **STOP** to any text message. This automatically disables SMS notifications for their account. To re-enable, contact the provider office.

### 7.4 Setting Up SMS for a Customer (Staff)

To enable SMS notifications for a customer:

1. Open the customer profile
2. Ensure a valid **mobile phone number** is on file
3. Enable the **SMS Notifications** flag
4. Set the customer's **preferred language** (English or Spanish)

---

## Appendix: Keyboard Shortcuts & Tips

### Address Entry Tips

- **Use saved addresses** when possible — they're faster and more accurate than typing new ones
- For locations without a street address, toggle the **Lat/Lon** switch to enter coordinates directly
- The address search is filtered to your provider's service region for faster results

### Dispatch Screen Tips

- **Resize panels** by dragging the vertical divider between runs and unassigned trips
- **Collapse runs** you're not working with to save screen space — the state is remembered between sessions
- Use the **trip type dropdown** in the unassigned panel to switch between Unscheduled, Standby, and Cab trips
- **Click a phone number** in the manifest to reveal both phone numbers for the customer

### Optimization Tips

- The optimizer works best with **complete information** — make sure pickup times, appointment times, and mobility needs are filled in
- After optimization, **review the manifest** before publishing — you can always drag stops to adjust manually
- For runs with mixed accessibility needs, the optimizer automatically considers wheelchair capacity separately from regular seating

### General Tips

- Most date fields have a **calendar picker** — click the field to open it
- **Flash messages** appear at the top of the screen to confirm actions or show errors
- Use **Clone Trip** for customers who take the same ride regularly
- Use **Create Return Trip** for round trips — it automatically swaps pickup and dropoff addresses

---

*This guide covers RidePilot as configured for Greater Victoria Regional Transit. Features may vary based on your provider settings and user role. For technical support, contact your system administrator.*
