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


def build_matrices(coords: list[tuple[float, float]]) -> tuple[list[list[int]], list[list[float]]]:
    """
    OSRM /table: (durations in seconds, distances in meters), NxN. Falls back
    to straight-line estimates (30 km/h) if OSRM is unavailable.
    """
    try:
        coord_str = ";".join(f"{lng},{lat}" for lat, lng in coords)
        resp = httpx.get(
            f"{OSRM_URL}/table/v1/driving/{coord_str}",
            params={"annotations": "duration,distance"},
            timeout=15.0,
        )
        resp.raise_for_status()
        data = resp.json()
        durations = [[int(v or 0) for v in row] for row in data["durations"]]
        distances = [[float(v or 0) for v in row] for row in data["distances"]]
        return durations, distances
    except Exception:
        n = len(coords)
        distances = [[_haversine_m(coords[i], coords[j]) if i != j else 0.0 for j in range(n)] for i in range(n)]
        return _euclidean_matrix(coords), distances


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
