# RidePilot Route Optimizer Integration
**Handover document for Claude Code**

---

## Project context

RidePilot is a Ruby on Rails paratransit scheduling app (AGPL v3, maintained by Cambridge Systematics).
Repo: https://github.com/camsys/ridepilot (branch: `develop`)
Stack: Rails, PostgreSQL + PostGIS, Sidekiq, Docker

Goal: Integrate a modern route optimization engine so that when rides are booked and runs are planned,
the system can automatically suggest or apply an optimal stop ordering — replacing the current
manual drag-and-drop dispatcher workflow.

---

## Problem framing — this is NOT TSP

Pure Travelling Salesman Problem minimizes total distance with no constraints.
Paratransit scheduling is actually a **Dial-a-Ride Problem (DARP)** / **Pickup and Delivery Problem
with Time Windows (PDPTW)**:

- Each trip is a **coupled pickup + dropoff** pair that cannot be separated
- Every trip has a **time window** (scheduled pickup time ± slack, typically ±5–10 min)
- Each run has **capacity constraints**: seats AND tie-down spaces tracked separately
- Multiple vehicles/runs operate concurrently on the same day
- Ride sharing (trip consolidation across passengers) is a primary efficiency goal
- Customer special needs (mobility devices, attendants, door-to-door requirements) add soft constraints

**Recommended solver: Google OR-Tools `RoutingModel` with PDPTW**
- Free, Apache 2.0 licensed
- Solves a 20–50 stop run in <50ms on CPU
- Native support for: pickup-delivery pairs, time windows, multiple capacity dimensions,
  multiple vehicles, soft time window violations with penalties

**On GPU acceleration:** Not useful at single-agency paratransit scale. A full day's schedule
(10 runs × 20 trips) solves in <2 seconds on one CPU core. GPU matters only at SaaS scale
(thousands of simultaneous runs across many agencies) — revisit with NVIDIA CuOpt at that point.

---

## Architecture — Python microservice sidecar

Keep the optimizer completely decoupled from the Rails stack.
RidePilot calls it via HTTP; the optimizer returns a suggested trip sequence and ETAs.

```
RidePilot (Rails)                    Optimizer (Python)
─────────────────                    ──────────────────
TripsController#create ──┐
RunsController#optimize ─┴──► RouteOptimizeJob (Sidekiq)
                                      │
                                      ▼
                              OptimizerClient (Faraday)
                                      │
                              HTTP POST /optimize/run
                                      │
                                      ▼
                              FastAPI endpoint
                                      │
                                      ▼
                              OR-Tools PDPTW solver
                                      │  (uses travel time matrix)
                                      ▼
                              OSRM /table API
                                      │
                                      ▼
                              Response: ordered trip_ids + ETAs
                                      │
                                      ▼
                              Trip.update!(position, eta)
```

---

## Trigger points (when to call the optimizer)

| Trigger | Behavior | Priority |
|---|---|---|
| Overnight batch job | Optimize all next-day runs, cross-run consolidation suggestions | **Start here** |
| Dispatcher "Optimize run" button | Reorder trips in a single run | Second |
| On trip booking | Suggest best run + insert position for new trip | Third |
| Live re-optimization | Driver late / no-show, rebalance remaining stops | Later |

Start with overnight batch — lowest risk, dispatcher sees results next morning and can override.
The existing drag-and-drop UI is the natural safety valve: optimizer proposes, dispatcher approves.

---

## Implementation

### 1. Python optimizer microservice

**File structure:**
```
optimizer_service/
├── main.py           # FastAPI app + endpoint
├── solver.py         # OR-Tools PDPTW logic
├── travel_time.py    # OSRM matrix client
├── requirements.txt  # ortools, fastapi, uvicorn, httpx, pydantic
├── Dockerfile
└── docker-compose.yml
```

**`optimizer_service/main.py`:**
```python
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from solver import solve_run
import logging

logger = logging.getLogger(__name__)
app = FastAPI(title="RidePilot Route Optimizer")


class Trip(BaseModel):
    trip_id: int
    pickup_lat: float
    pickup_lng: float
    dropoff_lat: float
    dropoff_lng: float
    earliest_pickup: int    # seconds from midnight
    latest_pickup: int      # seconds from midnight
    seats: int              # number of ambulatory seats required
    tie_downs: int          # number of wheelchair tie-down spaces required


class OptimizeRequest(BaseModel):
    run_id: int
    vehicle_capacity_seats: int
    vehicle_capacity_tie_downs: int
    trips: list[Trip]


class OptimizeResponse(BaseModel):
    run_id: int
    ordered_trip_ids: list[int]
    etas: list[int]          # seconds from midnight, parallel to ordered_trip_ids
    total_distance_m: float
    solver_status: str


@app.post("/optimize/run", response_model=OptimizeResponse)
def optimize_run(req: OptimizeRequest):
    if not req.trips:
        raise HTTPException(status_code=400, detail="No trips provided")
    try:
        result = solve_run(req)
        return result
    except Exception as e:
        logger.exception("Solver error for run %s", req.run_id)
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/health")
def health():
    return {"status": "ok"}
```

