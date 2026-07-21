from ortools.constraint_solver import routing_enums_pb2, pywrapcp
from travel_time import build_time_matrix


def solve_run(req):
    trips = req.trips
    n = len(trips)

    # Node layout: 0..n-1 = pickups, n..2n-1 = dropoffs, 2n = depot
    depot = 2 * n
    num_nodes = 2 * n + 1

    # Build coordinate list for travel time matrix
    # Use depot coords if provided, otherwise use first pickup as depot
    depot_lat = req.depot_lat if req.depot_lat else trips[0].pickup_lat
    depot_lng = req.depot_lng if req.depot_lng else trips[0].pickup_lng

    coords = (
        [(t.pickup_lat, t.pickup_lng) for t in trips]
        + [(t.dropoff_lat, t.dropoff_lng) for t in trips]
        + [(depot_lat, depot_lng)]
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
        # Dropoff: must be after pickup (no explicit window -- just precedence)
        dropoff_idx = manager.NodeToIndex(i + n)
        time_dim.CumulVar(dropoff_idx).SetRange(trip.earliest_pickup, max_time)

    # Capacity dimensions -- seats
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

    # Capacity dimensions -- tie-downs
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
    params.time_limit.seconds = 10  # max 10s per run

    solution = routing.SolveWithParameters(params)

    if not solution:
        raise RuntimeError(f"No feasible solution found for run {req.run_id}")

    # Extract ordered route
    ordered_trip_ids = []
    etas = []
    index = routing.Start(0)
    while not routing.IsEnd(index):
        node = manager.IndexToNode(index)
        if node < n:  # pickup node -- record trip order by pickup sequence
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


def solve_fleet(req):
    """
    Multi-vehicle fleet optimization: assigns trips across runs and sequences them.
    Each run becomes a vehicle with its own capacity and depot.
    """
    trips = req.trips
    vehicles = req.vehicles
    n = len(trips)
    v = len(vehicles)

    # Node layout: 0..n-1 = pickups, n..2n-1 = dropoffs, 2n..2n+v-1 = depots
    num_nodes = 2 * n + v

    # Build coordinate list
    coords = (
        [(t.pickup_lat, t.pickup_lng) for t in trips]
        + [(t.dropoff_lat, t.dropoff_lng) for t in trips]
        + [(veh.depot_lat, veh.depot_lng) for veh in vehicles]
    )
    time_matrix = build_time_matrix(coords)

    # Each vehicle starts and ends at its own depot
    starts = [2 * n + i for i in range(v)]
    ends = [2 * n + i for i in range(v)]

    manager = pywrapcp.RoutingIndexManager(num_nodes, v, starts, ends)
    routing = pywrapcp.RoutingModel(manager)

    # Time callback
    def time_callback(from_idx, to_idx):
        return time_matrix[manager.IndexToNode(from_idx)][manager.IndexToNode(to_idx)]

    transit_idx = routing.RegisterTransitCallback(time_callback)
    routing.SetArcCostEvaluatorOfAllVehicles(transit_idx)

    # Time window dimension
    max_time = 86400
    boarding_slack = 120
    routing.AddDimension(transit_idx, boarding_slack, max_time, False, "Time")
    time_dim = routing.GetDimensionOrDie("Time")

    # Vehicle start/end time windows
    for vi in range(v):
        start_idx = routing.Start(vi)
        end_idx = routing.End(vi)
        time_dim.CumulVar(start_idx).SetRange(vehicles[vi].earliest_start, vehicles[vi].latest_end)
        time_dim.CumulVar(end_idx).SetRange(vehicles[vi].earliest_start, vehicles[vi].latest_end)

    # Trip time windows
    for i, trip in enumerate(trips):
        pickup_idx = manager.NodeToIndex(i)
        time_dim.CumulVar(pickup_idx).SetRange(trip.earliest_pickup, trip.latest_pickup)
        dropoff_idx = manager.NodeToIndex(i + n)
        time_dim.CumulVar(dropoff_idx).SetRange(trip.earliest_pickup, max_time)

    # Seat capacity per vehicle
    def seat_callback(idx):
        node = manager.IndexToNode(idx)
        if node < n:
            return trips[node].seats
        elif node < 2 * n:
            return -trips[node - n].seats
        return 0

    seat_idx = routing.RegisterUnaryTransitCallback(seat_callback)
    routing.AddDimensionWithVehicleCapacity(
        seat_idx, 0, [veh.capacity_seats for veh in vehicles], True, "Seats"
    )

    # Tie-down capacity per vehicle
    def tiedown_callback(idx):
        node = manager.IndexToNode(idx)
        if node < n:
            return trips[node].tie_downs
        elif node < 2 * n:
            return -trips[node - n].tie_downs
        return 0

    tiedown_idx = routing.RegisterUnaryTransitCallback(tiedown_callback)
    routing.AddDimensionWithVehicleCapacity(
        tiedown_idx, 0, [veh.capacity_tie_downs for veh in vehicles], True, "TieDowns"
    )

    # Pickup-delivery constraints
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

    # Allow dropping trips with a high penalty (prefer assigning all)
    drop_penalty = 100000
    for i in range(n):
        routing.AddDisjunction([manager.NodeToIndex(i), manager.NodeToIndex(i + n)], drop_penalty)

    # Search parameters
    params = pywrapcp.DefaultRoutingSearchParameters()
    params.first_solution_strategy = routing_enums_pb2.FirstSolutionStrategy.PARALLEL_CHEAPEST_INSERTION
    params.local_search_metaheuristic = routing_enums_pb2.LocalSearchMetaheuristic.GUIDED_LOCAL_SEARCH
    params.time_limit.seconds = 30  # more time for multi-vehicle

    solution = routing.SolveWithParameters(params)

    if not solution:
        raise RuntimeError(f"No feasible solution found for fleet provider {req.provider_id}")

    # Extract assignments per vehicle
    assignments = []
    unassigned_trip_ids = []
    assigned_trip_set = set()

    for vi in range(v):
        run_id = vehicles[vi].run_id
        position = 0
        index = routing.Start(vi)
        while not routing.IsEnd(index):
            node = manager.IndexToNode(index)
            if node < n:  # pickup node
                trip_id = trips[node].trip_id
                eta = solution.Value(time_dim.CumulVar(index))
                assignments.append({
                    "trip_id": trip_id,
                    "run_id": run_id,
                    "position": position,
                    "eta": eta,
                })
                assigned_trip_set.add(trip_id)
                position += 1
            index = solution.Value(routing.NextVar(index))

    # Find unassigned trips
    for trip in trips:
        if trip.trip_id not in assigned_trip_set:
            unassigned_trip_ids.append(trip.trip_id)

    status_map = {0: "not_solved", 1: "success", 2: "fail", 3: "fail", 4: "fail"}

    return {
        "provider_id": req.provider_id,
        "assignments": assignments,
        "unassigned_trip_ids": unassigned_trip_ids,
        "total_distance_m": float(solution.ObjectiveValue()),
        "solver_status": status_map.get(routing.status(), "unknown"),
    }
