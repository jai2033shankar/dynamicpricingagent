"""
Recommendation Service — Orchestrator that combines Route + Carrier + Pricing
to produce top-N ranked options with explanations.
"""

import json
import time
import uuid
import heapq
from pathlib import Path
from datetime import datetime

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

# ─── Import sibling service logic directly (monolith mode for dev) ────────────
# In production, these would be HTTP calls to separate services.

import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from services.route_service.main import find_k_shortest_paths, compute_route_metrics
from services.carrier_service.main import score_carrier, _carriers_raw
from services.pricing_service.main import calculate_price, PricingRequest


# ─── Models ───────────────────────────────────────────────────────────────────

class Location(BaseModel):
    lat: float
    lng: float
    city: str


class Cargo(BaseModel):
    type: str = "general"
    weight_kg: float = 1000
    volume_cbm: float = 5


class Constraints(BaseModel):
    max_price: float | None = None
    preferred_carrier: str | None = None
    max_eta_hours: float | None = None
    requires_reefer: bool = False


class RecommendationRequest(BaseModel):
    origin: Location
    destination: Location
    cargo: Cargo
    priority: str = "standard"
    constraints: Constraints = Field(default_factory=Constraints)
    max_options: int = Field(3, ge=1, le=10)


class PricingBreakdownOut(BaseModel):
    base_cost: float
    demand_surge: float
    fuel_adjustment: float
    weather_traffic_factor: float
    weight_surcharge: float
    priority_premium: float
    risk_adjustment: float
    margin: float


class PricingOption(BaseModel):
    option_id: str
    carrier: str
    carrier_id: str
    route: list[str]
    distance_km: float
    eta_hours: float
    price: float
    breakdown: PricingBreakdownOut
    confidence_score: float
    explanation: str
    badge: str | None = None


class SignalsUsed(BaseModel):
    weather_index: float
    fuel_price_index: float
    demand_index: float
    traffic_index: float


class RecommendationResponse(BaseModel):
    shipment_id: str
    options: list[PricingOption]
    signals_used: SignalsUsed | None = None
    processing_time_ms: float
    generated_at: str


# ─── Orchestration logic ─────────────────────────────────────────────────────

def generate_recommendations(request: RecommendationRequest) -> RecommendationResponse:
    """
    Orchestrate route optimization → carrier selection → pricing
    to produce ranked shipment options.
    """
    start_time = time.time()
    shipment_id = f"SHP-{uuid.uuid4().hex[:8].upper()}"

    origin = request.origin.city
    destination = request.destination.city

    # Step 1: Find optimal routes
    routes = find_k_shortest_paths(
        origin=origin,
        destination=destination,
        k=5,  # Get more routes than needed for better combinations
        optimize_for="balanced",
    )

    if not routes:
        raise HTTPException(404, f"No routes found from {origin} to {destination}")

    # Step 2: Score all eligible carriers
    all_options = []

    for route_info in routes:
        waypoints = route_info["path"]
        metrics = compute_route_metrics(waypoints)

        for carrier in _carriers_raw:
            # Check coverage (carrier must cover at least origin and destination)
            coverage = set(carrier.get("coverage_cities", []))
            if origin not in coverage or destination not in coverage:
                continue

            # Score carrier
            scored = score_carrier(
                carrier=carrier,
                distance_km=metrics["total_distance_km"],
                priority=request.priority,
                requires_reefer=request.constraints.requires_reefer,
            )
            if not scored:
                continue

            # Preferred carrier boost
            if request.constraints.preferred_carrier == carrier["carrier_id"]:
                scored["composite_score"] *= 1.15

            # Step 3: Calculate dynamic price
            pricing_req = PricingRequest(
                origin=origin,
                destination=destination,
                distance_km=metrics["total_distance_km"],
                carrier_cost_per_km=carrier["cost_per_km"],
                carrier_reliability=carrier["reliability_score"],
                cargo_weight_kg=request.cargo.weight_kg,
                cargo_type=request.cargo.type,
                priority=request.priority,
                route_risk_factor=metrics["total_risk_factor"],
                route_cost_factor=metrics["total_cost_factor"],
            )
            pricing_result = calculate_price(pricing_req)

            # Apply constraints
            if request.constraints.max_price and pricing_result.price > request.constraints.max_price:
                continue

            eta = metrics["total_time_hours"]
            if request.constraints.max_eta_hours and eta > request.constraints.max_eta_hours:
                continue

            # Composite ranking score (lower is better for price, higher for quality)
            rank_score = (
                0.4 * (pricing_result.price / 100000)  # Normalize price
                - 0.3 * scored["composite_score"]
                - 0.2 * pricing_result.confidence_score
                + 0.1 * (eta / 100)  # Normalize ETA
            )

            option = PricingOption(
                option_id=f"OPT-{uuid.uuid4().hex[:6].upper()}",
                carrier=carrier["name"],
                carrier_id=carrier["carrier_id"],
                route=waypoints,
                distance_km=metrics["total_distance_km"],
                eta_hours=round(eta, 1),
                price=pricing_result.price,
                breakdown=PricingBreakdownOut(**pricing_result.breakdown.model_dump()),
                confidence_score=pricing_result.confidence_score,
                explanation=pricing_result.explanation,
            )

            all_options.append((rank_score, option))

    if not all_options:
        raise HTTPException(404, "No viable options found matching your constraints")

    # Sort by rank score and take top N
    all_options.sort(key=lambda x: x[0])
    top_options = [opt for _, opt in all_options[:request.max_options]]

    # Assign badges
    if len(top_options) >= 1:
        # Find cheapest
        cheapest = min(top_options, key=lambda o: o.price)
        cheapest.badge = "Best Value"

        # Find fastest
        fastest = min(top_options, key=lambda o: o.eta_hours)
        if fastest.option_id != cheapest.option_id:
            fastest.badge = "Fastest"

        # Find most reliable
        most_reliable = max(top_options, key=lambda o: o.confidence_score)
        if most_reliable.option_id != cheapest.option_id and most_reliable.option_id != fastest.option_id:
            most_reliable.badge = "Most Reliable"

    processing_ms = round((time.time() - start_time) * 1000, 1)

    return RecommendationResponse(
        shipment_id=shipment_id,
        options=top_options,
        signals_used=None,  # Would be populated from pricing service signals
        processing_time_ms=processing_ms,
        generated_at=datetime.utcnow().isoformat(),
    )


# ─── FastAPI App ──────────────────────────────────────────────────────────────

app = FastAPI(
    title="Recommendation Service",
    description="Orchestrates route + carrier + pricing to produce ranked shipment options",
    version="1.0.0",
)


@app.get("/health")
async def health():
    return {"status": "healthy", "service": "recommendation_service"}


@app.post("/recommendations", response_model=RecommendationResponse)
async def get_recommendations(request: RecommendationRequest):
    """
    Get top-N shipment recommendations with pricing, route, and carrier details.
    """
    return generate_recommendations(request)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8005)
