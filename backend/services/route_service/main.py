"""
Route Optimization Service — Graph-based shortest path with multi-constraint support.
Uses Dijkstra's algorithm on a weighted logistics graph.
"""

import json
import heapq
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

# ─── Load route graph from sample data ────────────────────────────────────────

DATA_PATH = Path(__file__).resolve().parents[3] / "data" / "sample" / "routes.json"

with open(DATA_PATH) as f:
    _raw = json.load(f)

# Build adjacency list (bidirectional)
_graph: dict[str, list[dict]] = {}
for city in _raw["cities"]:
    _graph[city] = []

for edge in _raw["edges"]:
    _graph[edge["from"]].append({
        "to": edge["to"],
        "distance_km": edge["distance_km"],
        "time_hours": edge["time_hours"],
        "cost_factor": edge.get("cost_factor", 1.0),
        "risk_factor": edge.get("risk_factor", 1.0),
    })
    _graph[edge["to"]].append({
        "to": edge["from"],
        "distance_km": edge["distance_km"],
        "time_hours": edge["time_hours"],
        "cost_factor": edge.get("cost_factor", 1.0),
        "risk_factor": edge.get("risk_factor", 1.0),
    })


# ─── Models ───────────────────────────────────────────────────────────────────

class RouteRequest(BaseModel):
    origin: str
    destination: str
    optimize_for: str = Field("distance", description="distance | time | cost | balanced")
    max_results: int = Field(3, ge=1, le=5)
    max_stops: int = Field(6, ge=2, le=10)


class RouteOption(BaseModel):
    route_id: str
    waypoints: list[str]
    total_distance_km: float
    total_time_hours: float
    total_cost_factor: float
    total_risk_factor: float


class RouteResponse(BaseModel):
    origin: str
    destination: str
    options: list[RouteOption]
    optimize_for: str


# ─── Route computation ───────────────────────────────────────────────────────

def _edge_weight(edge: dict, optimize_for: str) -> float:
    """Compute edge weight based on optimization objective."""
    if optimize_for == "distance":
        return edge["distance_km"]
    elif optimize_for == "time":
        return edge["time_hours"]
    elif optimize_for == "cost":
        return edge["distance_km"] * edge["cost_factor"]
    else:  # balanced
        return (
            0.4 * edge["distance_km"]
            + 0.3 * edge["time_hours"] * 60  # normalize hours to comparable scale
            + 0.2 * edge["distance_km"] * edge["cost_factor"]
            + 0.1 * edge["distance_km"] * edge["risk_factor"]
        )


def find_k_shortest_paths(
    origin: str,
    destination: str,
    k: int = 3,
    optimize_for: str = "distance",
    max_stops: int = 6,
) -> list[dict]:
    """
    Yen's K-shortest paths algorithm adapted for logistics graph.
    Returns top-K paths ranked by the specified optimization criterion.
    """
    if origin not in _graph or destination not in _graph:
        return []

    # Dijkstra for single shortest path
    def dijkstra(source: str, target: str, excluded_edges: set = None) -> Optional[dict]:
        if excluded_edges is None:
            excluded_edges = set()

        dist = {city: float("inf") for city in _graph}
        dist[source] = 0
        prev = {city: None for city in _graph}
        pq = [(0, source)]
        visited = set()

        while pq:
            d, u = heapq.heappop(pq)
            if u in visited:
                continue
            visited.add(u)
            if u == target:
                break

            for edge in _graph.get(u, []):
                v = edge["to"]
                edge_key = (u, v)
                if edge_key in excluded_edges or v in visited:
                    continue
                w = _edge_weight(edge, optimize_for)
                if dist[u] + w < dist[v]:
                    dist[v] = dist[u] + w
                    prev[v] = u
                    heapq.heappush(pq, (dist[v], v))

        if dist[target] == float("inf"):
            return None

        # Reconstruct path
        path = []
        node = target
        while node:
            path.append(node)
            node = prev[node]
        path.reverse()

        if len(path) > max_stops:
            return None

        return {"path": path, "weight": dist[target]}

    # Find first shortest path
    first = dijkstra(origin, destination)
    if not first:
        return []

    A = [first]  # List of shortest paths
    B = []  # Candidates

    for i in range(1, k):
        for j in range(len(A[-1]["path"]) - 1):
            spur_node = A[-1]["path"][j]
            root_path = A[-1]["path"][:j + 1]

            excluded = set()
            for path_info in A:
                p = path_info["path"]
                if p[:j + 1] == root_path and j + 1 < len(p):
                    excluded.add((p[j], p[j + 1]))

            spur_result = dijkstra(spur_node, destination, excluded)
            if spur_result:
                total_path = root_path[:-1] + spur_result["path"]
                if len(total_path) <= max_stops:
                    # Recalculate weight for total path
                    total_weight = 0
                    for idx in range(len(total_path) - 1):
                        for edge in _graph.get(total_path[idx], []):
                            if edge["to"] == total_path[idx + 1]:
                                total_weight += _edge_weight(edge, optimize_for)
                                break
                    candidate = {"path": total_path, "weight": total_weight}
                    if candidate not in B:
                        B.append(candidate)

        if not B:
            break

        B.sort(key=lambda x: x["weight"])
        best = B.pop(0)
        if best not in A:
            A.append(best)

    return A


