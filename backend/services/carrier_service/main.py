"""
Carrier Selection Service — Multi-objective carrier scoring and ranking.
Score = w1×(cost) + w2×(reliability) + w3×(availability) + w4×(ETA)
"""

import json
from pathlib import Path

from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel, Field

# ─── Load carrier data ────────────────────────────────────────────────────────

DATA_PATH = Path(__file__).resolve().parents[3] / "data" / "sample" / "carriers.json"

with open(DATA_PATH) as f:
    _carriers_raw = json.load(f)

_carriers = {c["carrier_id"]: c for c in _carriers_raw}


# ─── Models ───────────────────────────────────────────────────────────────────

class ScoredCarrier(BaseModel):
    carrier_id: str
    name: str
    fleet_type: list[str]
    cost_per_km: float
    reliability_score: float
    availability: bool
    avg_speed_kmh: float
    rating: float
    composite_score: float = Field(..., description="Multi-objective composite score (higher is better)")
    estimated_cost: float = Field(0, description="Estimated cost for the given distance")
    estimated_eta_hours: float = Field(0, description="Estimated ETA for the given distance")


class CarrierResponse(BaseModel):
    carriers: list[ScoredCarrier]
    total_available: int
    filters_applied: dict


# ─── Scoring logic ────────────────────────────────────────────────────────────

# Default weights (can be adjusted by priority)
WEIGHT_PROFILES = {
    "economy": {"cost": 0.50, "reliability": 0.20, "availability": 0.10, "eta": 0.20},
    "standard": {"cost": 0.35, "reliability": 0.30, "availability": 0.15, "eta": 0.20},
    "express": {"cost": 0.15, "reliability": 0.25, "availability": 0.20, "eta": 0.40},
}


def score_carrier(
    carrier: dict,
    distance_km: float,
    priority: str = "standard",
    requires_reefer: bool = False,
) -> dict | None:
    """
    Score a carrier using multi-objective weighted scoring.
    Returns None if carrier doesn't meet basic eligibility.
    """
    # Eligibility filters
    if not carrier.get("availability", False):
        return None

    if requires_reefer and "reefer" not in carrier.get("fleet_type", []):
        return None

    weights = WEIGHT_PROFILES.get(priority, WEIGHT_PROFILES["standard"])

    # Normalize scores (0-1 range, higher is better)
    # Cost: lower cost_per_km is better → invert
    max_cost = 50  # normalization ceiling
    cost_score = 1 - min(carrier["cost_per_km"] / max_cost, 1.0)

    # Reliability: already 0-1
    reliability_score = carrier["reliability_score"]

    # Availability: binary
    avail_score = 1.0 if carrier["availability"] else 0.0

    # ETA: higher speed is better
    max_speed = 80
    eta_score = min(carrier.get("avg_speed_kmh", 50) / max_speed, 1.0)

    # Composite score
    composite = (
        weights["cost"] * cost_score
        + weights["reliability"] * reliability_score
        + weights["availability"] * avail_score
        + weights["eta"] * eta_score
    )

    # Estimated cost and ETA
    est_cost = distance_km * carrier["cost_per_km"]
    est_eta = distance_km / carrier.get("avg_speed_kmh", 50)

    return {
        **carrier,
        "composite_score": round(composite, 4),
        "estimated_cost": round(est_cost, 2),
        "estimated_eta_hours": round(est_eta, 1),
    }


# ─── FastAPI App ──────────────────────────────────────────────────────────────

app = FastAPI(
    title="Carrier Selection Service",
    description="Multi-objective carrier scoring and ranking",
    version="1.0.0",
)


@app.get("/health")
async def health():
    return {"status": "healthy", "service": "carrier_service", "carriers_loaded": len(_carriers)}


@app.get("/carriers", response_model=CarrierResponse)
async def get_available_carriers(
    origin: str = Query(None, description="Origin city filter"),
    destination: str = Query(None, description="Destination city filter"),
    cargo_type: str = Query(None, description="Cargo type filter"),
    priority: str = Query("standard", description="economy | standard | express"),
    distance_km: float = Query(500, description="Estimated distance for cost calculation"),
    requires_reefer: bool = Query(False, description="Requires refrigerated transport"),
    min_reliability: float = Query(0.0, description="Minimum reliability score filter"),
):
    """
    Get available carriers ranked by multi-objective composite score.
    """
    filters = {
        "origin": origin,
        "destination": destination,
        "priority": priority,
        "distance_km": distance_km,
        "requires_reefer": requires_reefer,
        "min_reliability": min_reliability,
    }

    scored = []
    for carrier in _carriers_raw:
        # Coverage filter
        if origin and origin not in carrier.get("coverage_cities", []):
            continue
        if destination and destination not in carrier.get("coverage_cities", []):
            continue

        # Reliability filter
        if carrier["reliability_score"] < min_reliability:
            continue

        result = score_carrier(carrier, distance_km, priority, requires_reefer)
        if result:
            scored.append(ScoredCarrier(**result))

    # Sort by composite score descending
    scored.sort(key=lambda c: c.composite_score, reverse=True)

    return CarrierResponse(
        carriers=scored,
        total_available=len(scored),
        filters_applied=filters,
    )


@app.get("/carriers/{carrier_id}")
async def get_carrier(carrier_id: str):
    """Get a specific carrier by ID."""
    if carrier_id not in _carriers:
        raise HTTPException(404, f"Carrier '{carrier_id}' not found")
    return _carriers[carrier_id]


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8003)
