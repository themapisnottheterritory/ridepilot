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
    earliest_pickup: int    # seconds from midnight
    latest_pickup: int      # seconds from midnight
    seats: int              # number of ambulatory seats required
    tie_downs: int          # number of wheelchair tie-down spaces required


class OptimizeRequest(BaseModel):
    run_id: int
    vehicle_capacity_seats: int
    vehicle_capacity_tie_downs: int
    depot_lat: float | None = None
    depot_lng: float | None = None
    trips: list[Trip]


class OptimizeResponse(BaseModel):
    run_id: int
    ordered_trip_ids: list[int]
    etas: list[int]          # seconds from midnight, parallel to ordered_trip_ids
    total_distance_m: float
    solver_status: str


class VehicleSpec(BaseModel):
    run_id: int
    capacity_seats: int
    capacity_tie_downs: int
    depot_lat: float
    depot_lng: float
    earliest_start: int     # seconds from midnight
    latest_end: int         # seconds from midnight


class FleetOptimizeRequest(BaseModel):
    provider_id: int
    date: str               # YYYY-MM-DD
    vehicles: list[VehicleSpec]
    trips: list[Trip]


class TripAssignment(BaseModel):
    trip_id: int
    run_id: int
    position: int
    eta: int                # seconds from midnight


class FleetOptimizeResponse(BaseModel):
    provider_id: int
    assignments: list[TripAssignment]
    unassigned_trip_ids: list[int]
    total_distance_m: float
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