**`optimizer_service/solver.py`:**
```python
from ortools.constraint_solver import routing_enums_pb2, pywrapcp
from travel_time import build_time_matrix
import math


def solve_run(req):
    trips = req.trips
    n = len(trips)

    # Node layout: 0..n-1 = pickups, n..2n-1 = dropoffs, 2n = depot
    depot = 2 * n
    num_nodes = 2 * n + 1

    # Build travel time matrix (seconds) via OSRM
    coords = (
        [(t.pickup_lat, t.pickup_lng) for t in trips]
        + [(t.dropoff_lat, t.dropoff_lng) for t in trips]
        + [(0.0, 0.0)]  # depot placeholder
    )
    time_matrix = build_time_matrix(coords)

    manager = pywrapcp.RoutingIndexManager(num_nodes, 1, depot)
    routing = pywrapcp.RoutingModel(manager)

    # Time callback
    def time_callback(from_idx, to_idx):
        return time_matrix[manager.IndexToNode(from_idx)][manager.IndexToNode(to_idx)]

    transit_idx = routing.RegisterTransitCallback(time_callback)
    routing.SetArcCostEvaluatorOfAllVehicles(transit_idx)

    # Time window dimension
    max_time = 86400  # seconds in a day
    boarding_slack = 120  # 2 min default board/alight time
    routing.AddDimension(transit_idx, boarding_slack, max_time, False, "Time")
    time_dim = routing.GetDimensionOrDie("Time")

    for i, trip in enumerate(trips):
        # Pickup time window
        pickup_idx = manager.NodeToIndex(i)
        time_dim.CumulVar(pickup_idx).SetRange(trip.earliest_pickup, trip.latest_pickup)
        # Dropoff: must be after pickup (no explicit window — just precedence)
        dropoff_idx = manager.NodeToIndex(i + n)
        time_dim.CumulVar(dropoff_idx).SetRange(trip.earliest_pickup, max_time)

    # Capacity dimensions — seats
    def seat_callback(idx):
        node = manager.IndexToNode(idx)
        if node < n:
            return trips[node].seats       # pickup: add passengers
        elif node < 2 * n:
            return -trips[node - n].seats  # dropoff: remove passengers
        return 0

    seat_idx = routing.RegisterUnaryTransitCallback(seat_callback)
    routing.AddDimensionWithVehicleCapacity(
        seat_idx, 0, [req.vehicle_capacity_seats], True, "Seats"
    )

    # Capacity dimensions — tie-downs
    def tiedown_callback(idx):
        node = manager.IndexToNode(idx)
        if node < n:
            return trips[node].tie_downs
        elif node < 2 * n:
            return -trips[node - n].tie_downs
        return 0

    tiedown_idx = routing.RegisterUnaryTransitCallback(tiedown_callback)
    routing.AddDimensionWithVehicleCapacity(
        tiedown_idx, 0, [req.vehicle_capacity_tie_downs], True, "TieDowns"
    )

    # Pickup-delivery constraints (keep pairs together and ordered)
    for i in range(n):
        pickup_idx = manager.NodeToIndex(i)
        dropoff_idx = manager.NodeToIndex(i + n)
        routing.AddPickupAndDelivery(pickup_idx, dropoff_idx)
        routing.solver().Add(
            routing.VehicleVar(pickup_idx) == routing.VehicleVar(dropoff_idx)
        )
        routing.solver().Add(
            time_dim.CumulVar(pickup_idx) <= time_dim.CumulVar(dropoff_idx)
        )

    # Search parameters
    params = pywrapcp.DefaultRoutingSearchParameters()
    params.first_solution_strategy = routing_enums_pb2.FirstSolutionStrategy.PARALLEL_CHEAPEST_INSERTION
    params.local_search_metaheuristic = routing_enums_pb2.LocalSearchMetaheuristic.GUIDED_LOCAL_SEARCH
    params.time_limit.seconds = 10  # max 10s per run — plenty for paratransit scale

    solution = routing.SolveWithParameters(params)

    if not solution:
        raise RuntimeError(f"No feasible solution found for run {req.run_id}")

    # Extract ordered route
    ordered_trip_ids = []
    etas = []
    index = routing.Start(0)
    while not routing.IsEnd(index):
        node = manager.IndexToNode(index)
        if node < n:  # pickup node — record trip order by pickup sequence
            ordered_trip_ids.append(trips[node].trip_id)
            etas.append(solution.Value(time_dim.CumulVar(index)))
        index = solution.Value(routing.NextVar(index))

    status_map = {0: "not_solved", 1: "success", 2: "fail", 3: "fail", 4: "fail"}

    return {
        "run_id": req.run_id,
        "ordered_trip_ids": ordered_trip_ids,
        "etas": etas,
        "total_distance_m": float(solution.ObjectiveValue()),
        "solver_status": status_map.get(routing.status(), "unknown"),
    }
```

**`optimizer_service/travel_time.py`:**
```python
import httpx
import math
import os

OSRM_URL = os.getenv("OSRM_URL", "http://osrm:5000")


def build_time_matrix(coords: list[tuple[float, float]]) -> list[list[int]]:
    """
    Call OSRM /table endpoint to get NxN travel time matrix (seconds).
    Falls back to Euclidean estimate if OSRM unavailable.
    coords: list of (lat, lng) tuples
    """
    try:
        coord_str = ";".join(f"{lng},{lat}" for lat, lng in coords)
        resp = httpx.get(
            f"{OSRM_URL}/table/v1/driving/{coord_str}",
            params={"annotations": "duration"},
            timeout=15.0,
        )
        resp.raise_for_status()
        data = resp.json()
        return [[int(v or 0) for v in row] for row in data["durations"]]
    except Exception:
        # Fallback: straight-line distance / 30 km/h
        return _euclidean_matrix(coords)


def _euclidean_matrix(coords):
    n = len(coords)
    matrix = [[0] * n for _ in range(n)]
    for i in range(n):
        for j in range(n):
            if i != j:
                dist_m = _haversine_m(coords[i], coords[j])
                matrix[i][j] = int(dist_m / 8.33)  # ~30 km/h in m/s
    return matrix


def _haversine_m(a, b):
    R = 6_371_000
    lat1, lng1 = math.radians(a[0]), math.radians(a[1])
    lat2, lng2 = math.radians(b[0]), math.radians(b[1])
    dlat, dlng = lat2 - lat1, lng2 - lng1
    h = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlng / 2) ** 2
    return 2 * R * math.asin(math.sqrt(h))
```

**`optimizer_service/requirements.txt`:**
```
ortools>=9.8
fastapi>=0.110
uvicorn[standard]>=0.29
httpx>=0.27
pydantic>=2.0
```

**`optimizer_service/Dockerfile`:**
```dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8765"]
```

---

### 2. Rails integration