def compute_route_metrics(waypoints: list[str]) -> dict:
    """Compute total distance, time, cost, and risk for a route."""
    total_dist = 0
    total_time = 0
    total_cost = 0
    total_risk = 0

    for i in range(len(waypoints) - 1):
        for edge in _graph.get(waypoints[i], []):
            if edge["to"] == waypoints[i + 1]:
                total_dist += edge["distance_km"]
                total_time += edge["time_hours"]
                total_cost += edge["distance_km"] * edge["cost_factor"]
                total_risk += edge["distance_km"] * edge["risk_factor"]
                break

    return {
        "total_distance_km": round(total_dist, 1),
        "total_time_hours": round(total_time, 1),
        "total_cost_factor": round(total_cost / max(total_dist, 1), 3),
        "total_risk_factor": round(total_risk / max(total_dist, 1), 3),
    }


# ─── FastAPI App ──────────────────────────────────────────────────────────────

app = FastAPI(
    title="Route Optimization Service",
    description="Graph-based route optimization with Dijkstra/Yen's K-shortest paths",
    version="1.0.0",
)


@app.get("/health")
async def health():
    return {"status": "healthy", "service": "route_service", "cities": len(_graph)}


@app.get("/cities")
async def list_cities():
    """List all available cities in the logistics network."""
    return {"cities": sorted(_graph.keys()), "total": len(_graph)}


@app.post("/route/optimize", response_model=RouteResponse)
async def optimize_route(request: RouteRequest):
    """
    Find optimal routes between origin and destination.
    Returns top-K routes ranked by the specified optimization criterion.
    """
    if request.origin not in _graph:
        raise HTTPException(404, f"Origin city '{request.origin}' not found in network")
    if request.destination not in _graph:
        raise HTTPException(404, f"Destination city '{request.destination}' not found in network")
    if request.origin == request.destination:
        raise HTTPException(400, "Origin and destination must be different")

    paths = find_k_shortest_paths(
        origin=request.origin,
        destination=request.destination,
        k=request.max_results,
        optimize_for=request.optimize_for,
        max_stops=request.max_stops,
    )

    if not paths:
        raise HTTPException(404, f"No route found from {request.origin} to {request.destination}")

    options = []
    for idx, path_info in enumerate(paths):
        metrics = compute_route_metrics(path_info["path"])
        options.append(RouteOption(
            route_id=f"RT-{idx + 1:03d}",
            waypoints=path_info["path"],
            **metrics,
        ))

    return RouteResponse(
        origin=request.origin,
        destination=request.destination,
        options=options,
        optimize_for=request.optimize_for,
    )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8002)
