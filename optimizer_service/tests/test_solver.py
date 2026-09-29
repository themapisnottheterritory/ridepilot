"""Solver rules on a toy map: points on a line, 60 s per unit of distance.

  docker run --rm -v "$PWD/optimizer_service:/app" -w /app ridepilot_optimizer python -m unittest -v
"""
import unittest
from unittest import mock

import solver
from main import FleetOptimizeRequest, OptimizeRequest, Trip, VehicleSpec

UNIT = 60  # seconds per unit


def fake_matrices(coords):
    xs = [lat for lat, _ in coords]           # position = latitude, longitude ignored
    T = [[int(abs(a - b) * UNIT) for b in xs] for a in xs]
    D = [[abs(a - b) * 1000.0 for b in xs] for a in xs]
    return T, D


def trip(tid, frm, to, pickup_min, window=(5, 10), **kw):
    t = pickup_min * 60
    return Trip(trip_id=tid, pickup_lat=frm, pickup_lng=0, dropoff_lat=to, dropoff_lng=0,
                earliest_pickup=t - window[0] * 60, latest_pickup=t + window[1] * 60, seats=1, tie_downs=0, **kw)


def run(trips, **kw):
    base = dict(run_id=1, vehicle_capacity_seats=8, vehicle_capacity_tie_downs=2, depot_lat=0, depot_lng=0,
                earliest_start=0, latest_end=86400, service_seconds=0, trips=trips)
    base.update(kw)
    return solver.solve_run(OptimizeRequest(**base))


def order(result):
    return [(s["kind"][0], s["trip_id"]) for s in result["stops"]]


@mock.patch.object(solver, "build_matrices", side_effect=fake_matrices)
class SolveRunTest(unittest.TestCase):
    def test_every_trip_has_pickup_before_dropoff_in_the_full_sequence(self, _):
        r = run([trip(1, 10, 20, 480), trip(2, 12, 22, 482), trip(3, 30, 5, 540)])
        self.assertEqual(r["solver_status"], "success")
        seq = order(r)
        self.assertEqual(len(seq), 6)
        for tid in (1, 2, 3):
            self.assertLess(seq.index(("p", tid)), seq.index(("d", tid)))
        self.assertEqual(r["ordered_trip_ids"], [s["trip_id"] for s in r["stops"] if s["kind"] == "pickup"])

    def test_riders_going_the_same_way_share_the_bus(self, _):
        # both from ~10 to ~20 at the same time: both on board together beats two separate legs
        r = run([trip(1, 10, 20, 480), trip(2, 11, 21, 480)])
        kinds = [k for k, _ in order(r)]
        self.assertEqual(kinds, ["p", "p", "d", "d"])

    def test_max_ride_stops_a_long_detour(self, _):
        # rider 1 goes 10 -> 12 (2 min direct, limit max(3, 22) = 22 min). Carrying them
        # out to 40 and back first would save nothing for them and blow the limit.
        r = run([trip(1, 10, 12, 480, window=(0, 0)), trip(2, 11, 40, 481, window=(0, 60))], max_ride_extra=1200)
        on_board = {}
        for s in r["stops"]:
            on_board.setdefault(s["trip_id"], {})[s["kind"]] = s["eta"]
        self.assertLessEqual(on_board[1]["dropoff"] - on_board[1]["pickup"], r["max_ride_seconds"][1])
        self.assertLessEqual(on_board[1]["dropoff"] - on_board[1]["pickup"], 22 * 60)

    def test_appointment_is_a_deadline(self, _):
        # pickup 8:00 at 10, appointment 8:25 at 30 (20 min away). The solver may not
        # wander off with the rider first.
        t = trip(1, 10, 30, 480, latest_dropoff=505 * 60)
        r = run([t, trip(2, 60, 70, 481, window=(0, 120))])
        drop = next(s["eta"] for s in r["stops"] if s["trip_id"] == 1 and s["kind"] == "dropoff")
        self.assertLessEqual(drop, 505 * 60)

    def test_impossible_trip_is_reported_not_fatal(self, _):
        # appointment 5 minutes after pickup for a 20-minute ride: cannot be served
        r = run([trip(1, 10, 30, 480, window=(0, 0), latest_dropoff=485 * 60), trip(2, 12, 14, 490)])
        self.assertEqual(r["solver_status"], "partial")
        self.assertEqual(r["unassigned_trip_ids"], [1])
        self.assertEqual(order(r), [("p", 2), ("d", 2)])

    def test_run_hours_bound_the_route(self, _):
        # run starts 8:00 at the depot (0); a 7:00 pickup at 10 cannot be reached
        r = run([trip(1, 10, 20, 420, window=(0, 10)), trip(2, 10, 20, 540)], earliest_start=480 * 60, latest_end=1020 * 60)
        self.assertEqual(r["unassigned_trip_ids"], [1])
        self.assertGreaterEqual(r["start"], 480 * 60)

    def test_boarding_time_pushes_the_next_stop(self, _):
        r = run([trip(1, 10, 20, 480, window=(0, 30))], service_seconds=120)
        pick, drop = r["stops"][0]["eta"], r["stops"][1]["eta"]
        self.assertEqual(drop - pick, 10 * UNIT + 120)

    def test_capacity(self, _):
        trips = [trip(i, 10, 20, 480, window=(0, 60)) for i in range(1, 4)]
        r = run(trips, vehicle_capacity_seats=2)
        peak, on = 0, 0
        for s in r["stops"]:
            on += 1 if s["kind"] == "pickup" else -1
            peak = max(peak, on)
        self.assertLessEqual(peak, 2)
        self.assertEqual(r["solver_status"], "success")


@mock.patch.object(solver, "build_matrices", side_effect=fake_matrices)
class SolveFleetTest(unittest.TestCase):
    def fleet(self, trips, n_vehicles=2):
        vehicles = [VehicleSpec(run_id=100 + i, capacity_seats=8, capacity_tie_downs=2, depot_lat=0, depot_lng=0,
                                earliest_start=0, latest_end=86400) for i in range(n_vehicles)]
        return solver.solve_fleet(FleetOptimizeRequest(provider_id=1, date="2026-10-01", vehicles=vehicles,
                                                       trips=trips, service_seconds=0))

    def test_two_trips_one_vehicle_does_not_crash_and_assigns_both(self, _):
        # the old model's shared disjunction made this request exhaust memory
        r = self.fleet([trip(1, 10, 20, 480), trip(2, 30, 40, 600)], n_vehicles=1)
        self.assertEqual(r["solver_status"], "success")
        self.assertEqual(r["unassigned_trip_ids"], [])

    def test_simultaneous_trips_far_apart_go_on_different_buses(self, _):
        r = self.fleet([trip(1, 10, 12, 480, window=(0, 5)), trip(2, 90, 92, 480, window=(0, 5))])
        self.assertEqual(r["unassigned_trip_ids"], [])
        runs_used = {a["run_id"] for a in r["assignments"]}
        self.assertEqual(len(runs_used), 2)
        for route in r["runs"]:
            kinds = {}
            for s in route["stops"]:
                kinds.setdefault(s["trip_id"], set()).add(s["kind"])
            self.assertTrue(all(k == {"pickup", "dropoff"} for k in kinds.values()))


if __name__ == "__main__":
    unittest.main()