**`app/services/route_optimizer_service.rb`:**
```ruby
class RouteOptimizerService
  OPTIMIZER_URL = ENV.fetch("OPTIMIZER_URL", "http://localhost:8765")
  PICKUP_SLACK_BEFORE = 5.minutes
  PICKUP_SLACK_AFTER  = 10.minutes

  def self.optimize_run(run)
    new(run).call
  end

  def initialize(run)
    @run = run
  end

  def call
    payload = build_payload
    return { error: "No trips on run" } if payload[:trips].empty?

    resp = Faraday.post(
      "#{OPTIMIZER_URL}/optimize/run",
      payload.to_json,
      "Content-Type" => "application/json"
    )

    raise "Optimizer HTTP #{resp.status}" unless resp.success?

    result = JSON.parse(resp.body)
    apply_result(result)
    result
  end

  private

  def build_payload
    {
      run_id: @run.id,
      vehicle_capacity_seats:     @run.vehicle&.max_capacity_seats    || 8,
      vehicle_capacity_tie_downs: @run.vehicle&.max_capacity_tie_downs || 2,
      trips: @run.trips.map { |t| serialize_trip(t) }.compact
    }
  end

  def serialize_trip(trip)
    return nil unless trip.pickup_address&.latitude && trip.dropoff_address&.latitude
    {
      trip_id:         trip.id,
      pickup_lat:      trip.pickup_address.latitude.to_f,
      pickup_lng:      trip.pickup_address.longitude.to_f,
      dropoff_lat:     trip.dropoff_address.latitude.to_f,
      dropoff_lng:     trip.dropoff_address.longitude.to_f,
      earliest_pickup: (trip.pickup_time - PICKUP_SLACK_BEFORE).seconds_since_midnight.to_i,
      latest_pickup:   (trip.pickup_time + PICKUP_SLACK_AFTER).seconds_since_midnight.to_i,
      seats:           trip.mobility_capacity(:seat)     || 1,
      tie_downs:       trip.mobility_capacity(:tie_down) || 0
    }
  end

  def apply_result(result)
    ActiveRecord::Base.transaction do
      result["ordered_trip_ids"].each_with_index do |trip_id, position|
        eta_seconds = result["etas"][position]
        eta_time    = @run.date.to_time + eta_seconds.seconds

        Trip.find(trip_id).update!(
          run_position: position,
          estimated_pickup_time: eta_time
        )
      end
    end
  end
end
```

**`app/jobs/route_optimize_job.rb`:**
```ruby
class RouteOptimizeJob < ApplicationJob
  queue_as :optimizer
  retry_on StandardError, wait: 30.seconds, attempts: 3

  def perform(run_id)
    run = Run.find(run_id)
    RouteOptimizerService.optimize_run(run)
  end
end
```

**`app/controllers/runs_controller.rb` — add action:**
```ruby
def optimize
  @run = Run.find(params[:id])
  authorize! :update, @run
  RouteOptimizeJob.perform_later(@run.id)
  respond_to do |format|
    format.json { render json: { status: "queued", run_id: @run.id } }
    format.html { redirect_to run_path(@run), notice: "Route optimization queued." }
  end
end
```

**`config/routes.rb` — add to runs resource:**
```ruby
resources :runs do
  member { post :optimize }
end
```

**Database migration — add fields to trips:**
```ruby
class AddOptimizerFieldsToTrips < ActiveRecord::Migration[7.0]
  def change
    add_column :trips, :run_position, :integer
    add_column :trips, :estimated_pickup_time, :datetime
    add_index  :trips, [:run_id, :run_position]
  end
end
```

---

### 3. Overnight batch job

```ruby
# app/jobs/overnight_optimize_job.rb
class OvernightOptimizeJob < ApplicationJob
  queue_as :optimizer

  def perform(date = Date.tomorrow)
    Run.for_date(date).each do |run|
      next if run.trips.count < 2
      RouteOptimizeJob.perform_later(run.id)
    end
  end
end
```

Schedule via `config/schedule.rb` (whenever gem) or Sidekiq-cron:
```ruby
every 1.day, at: "11:00 pm" do
  runner "OvernightOptimizeJob.perform_later"
end
```

---

### 4. OSRM setup (self-hosted, recommended)

```bash
# Download Texas road data
wget https://download.geofabrik.de/north-america/us/texas-latest.osm.pbf

# Process and start OSRM
docker run -t -v $(pwd):/data osrm/osrm-backend osrm-extract \
  -p /opt/car.lua /data/texas-latest.osm.pbf
docker run -t -v $(pwd):/data osrm/osrm-backend osrm-partition /data/texas-latest.osrm
docker run -t -v $(pwd):/data osrm/osrm-backend osrm-customize /data/texas-latest.osrm
docker run -d -p 5000:5000 -v $(pwd):/data osrm/osrm-backend \
  osrm-routed --algorithm mld /data/texas-latest.osrm
```

Add to `docker-compose.yml`:
```yaml
services:
  optimizer:
    build: ./optimizer_service
    ports:
      - "8765:8765"
    environment:
      - OSRM_URL=http://osrm:5000
    depends_on:
      - osrm

  osrm:
    image: osrm/osrm-backend
    command: osrm-routed --algorithm mld /data/texas-latest.osrm
    volumes:
      - ./osrm-data:/data
    ports:
      - "5000:5000"
```

---

## Key RidePilot model relationships to understand

```
Provider
  └── Run (vehicle + driver + date)
        └── Trip (pickup addr, dropoff addr, pickup_time, customer)
              └── Customer (mobility_needs, funding_sources)
```

Relevant existing model files to review:
- `app/models/run.rb` — scope `for_date`, associations
- `app/models/trip.rb` — `mobility_capacity` method, address associations
- `app/models/address.rb` — has `latitude`, `longitude` (geocoded via Google Maps API)
- `app/models/vehicle.rb` — capacity fields (check exact column names)

---

## RidePilot-specific gotchas

1. **Address geocoding** — RidePilot geocodes addresses on save via Google Maps. Confirm `latitude`/`longitude` are populated before calling optimizer; some legacy addresses may be null.

2. **Mobility capacity** — trips use a `TripCapacity` join model. The `mobility_capacity(:seat)` helper already exists in `Trip`; verify it returns an integer.

3. **Run position** — RidePilot may already have a `position` or ordering field on trips. Check the schema before adding `run_position` to avoid conflicts.

