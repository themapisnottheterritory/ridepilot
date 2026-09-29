"""Pickup-and-delivery routing for demand-response runs (OR-Tools over OSRM).

One model serves both endpoints: a single run (one vehicle) and a fleet (one
vehicle per run). Rules, all hard unless a trip is left unassigned:

  - each pickup inside its window [earliest_pickup, latest_pickup];
  - each drop-off no later than latest_dropoff (the appointment time) when set;
  - a rider is on board no longer than their max ride: max_ride if the trip
    sends one, else max(direct * max_ride_factor, direct + max_ride_extra);
  - service_seconds of boarding at every pickup and drop-off;
  - seats and wheelchair tie-downs within the vehicle's capacity;
  - the vehicle leaves and returns to its depot inside [earliest_start, latest_end].

A trip that cannot be served under those rules is left out and reported in
unassigned_trip_ids (with a high penalty, so the solver only does it when it
must) instead of failing the whole run. The result carries the full stop
sequence per vehicle, pickups and drop-offs interleaved, which is what a
shared-ride manifest needs; ordered_trip_ids / etas are kept for older callers.

Rewritten 2026-09-28: the first version had no drop-off deadline, no ride-time
limit and no boarding time (so it kept riders on board for hours to save
miles), returned only the pickup order, and grouped each trip's pickup and
drop-off into one disjunction in the fleet model, which conflicts with the
pickup-delivery pairing and crashed the service with std::bad_alloc.
"""
from ortools.constraint_solver import routing_enums_pb2, pywrapcp

from travel_time import build_matrices

HORIZON = 86400          # seconds in a day
DROP_PENALTY = 1_000_000  # cost of leaving a trip unassigned (>> any route's seconds)


def _max_ride(trip, direct, req):
    if getattr(trip, "max_ride", None):
        return int(trip.max_ride)
    return int(max(direct * req.max_ride_factor, direct + req.max_ride_extra))


def _solve(trips, vehicles, req, time_limit):
    """trips: Trip models; vehicles: list of dicts with capacity_seats,
    capacity_tie_downs, depot_lat, depot_lng, earliest_start, latest_end."""
    n, v = len(trips), len(vehicles)
    coords = ([(t.pickup_lat, t.pickup_lng) for t in trips]
              + [(t.dropoff_lat, t.dropoff_lng) for t in trips]
              + [(veh["depot_lat"], veh["depot_lng"]) for veh in vehicles])
    T, D = build_matrices(coords)
    depots = [2 * n + i for i in range(v)]
    service = int(req.service_seconds)

    manager = pywrapcp.RoutingIndexManager(2 * n + v, v, depots, depots)
    routing = pywrapcp.RoutingModel(manager)

    def is_stop(node):
        return node < 2 * n

    def transit(from_idx, to_idx):
        a, b = manager.IndexToNode(from_idx), manager.IndexToNode(to_idx)
        return T[a][b] + (service if is_stop(a) else 0)

    transit_idx = routing.RegisterTransitCallback(transit)
    routing.SetArcCostEvaluatorOfAllVehicles(transit_idx)
    # Slack = waiting at a stop; a day-long run can wait hours between trips.
    routing.AddDimension(transit_idx, HORIZON, HORIZON, False, "Time")
    time_dim = routing.GetDimensionOrDie("Time")

    for vi, veh in enumerate(vehicles):
        lo, hi = int(veh["earliest_start"]), int(veh["latest_end"])
        time_dim.CumulVar(routing.Start(vi)).SetRange(lo, hi)
        time_dim.CumulVar(routing.End(vi)).SetRange(lo, hi)
        routing.AddVariableMinimizedByFinalizer(time_dim.CumulVar(routing.Start(vi)))
        routing.AddVariableMinimizedByFinalizer(time_dim.CumulVar(routing.End(vi)))

    for key, caps in (("seats", [int(veh["capacity_seats"]) for veh in vehicles]),
                      ("tie_downs", [int(veh["capacity_tie_downs"]) for veh in vehicles])):
        def demand(idx, key=key):
            node = manager.IndexToNode(idx)
            if node < n:
                return getattr(trips[node], key)
            if node < 2 * n:
                return -getattr(trips[node - n], key)
            return 0
        routing.AddDimensionWithVehicleCapacity(routing.RegisterUnaryTransitCallback(demand), 0, caps, True, key)

    solver = routing.solver()
    limits = {}
    for i, t in enumerate(trips):
        p, d = manager.NodeToIndex(i), manager.NodeToIndex(i + n)
        routing.AddPickupAndDelivery(p, d)
        solver.Add(routing.VehicleVar(p) == routing.VehicleVar(d))
        time_dim.CumulVar(p).SetRange(int(t.earliest_pickup), int(t.latest_pickup))
        latest_drop = int(t.latest_dropoff) if getattr(t, "latest_dropoff", None) else HORIZON
        time_dim.CumulVar(d).SetRange(int(t.earliest_pickup), latest_drop)
        ride = _max_ride(t, T[i][i + n], req)
        limits[t.trip_id] = ride
        # on board from the start of boarding at pickup to arrival at drop-off
        solver.Add(time_dim.CumulVar(d) - time_dim.CumulVar(p) <= ride + service)
        # A trip may be left out, but only as a pair: pickup and drop-off each
        # get their own disjunction (one shared disjunction allows at most one
        # of the two, which contradicts the pairing above).
        routing.AddDisjunction([p], DROP_PENALTY)
        routing.AddDisjunction([d], DROP_PENALTY)
        routing.AddVariableMinimizedByFinalizer(time_dim.CumulVar(p))
        routing.AddVariableMinimizedByFinalizer(time_dim.CumulVar(d))

    params = pywrapcp.DefaultRoutingSearchParameters()
    params.first_solution_strategy = routing_enums_pb2.FirstSolutionStrategy.PARALLEL_CHEAPEST_INSERTION
    params.local_search_metaheuristic = routing_enums_pb2.LocalSearchMetaheuristic.GUIDED_LOCAL_SEARCH
    params.time_limit.seconds = time_limit
    solution = routing.SolveWithParameters(params)
    if not solution:
        return None, limits

    routes = []
    for vi in range(v):
        idx, stops, meters, drive = routing.Start(vi), [], 0.0, 0
        start = solution.Min(time_dim.CumulVar(idx))
        prev = manager.IndexToNode(idx)
        idx = solution.Value(routing.NextVar(idx))
        while not routing.IsEnd(idx):
            node = manager.IndexToNode(idx)
            meters += D[prev][node]; drive += T[prev][node]
            trip = trips[node] if node < n else trips[node - n]
            stops.append({"trip_id": trip.trip_id, "kind": "pickup" if node < n else "dropoff",
                          "eta": solution.Min(time_dim.CumulVar(idx))})
            prev = node
            idx = solution.Value(routing.NextVar(idx))
        meters += D[prev][manager.IndexToNode(idx)]; drive += T[prev][manager.IndexToNode(idx)]
        routes.append({"stops": stops, "start": start, "end": solution.Min(time_dim.CumulVar(idx)),
                       "distance_m": round(meters, 1), "drive_seconds": drive})
    return routes, limits


