from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from solver import solve_run, solve_fleet
import logging

logger = logging.getLogger(__name__)
app = FastAPI(title="RidePilot Route Optimizer")


class Trip(BaseModel):
    trip_id: int
    pickup_lat: float
    pickup_lng: float
    dropoff_lat: float
    dropoff_lng: float
    earliest_pickup: int                 # seconds from midnight
    latest_pickup: int                   # seconds from midnight
    seats: int                           # ambulatory seats required
    tie_downs: int                       # wheelchair tie-down spaces required
    latest_dropoff: int | None = None    # appointment time, seconds from midnight
    max_ride: int | None = None          # seconds on board; default from the ride policy below


class RidePolicy(BaseModel):
    service_seconds: int = 120           # boarding time at each pickup and drop-off
    max_ride_factor: float = 1.5         # max ride = max(direct * factor, direct + extra)
    max_ride_extra: int = 1200           # seconds


class OptimizeRequest(RidePolicy):
    run_id: int
    vehicle_capacity_seats: int
    vehicle_capacity_tie_downs: int
    depot_lat: float | None = None
    depot_lng: float | None = None
    earliest_start: int | None = None    # run hours, seconds from midnight
    latest_end: int | None = None
    trips: list[Trip]


class Stop(BaseModel):
    trip_id: int
    kind: str                            # pickup | dropoff
    eta: int                             # seconds from midnight


class OptimizeResponse(BaseModel):
    run_id: int
    stops: list[Stop]                    # full sequence, pickups and drop-offs interleaved
    ordered_trip_ids: list[int]          # pickup order (older callers)
    etas: list[int]                      # parallel to ordered_trip_ids
    unassigned_trip_ids: list[int]
    max_ride_seconds: dict[int, int]
    start: int | None
    end: int | None
    total_distance_m: float
    total_drive_seconds: int
    solver_status: str                   # success | partial (some trips left out) | fail


class VehicleSpec(BaseModel):
    run_id: int
    capacity_seats: int
    capacity_tie_downs: int
    depot_lat: float
    depot_lng: float
    earliest_start: int                  # seconds from midnight
    latest_end: int                      # seconds from midnight


class FleetOptimizeRequest(RidePolicy):
    provider_id: int
    date: str                            # YYYY-MM-DD
    vehicles: list[VehicleSpec]
    trips: list[Trip]


class TripAssignment(BaseModel):
    trip_id: int
    run_id: int
    position: int
    eta: int


class RunRoute(BaseModel):
    run_id: int
    stops: list[Stop]
    start: int | None
    end: int | None
    distance_m: float
    drive_seconds: int


class FleetOptimizeResponse(BaseModel):
    provider_id: int
    runs: list[RunRoute]
    assignments: list[TripAssignment]    # pickup order per run (older callers)
    unassigned_trip_ids: list[int]
    total_distance_m: float
    total_drive_seconds: int
    solver_status: str


@app.post("/optimize/run", response_model=OptimizeResponse)
def optimize_run_endpoint(req: OptimizeRequest):
    if not req.trips:
        raise HTTPException(status_code=400, detail="No trips provided")
    try:
        result = solve_run(req)
        return result
    except Exception as e:
        logger.exception("Solver error for run %s", req.run_id)
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/optimize/fleet", response_model=FleetOptimizeResponse)
def optimize_fleet_endpoint(req: FleetOptimizeRequest):
    if not req.trips:
        raise HTTPException(status_code=400, detail="No trips provided")
    if not req.vehicles:
        raise HTTPException(status_code=400, detail="No vehicles provided")
    try:
        result = solve_fleet(req)
        return result
    except Exception as e:
        logger.exception("Solver error for fleet provider %s", req.provider_id)
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/health")
def health():
    return {"status": "ok"}