4. **Multi-tenant** — RidePilot is multi-provider. The optimizer service is provider-agnostic (just works on a run's trips), so no special handling needed there.

5. **Time zones** — Victoria, TX is Central time. `pickup_time` is stored as UTC in Rails. Use `seconds_since_midnight` on the local time, not UTC, when building the payload.

---

## Testing the optimizer independently

```bash
curl -X POST http://localhost:8765/optimize/run \
  -H "Content-Type: application/json" \
  -d '{
    "run_id": 1,
    "vehicle_capacity_seats": 8,
    "vehicle_capacity_tie_downs": 2,
    "trips": [
      {
        "trip_id": 101,
        "pickup_lat": 28.8052, "pickup_lng": -97.0036,
        "dropoff_lat": 28.8150, "dropoff_lng": -96.9800,
        "earliest_pickup": 28800, "latest_pickup": 29400,
        "seats": 1, "tie_downs": 0
      },
      {
        "trip_id": 102,
        "pickup_lat": 28.7900, "pickup_lng": -97.0200,
        "dropoff_lat": 28.8300, "dropoff_lng": -96.9900,
        "earliest_pickup": 29100, "latest_pickup": 30000,
        "seats": 0, "tie_downs": 1
      }
    ]
  }'
```

Expected response:
```json
{
  "run_id": 1,
  "ordered_trip_ids": [101, 102],
  "etas": [28920, 29340],
  "total_distance_m": 4821.0,
  "solver_status": "success"
}
```

---

### 5. Cross-run consolidation

Rather than optimizing each run in isolation, this extends the solver to assign trips across runs
simultaneously — finding cases where a passenger on Run A could be served by Run B with less
total deadhead mileage.

**How it works:** Instead of `num_vehicles=1`, pass `num_vehicles=len(runs)` to OR-Tools.
Each run becomes a vehicle with its own capacity and start/end depot (the garage). OR-Tools
then assigns trips to runs *and* sequences them in a single solve.

**New endpoint: `POST /optimize/fleet`**

```python
class FleetOptimizeRequest(BaseModel):
    provider_id: int
    date: str                       # YYYY-MM-DD
    vehicles: list[VehicleSpec]     # one per run
    trips: list[Trip]               # all unassigned or reassignable trips

class VehicleSpec(BaseModel):
    run_id: int
    capacity_seats: int
    capacity_tie_downs: int
    start_lat: float                # garage / first stop
    start_lng: float
    earliest_start: int             # seconds from midnight
    latest_end: int
```

The solver returns `{trip_id, assigned_run_id, position, eta}` for every trip.

**Rails job:**
```ruby
class FleetOptimizeJob < ApplicationJob
  queue_as :optimizer

  def perform(provider_id, date)
    provider = Provider.find(provider_id)
    runs  = provider.runs.for_date(date).includes(:vehicle, trips: [:pickup_address, :dropoff_address])
    trips = runs.flat_map(&:trips)

    payload = FleetOptimizerPayload.new(runs, trips).build
    result  = OptimizerClient.post("/optimize/fleet", payload)

    ActiveRecord::Base.transaction do
      result["assignments"].each do |assignment|
        Trip.find(assignment["trip_id"]).update!(
          run_id:                assignment["run_id"],
          run_position:          assignment["position"],
          estimated_pickup_time: time_from_seconds(date, assignment["eta"])
        )
      end
    end
  end
end
```

Add to overnight schedule after per-run optimize:
```ruby
every 1.day, at: "11:15 pm" do
  runner "FleetOptimizeJob.perform_later(Provider.all.pluck(:id), Date.tomorrow)"
end
```

---

### 6. Real-time re-optimization with WebSocket ETA push

When a driver is running late or a passenger is a no-show, re-run the solver on the remaining
stops and push updated ETAs to the dispatcher and driver app (RideAVL) over ActionCable.

**Trigger conditions** (detected in the CAD/AVL layer):
- GPS position shows vehicle >5 min behind current ETA
- Dispatcher marks a trip as no-show
- Driver sends emergency alert

**Rails channel:**
```ruby
# app/channels/run_eta_channel.rb
class RunEtaChannel < ApplicationCable::Channel
  def subscribed
    stream_from "run_eta_#{params[:run_id]}"
  end
end
```

**Re-optimize job:**
```ruby
class RealtimeReoptimizeJob < ApplicationJob
  queue_as :optimizer_realtime   # separate high-priority queue

  def perform(run_id, completed_trip_ids: [])
    run = Run.find(run_id)
    remaining_trips = run.trips.where.not(id: completed_trip_ids)
    return if remaining_trips.count < 2

    result = RouteOptimizerService.optimize_run_with_trips(run, remaining_trips)

    # Push ETAs to dispatcher UI and RideAVL driver app
    ActionCable.server.broadcast("run_eta_#{run_id}", {
      ordered_trip_ids: result["ordered_trip_ids"],
      etas:             result["etas"],
      updated_at:       Time.current.iso8601
    })
  end
end
```

**JavaScript subscriber (dispatch view):**
```javascript
// app/javascript/channels/run_eta_channel.js
import consumer from "./consumer"

consumer.subscriptions.create(
  { channel: "RunEtaChannel", run_id: gon.run_id },
  {
    received(data) {
      data.ordered_trip_ids.forEach((tripId, i) => {
        const eta = new Date(data.etas[i] * 1000)
        document.querySelector(`[data-trip-id="${tripId}"] .eta`)
                .textContent = eta.toLocaleTimeString()
      })
    }
  }
)
```

**Sidekiq queue config** (`config/sidekiq.yml`):
```yaml
queues:
  - [optimizer_realtime, 10]   # highest priority
  - [optimizer, 3]
  - [default, 1]
```

---

### 7. NVIDIA CuOpt integration (SaaS / TransMilenio scale)

When the GTFS SaaS product scales to multiple agencies — particularly with the TransMilenio
connection — OR-Tools on CPU will still handle dozens of agencies fine, but CuOpt becomes
relevant at hundreds of agencies or very large fleets (500+ vehicles).

CuOpt is a drop-in replacement: same PDPTW problem formulation, GPU-parallelized across vehicles.
It exposes a REST API identical enough to swap in behind the existing `OptimizerClient`.

**Feature flag approach** — don't rip out OR-Tools, gate by provider:

```python
# optimizer_service/solver.py
import os

def solve_run(req):
    backend = os.getenv("SOLVER_BACKEND", "ortools")
    if backend == "cuopt":
        from cuopt_solver import solve_run_cuopt
        return solve_run_cuopt(req)
    else:
        return _solve_ortools(req)
```

**`optimizer_service/cuopt_solver.py`:**
```python
import httpx, os

CUOPT_URL = os.getenv("CUOPT_URL", "http://cuopt-server:8000")

def solve_run_cuopt(req):
    # CuOpt expects same logical structure — build its payload format
    payload = {
        "cost_matrix_data": {"data": {"0": build_flat_matrix(req)}},
        "task_data": build_task_data(req),
        "fleet_data": build_fleet_data(req),
        "solver_config": {"time_limit": 10, "number_of_climbers": 128}
    }
    resp = httpx.post(f"{CUOPT_URL}/cuopt/", json=payload, timeout=30)
    resp.raise_for_status()
    return parse_cuopt_response(resp.json(), req)
```

Set `SOLVER_BACKEND=cuopt` in the provider's environment when ready to migrate.

---

### 8. ML-based travel time prediction

OSRM uses static road network speeds. For Victoria TX, actual travel times vary by time of day,
school zones, railroad crossings, and weather. Replace the OSRM matrix with a learned model
trained on historical trip data from RidePilot's own `actual_pickup_time` records.

**Data available in RidePilot:** `Trip` has `pickup_time` (scheduled) and `actual_pickup_time`
(recorded by driver). The delta, combined with origin/destination and time-of-day, trains a
correction model.

**Simple approach — XGBoost correction on top of OSRM:**
```python
# optimizer_service/travel_time_ml.py
import joblib, numpy as np
from travel_time import build_time_matrix as osrm_matrix

model = joblib.load("models/travel_time_corrector.pkl")  # trained offline

def build_time_matrix_ml(coords, departure_time_seconds):
    base = osrm_matrix(coords)
    n = len(coords)
    corrected = [[0] * n for _ in range(n)]
    for i in range(n):
        for j in range(n):
            if i == j:
                continue
            features = np.array([[
                base[i][j],                      # OSRM estimate
                departure_time_seconds / 3600,   # hour of day
                coords[i][0], coords[i][1],      # origin lat/lng
                coords[j][0], coords[j][1],      # dest lat/lng
            ]])
            corrected[i][j] = int(model.predict(features)[0])
    return corrected
```

**Training pipeline** (`scripts/train_travel_time_model.py`):
```python
# Pull historical trip data from RidePilot DB
# Features: osrm_estimate, hour_of_day, origin_lat, origin_lng, dest_lat, dest_lng
# Target: actual_travel_time_seconds (actual_pickup_time - departure_time)
# Model: XGBRegressor, retrain weekly via cron
```

Gate behind env var: `TRAVEL_TIME_BACKEND=ml` vs `osrm`.

---

### 9. Soft constraint tuning

Hard constraints (time windows, capacity) are enforced as solver constraints.
Soft constraints are penalties — the solver tries to minimize them but will violate them if needed.

**Per-customer lateness penalty weights:**

Some passengers (dialysis patients, job commuters) have zero tolerance for lateness.
Others are flexible. Store a `scheduling_priority` on the `Customer` model (1–5) and map to
OR-Tools penalty multipliers.

```python
# In solver.py — replace hard time windows with penalized soft windows for flexible customers
def add_time_windows(routing, manager, time_dim, trips):
    for i, trip in enumerate(trips):
        idx = manager.NodeToIndex(i)
        if trip.scheduling_priority >= 4:
            # Hard window — must be on time
            time_dim.CumulVar(idx).SetRange(trip.earliest_pickup, trip.latest_pickup)
        else:
            # Soft window — penalize lateness proportional to priority
            penalty = (6 - trip.scheduling_priority) * 60  # seconds of extra cost per violation
            time_dim.SetCumulVarSoftUpperBound(idx, trip.latest_pickup, penalty)
```

**Preferred driver assignments:**

Some passengers have established relationships with specific drivers.
Model as a fixed-vehicle constraint or high arc cost:

```python
# If a trip has a preferred_driver, assign to that vehicle (run) or add 30min penalty
if trip.preferred_run_id:
    preferred_vehicle = run_id_to_vehicle_index[trip.preferred_run_id]
    routing.SetAllowedVehiclesForIndex([preferred_vehicle], manager.NodeToIndex(i))
```

**Rails side — add to Customer model:**
```ruby
# migration
add_column :customers, :scheduling_priority, :integer, default: 3
add_column :customers, :preferred_driver_id, :integer, references: :users

# In RouteOptimizerService#serialize_trip:
seats:                trip.mobility_capacity(:seat) || 1,
tie_downs:            trip.mobility_capacity(:tie_down) || 0,
scheduling_priority:  trip.customer&.scheduling_priority || 3,
preferred_run_id:     trip.customer&.preferred_driver&.current_run_id
```

---

### 10. Client SMS notifications

Passengers receive automated SMS messages at key moments in their trip lifecycle —
confirmation, day-before reminder, morning-of ETA window, vehicle approaching, and
any schedule changes triggered by the optimizer. Uses Twilio as the SMS provider.
Bilingual by default (English + Spanish) given Victoria TX demographics; Vietnamese
support is straightforward to add given the existing call center language work.

**Gems:**
```ruby
# Gemfile
gem "twilio-ruby"
gem "i18n"   # already in Rails — used for message templates
```

**Environment variables (`config/application.yml`):**
```yaml
TWILIO_ACCOUNT_SID: "ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
TWILIO_AUTH_TOKEN:  "your_auth_token"
TWILIO_FROM_NUMBER: "+13618001234"   # Victoria TX area code
```

**`app/services/sms_notification_service.rb`:**
```ruby
class SmsNotificationService
  CLIENT = Twilio::REST::Client.new(
    ENV["TWILIO_ACCOUNT_SID"],
    ENV["TWILIO_AUTH_TOKEN"]
  )
  FROM = ENV["TWILIO_FROM_NUMBER"]

  TEMPLATES = {
    confirmation: {
      en: "Your %{agency} ride is confirmed. Pickup at %{pickup_time} from %{pickup_address}. " \
          "Reply STOP to opt out.",
      es: "Su viaje con %{agency} está confirmado. Recogida a las %{pickup_time} en %{pickup_address}. " \
          "Responda STOP para cancelar."
    },
    reminder_day_before: {
      en: "Reminder: Your %{agency} ride is tomorrow at %{pickup_time}. " \
          "Call %{phone} to cancel or change.",
      es: "Recordatorio: Su viaje con %{agency} es mañana a las %{pickup_time}. " \
          "Llame al %{phone} para cancelar o cambiar."
    },
    eta_window: {
      en: "Your %{agency} driver will arrive between %{eta_start} and %{eta_end}. " \
          "Please be ready at %{pickup_address}.",
      es: "Su conductor de %{agency} llegará entre las %{eta_start} y las %{eta_end}. " \
          "Por favor esté listo en %{pickup_address}."
    },
    vehicle_approaching: {
      en: "Your %{agency} driver is %{minutes} minutes away. Vehicle: %{vehicle_description}.",
      es: "Su conductor de %{agency} está a %{minutes} minutos. Vehículo: %{vehicle_description}."
    },
    schedule_change: {
      en: "Schedule update: Your pickup time has changed to %{new_time}. " \
          "Questions? Call %{phone}.",
      es: "Actualización: Su hora de recogida cambió a %{new_time}. " \
          "¿Preguntas? Llame al %{phone}."
    },
    trip_cancelled: {
      en: "Your %{agency} trip for %{date} has been cancelled. Call %{phone} to reschedule.",
      es: "Su viaje con %{agency} para el %{date} fue cancelado. Llame al %{phone} para reprogramar."
    }
  }.freeze

  def self.send(customer:, template:, **vars)
    return unless customer.sms_notifications_enabled? && customer.phone_number.present?

    lang   = customer.preferred_language.to_sym.then { |l| TEMPLATES[template].key?(l) ? l : :en }
    body   = format(TEMPLATES[template][lang], **vars)
    number = normalize_phone(customer.phone_number)

    CLIENT.messages.create(from: FROM, to: number, body: body)
  rescue Twilio::REST::RestError => e
    Rails.logger.error("SMS failed for customer #{customer.id}: #{e.message}")
  end

  def self.normalize_phone(raw)
    digits = raw.gsub(/\D/, "")
    digits.length == 10 ? "+1#{digits}" : "+#{digits}"
  end
end
```

**`app/jobs/sms_notification_job.rb`:**
```ruby
class SmsNotificationJob < ApplicationJob
  queue_as :notifications
  retry_on Twilio::REST::RestError, wait: 2.minutes, attempts: 3

  def perform(customer_id, template, **vars)
    customer = Customer.find(customer_id)
    SmsNotificationService.send(customer: customer, template: template.to_sym, **vars)
  end
end
```

**Trigger points in the Rails app:**

```ruby
# After trip is confirmed (TripsController#create or Trip after_commit)
class Trip < ApplicationRecord
  after_commit :send_confirmation_sms, on: :create

  private

  def send_confirmation_sms
    SmsNotificationJob.perform_later(
      customer_id,
      :confirmation,
      agency:          provider.name,
      pickup_time:     pickup_time.in_time_zone("Central Time (US & Canada)").strftime("%I:%M %p"),
      pickup_address:  pickup_address.text
    )
  end
end
```

```ruby
# Day-before reminder — schedule for 6 PM the evening before
class DayBeforeReminderJob < ApplicationJob
  queue_as :notifications

  def perform(date = Date.tomorrow)
    Trip.confirmed.for_date(date).each do |trip|
      SmsNotificationJob.perform_later(
        trip.customer_id,
        :reminder_day_before,
        agency:      trip.provider.name,
        pickup_time: trip.pickup_time.in_time_zone("Central Time (US & Canada)").strftime("%I:%M %p"),
        phone:       trip.provider.phone
      )
    end
  end
end
```

```ruby
# Morning ETA window — fired by OvernightOptimizeJob after run is solved
# Sends the ±window based on optimizer ETA
def send_eta_window_notifications(run, result)
  result["ordered_trip_ids"].each_with_index do |trip_id, i|
    trip = Trip.find(trip_id)
    eta  = result["etas"][i]
    eta_time = run.date.to_time + eta.seconds

    SmsNotificationJob.perform_later(
      trip.customer_id,
      :eta_window,
      agency:           run.provider.name,
      eta_start:        (eta_time - 10.minutes).strftime("%I:%M %p"),
      eta_end:          (eta_time + 10.minutes).strftime("%I:%M %p"),
      pickup_address:   trip.pickup_address.text
    )
  end
end
```

```ruby
# Vehicle approaching — fired from CAD/AVL when GPS distance < 0.5 miles
# (hook into existing ridepilot_cad_avl engine's position update callback)
class VehicleApproachingJob < ApplicationJob
  queue_as :notifications

  def perform(trip_id, minutes_away)
    trip = Trip.find(trip_id)
    return if trip.approach_notified?   # idempotent — only fire once per trip

    SmsNotificationJob.perform_later(
      trip.customer_id,
      :vehicle_approaching,
      agency:               trip.provider.name,
      minutes:              minutes_away,
      vehicle_description:  "#{trip.run.vehicle.year} #{trip.run.vehicle.make} (#{trip.run.vehicle.license_plate})"
    )
    trip.update!(approach_notified: true)
  end
end
```

```ruby
# Schedule change — fired by RouteOptimizerService#apply_result when ETA shifts > 5 min
def apply_result(result)
  ActiveRecord::Base.transaction do
    result["ordered_trip_ids"].each_with_index do |trip_id, position|
      trip         = Trip.find(trip_id)
      new_eta      = @run.date.to_time + result["etas"][position].seconds
      previous_eta = trip.estimated_pickup_time

      trip.update!(run_position: position, estimated_pickup_time: new_eta)

      if previous_eta && (new_eta - previous_eta).abs > 5.minutes
        SmsNotificationJob.perform_later(
          trip.customer_id,
          :schedule_change,
          new_time: new_eta.in_time_zone("Central Time (US & Canada)").strftime("%I:%M %p"),
          phone:    @run.provider.phone
        )
      end
    end
  end
end
```

**Customer model additions:**
```ruby
# migration
add_column :customers, :sms_notifications_enabled, :boolean, default: true
add_column :customers, :preferred_language,         :string,  default: "en"
add_column :customers, :approach_notified,          :boolean, default: false  # on trips table

# config/schedule.rb
every 1.day, at: "6:00 pm" do
  runner "DayBeforeReminderJob.perform_later"
end
```

**Inbound STOP handling (Twilio webhook):**
```ruby
# config/routes.rb
post "/twilio/sms/inbound", to: "twilio_sms#inbound"

# app/controllers/twilio_sms_controller.rb
class TwilioSmsController < ApplicationController
  skip_before_action :verify_authenticity_token

  def inbound
    body = params[:Body].to_s.strip.upcase
    from = params[:From]

    if body == "STOP"
      customer = Customer.find_by_phone(from)
      customer&.update!(sms_notifications_enabled: false)
    end

    head :ok
  end
end
```

**Sidekiq queue update (`config/sidekiq.yml`):**
```yaml
queues:
  - [optimizer_realtime, 10]
  - [notifications, 7]         # high priority — time-sensitive
  - [optimizer, 3]
  - [default, 1]
```

---

### 11. Optional client app (Progressive Web App)

A lightweight PWA that passengers can add to their home screen — no App Store, no install friction.
Built as a standalone Rails view set served from a `/my-ride` path, rendered as a PWA with
push notification support and offline caching. This is the right approach for a paratransit
population: many passengers are elderly, use older Android devices, and can't navigate app stores.

The app shows the passenger their upcoming trip, live driver location, and ETA. It shares the
same ActionCable connection used by the dispatch view for real-time ETA updates.

**Architecture decision:** PWA over native app because:
- Zero install barrier — share a URL via SMS
- Works on any device with a browser (Android or iOS)
- No separate App Store submission or maintenance
- Shares the existing Rails session/auth layer
- Offline manifest caches the trip details if connectivity drops mid-ride

**Key files:**

```
app/
├── controllers/
│   └── client_portal_controller.rb
├── views/
│   └── client_portal/
│       ├── show.html.erb          # main trip status page
│       └── offline.html.erb       # cached fallback
├── javascript/
│   ├── pwa/
│   │   ├── service_worker.js      # caches assets + trip data
│   │   └── manifest.json
│   └── channels/
│       └── client_eta_channel.js  # subscribes to driver location updates
public/
└── icons/
    ├── icon-192.png
    └── icon-512.png
```

**`app/controllers/client_portal_controller.rb`:**
```ruby
class ClientPortalController < ApplicationController
  # Authenticated via magic link token — no password required
  before_action :authenticate_via_token

  def show
    @customer = current_customer
    @upcoming_trips = @customer.trips
                               .confirmed
                               .where("pickup_time > ?", Time.current)
                               .order(:pickup_time)
                               .limit(3)
                               .includes(:run, :pickup_address, :dropoff_address)
    @next_trip = @upcoming_trips.first
  end

  private

  def authenticate_via_token
    token = params[:token] || session[:client_token]
    @customer_auth = CustomerAuth.find_by(token: token, expires_at: Time.current..)
    if @customer_auth
      session[:client_token] = token
      @current_customer = @customer_auth.customer
    else
      redirect_to root_path, alert: "Link expired. Please call us for a new link."
    end
  end

  def current_customer
    @current_customer
  end
end
```

**`app/models/customer_auth.rb`:**
```ruby
class CustomerAuth < ApplicationRecord
  belongs_to :customer
  before_create { self.token = SecureRandom.urlsafe_base64(32) }

  def self.generate_for(customer, expires_in: 7.days)
    create!(customer: customer, expires_at: expires_in.from_now)
  end
end

# migration
create_table :customer_auths do |t|
  t.references :customer, null: false
  t.string  :token, null: false, index: { unique: true }
  t.datetime :expires_at, null: false
  t.timestamps
end
```

**Magic link delivery via SMS** — triggered when trip is confirmed:
```ruby
# In SmsNotificationService — add to confirmation SMS or send separately
def self.send_portal_link(customer, trip)
  auth  = CustomerAuth.generate_for(customer)
  url   = Rails.application.routes.url_helpers.client_portal_url(token: auth.token)
  lang  = customer.preferred_language.to_sym

  body = lang == :es \
    ? "Siga su viaje con #{trip.provider.name}: #{url}"
    : "Track your #{trip.provider.name} ride: #{url}"

  send_raw(to: customer.phone_number, body: body)
end
```

**`app/views/client_portal/show.html.erb`:**
```erb
<%# Minimal, large-text, mobile-first — paratransit passengers often have vision issues %>
<div class="client-portal" data-trip-id="<%= @next_trip&.id %>"
                           data-run-id="<%= @next_trip&.run_id %>">

  <% if @next_trip %>
    <div class="status-card">
      <p class="status-label">Your next ride</p>
      <p class="pickup-time"><%= @next_trip.pickup_time.in_time_zone("Central Time (US & Canada)")
                                                        .strftime("%A, %B %-d at %I:%M %p") %></p>
      <p class="address">Pickup: <%= @next_trip.pickup_address.text %></p>
      <p class="address">Dropoff: <%= @next_trip.dropoff_address.text %></p>

      <div class="eta-section" id="eta-display">
        <% if @next_trip.estimated_pickup_time %>
          <p class="eta-label">Estimated arrival</p>
          <p class="eta-time" id="eta-time">
            <%= @next_trip.estimated_pickup_time
                          .in_time_zone("Central Time (US & Canada)")
                          .strftime("%I:%M %p") %>
          </p>
        <% end %>
      </div>

      <div id="driver-map" class="driver-map" style="display:none">
        <%# Leaflet map injected by JS once driver location is available %>
      </div>
    </div>

    <div class="upcoming-trips">
      <% @upcoming_trips.drop(1).each do |trip| %>
        <div class="trip-row">
          <span><%= trip.pickup_time.strftime("%a %-d %b %I:%M %p") %></span>
          <span><%= trip.pickup_address.text %> → <%= trip.dropoff_address.text %></span>
        </div>
      <% end %>
    </div>

  <% else %>
    <div class="no-trips">
      <p>No upcoming trips scheduled.</p>
      <p>Call <%= @customer.provider.phone %> to book a ride.</p>
    </div>
  <% end %>

  <footer>
    <a href="tel:<%= @customer.provider.phone %>">
      Call <%= @customer.provider.name %>
    </a>
  </footer>
</div>
```

**`app/javascript/channels/client_eta_channel.js`:**
```javascript
import consumer from "./consumer"
import L from "leaflet"   // loaded from CDN in layout

let map, driverMarker

consumer.subscriptions.create(
  {
    channel: "RunEtaChannel",
    run_id:  document.querySelector(".client-portal")?.dataset?.runId
  },
  {
    received({ ordered_trip_ids, etas, driver_lat, driver_lng }) {
      const tripId  = parseInt(document.querySelector(".client-portal").dataset.tripId)
      const tripIdx = ordered_trip_ids.indexOf(tripId)
      if (tripIdx === -1) return

      // Update ETA display
      const etaSec = etas[tripIdx]
      const etaDate = new Date(etaSec * 1000)
      const etaEl = document.getElementById("eta-time")
      if (etaEl) {
        etaEl.textContent = etaDate.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
      }

      // Show driver on map
      if (driver_lat && driver_lng) {
        const mapEl = document.getElementById("driver-map")
        mapEl.style.display = "block"

        if (!map) {
          map = L.map("driver-map").setView([driver_lat, driver_lng], 14)
          L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png").addTo(map)
          driverMarker = L.marker([driver_lat, driver_lng], {
            icon: L.divIcon({ className: "bus-icon", html: "🚐", iconSize: [32, 32] })
          }).addTo(map)
        } else {
          driverMarker.setLatLng([driver_lat, driver_lng])
          map.panTo([driver_lat, driver_lng])
        }
      }
    }
  }
)
```

**Include driver GPS in the ActionCable broadcast** (update `RealtimeReoptimizeJob`):
```ruby
ActionCable.server.broadcast("run_eta_#{run_id}", {
  ordered_trip_ids: result["ordered_trip_ids"],
  etas:             result["etas"],
  driver_lat:       run.current_vehicle_lat,   # from CAD/AVL GPS feed
  driver_lng:       run.current_vehicle_lng,
  updated_at:       Time.current.iso8601
})
```

**PWA manifest (`app/javascript/pwa/manifest.json`):**
```json
{
  "name": "My Ride",
  "short_name": "My Ride",
  "start_url": "/my-ride",
  "display": "standalone",
  "background_color": "#ffffff",
  "theme_color": "#1a56db",
  "icons": [
    { "src": "/icons/icon-192.png", "sizes": "192x192", "type": "image/png" },
    { "src": "/icons/icon-512.png", "sizes": "512x512", "type": "image/png" }
  ]
}
```

**Service worker (`app/javascript/pwa/service_worker.js`):**
```javascript
const CACHE = "my-ride-v1"
const OFFLINE_URL = "/my-ride/offline"
const STATIC_ASSETS = ["/my-ride", OFFLINE_URL, "/icons/icon-192.png"]

self.addEventListener("install", event => {
  event.waitUntil(
    caches.open(CACHE).then(cache => cache.addAll(STATIC_ASSETS))
  )
})

self.addEventListener("fetch", event => {
  if (event.request.mode === "navigate") {
    event.respondWith(
      fetch(event.request).catch(() => caches.match(OFFLINE_URL))
    )
    return
  }
  event.respondWith(
    caches.match(event.request).then(cached => cached || fetch(event.request))
  )
})
```

**Register service worker in application layout:**
```erb
<%# app/views/layouts/application.html.erb — inside <head> %>
<link rel="manifest" href="/pwa/manifest.json">
<script>
  if ("serviceWorker" in navigator) {
    navigator.serviceWorker.register("/pwa/service_worker.js")
  }
</script>
```

**Routes:**
```ruby
# config/routes.rb
scope "/my-ride" do
  get  "/",        to: "client_portal#show",   as: :client_portal
  get  "/offline", to: "client_portal#offline", as: :client_portal_offline
end
post "/twilio/sms/inbound", to: "twilio_sms#inbound"
```

**Customer model additions:**
```ruby
# migration — also adds portal fields
add_column :customers, :portal_push_enabled, :boolean, default: false

# Optional: Web Push notifications (in addition to SMS) via webpush gem
# Store push subscription JSON in customer record
# Broadcast alongside ActionCable when ETA changes significantly
```

**Accessibility considerations** (paratransit population):
- Minimum 18px body text, 24px for ETA display
- High contrast — WCAG AA minimum, AAA preferred
- All interactive elements ≥ 44×44px touch target
- "Call us" link always visible as primary CTA — not every passenger will use the app
- Screen reader tested: NVDA + Chrome, VoiceOver + Safari iOS

---

## Updated trigger points (all phases)

| Trigger | Behavior | Phase |
|---|---|---|
| Overnight batch — per run | Optimize stop order within each run | 1 — start here |
| Dispatcher "Optimize run" button | Reorder trips in a single run on demand | 1 |
| Trip confirmed | SMS confirmation + portal link sent to passenger | 1 |
| Overnight batch — fleet | Cross-run trip reassignment | 2 |
| On trip booking | Suggest best run + insert position | 2 |
| Morning ETA window | SMS with arrival window after overnight optimization | 2 |
| Day-before reminder | SMS reminder at 6 PM evening prior | 2 |
| Live re-optimization | Driver late / no-show, push updated ETAs via WebSocket | 3 |
| Vehicle approaching | SMS when driver ≤ 0.5 miles away | 3 |
| Schedule change | SMS when optimizer shifts ETA >5 min | 3 |
| Client PWA | Live driver map + ETA in passenger's browser | 3 |
| CuOpt migration | Swap solver backend for SaaS scale | 4 (SaaS only) |
| ML travel times | Use learned correction model | 4 |
| Soft constraints | Priority weighting, preferred drivers | 3–4 |


---

*Generated from Claude conversation — March 2026*
*Context: GCRPC Victoria TX paratransit scheduling improvement*