def _status(routing_found, unassigned):
    if not routing_found:
        return "fail"
    return "success" if not unassigned else "partial"


def solve_run(req):
    trips = req.trips
    depot_lat = req.depot_lat if req.depot_lat is not None else trips[0].pickup_lat
    depot_lng = req.depot_lng if req.depot_lng is not None else trips[0].pickup_lng
    vehicle = {"capacity_seats": req.vehicle_capacity_seats, "capacity_tie_downs": req.vehicle_capacity_tie_downs,
               "depot_lat": depot_lat, "depot_lng": depot_lng,
               "earliest_start": req.earliest_start if req.earliest_start is not None else 0,
               "latest_end": req.latest_end if req.latest_end is not None else HORIZON}
    routes, limits = _solve(trips, [vehicle], req, time_limit=10)
    route = routes[0] if routes else {"stops": [], "start": None, "end": None, "distance_m": 0.0, "drive_seconds": 0}
    served = {s["trip_id"] for s in route["stops"]}
    unassigned = [t.trip_id for t in trips if t.trip_id not in served]
    pickups = [s for s in route["stops"] if s["kind"] == "pickup"]
    return {
        "run_id": req.run_id,
        "stops": route["stops"],
        "ordered_trip_ids": [s["trip_id"] for s in pickups],
        "etas": [s["eta"] for s in pickups],
        "unassigned_trip_ids": unassigned,
        "max_ride_seconds": limits,
        "start": route["start"], "end": route["end"],
        "total_distance_m": route["distance_m"],
        "total_drive_seconds": route["drive_seconds"],
        "solver_status": _status(routes is not None, unassigned),
    }


def solve_fleet(req):
    vehicles = [veh.model_dump() for veh in req.vehicles]
    routes, limits = _solve(req.trips, vehicles, req, time_limit=30)
    runs, served = [], set()
    for veh, route in zip(req.vehicles, routes or []):
        served |= {s["trip_id"] for s in route["stops"]}
        runs.append({"run_id": veh.run_id, **route})
    unassigned = [t.trip_id for t in req.trips if t.trip_id not in served]
    assignments = []
    for r in runs:
        for pos, s in enumerate(x for x in r["stops"] if x["kind"] == "pickup"):
            assignments.append({"trip_id": s["trip_id"], "run_id": r["run_id"], "position": pos, "eta": s["eta"]})
    return {
        "provider_id": req.provider_id,
        "runs": runs,
        "assignments": assignments,
        "unassigned_trip_ids": unassigned,
        "total_distance_m": round(sum(r["distance_m"] for r in runs), 1),
        "total_drive_seconds": sum(r["drive_seconds"] for r in runs),
        "solver_status": _status(routes is not None, unassigned),
    }
