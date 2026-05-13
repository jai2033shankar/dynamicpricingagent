"""
Dynamic Pricing Service — Core pricing engine.
Formula: P = (B × D × F × T) + M

Where:
  P = Final Price
  B = Base Cost (distance × carrier cost_per_km)
  D = Demand Multiplier
  F = Fuel Index
  T = Traffic/Weather Factor
  M = Margin
"""

import json
import random
from pathlib import Path
from datetime import datetime

from fastapi import FastAPI
from pydantic import BaseModel, Field

# ─── Load external signals ───────────────────────────────────────────────────

SIGNALS_PATH = Path(__file__).resolve().parents[3] / "data" / "sample" / "external_signals.json"

with open(SIGNALS_PATH) as f:
    _signals_data = json.load(f)

_signals_by_region = {s["region"]: s for s in _signals_data["signals"]}


# ─── Models ───────────────────────────────────────────────────────────────────

class PricingRequest(BaseModel):
    origin: str
    destination: str
    distance_km: float
    carrier_cost_per_km: float
    carrier_reliability: float = 0.9
    cargo_weight_kg: float = 1000
    cargo_type: str = "general"
    priority: str = "standard"
    route_risk_factor: float = 1.0
    route_cost_factor: float = 1.0

    # Optional overrides for signals
    weather_index: float | None = None
    fuel_price_index: float | None = None
    demand_index: float | None = None
    traffic_index: float | None = None


class PricingBreakdown(BaseModel):
    base_cost: float
    demand_surge: float
    fuel_adjustment: float
    weather_traffic_factor: float
    weight_surcharge: float
    priority_premium: float
    risk_adjustment: float
    margin: float


class PricingResult(BaseModel):
    price: float
    breakdown: PricingBreakdown
    confidence_score: float
    signals_used: dict
    explanation: str


# ─── Pricing logic ────────────────────────────────────────────────────────────

# Priority multipliers
PRIORITY_MULTIPLIERS = {
    "economy": 0.85,
    "standard": 1.0,
    "express": 1.35,
}

# Weight surcharge tiers (per kg above threshold)
WEIGHT_TIERS = [
    (500, 0),        # First 500 kg: no surcharge
    (2000, 0.5),     # 500-2000 kg: $0.5/kg
    (5000, 1.0),     # 2000-5000 kg: $1.0/kg
    (float("inf"), 1.5),  # 5000+ kg: $1.5/kg
]

# Cargo type risk multipliers
CARGO_RISK = {
    "FMCG": 1.0,
    "electronics": 1.15,
    "pharmaceuticals": 1.25,
    "automotive": 1.1,
    "textiles": 0.95,
    "chemicals": 1.3,
    "perishable": 1.2,
    "general": 1.0,
}

# Margin configuration
DEFAULT_MARGIN_PCT = 0.08
MIN_MARGIN_PCT = 0.03
MAX_MARGIN_PCT = 0.15


def get_signals(origin: str, destination: str, overrides: dict) -> dict:
    """Get external signals for a route, with optional overrides."""
    region_key = f"{origin}-{destination}"
    reverse_key = f"{destination}-{origin}"

    signals = (
        _signals_by_region.get(region_key)
        or _signals_by_region.get(reverse_key)
        or _signals_by_region.get("default")
    )

    result = {
        "weather_index": overrides.get("weather_index") or signals["weather_index"],
        "fuel_price_index": overrides.get("fuel_price_index") or signals["fuel_price_index"],
        "demand_index": overrides.get("demand_index") or signals["demand_index"],
        "traffic_index": overrides.get("traffic_index") or signals["traffic_index"],
    }

    # Add slight randomness to simulate real-time variation (±5%)
    for key in result:
        if not overrides.get(key):
            result[key] *= random.uniform(0.95, 1.05)
            result[key] = round(result[key], 3)

    return result


def calculate_weight_surcharge(weight_kg: float) -> float:
    """Calculate weight-based surcharge using tiered pricing."""
    surcharge = 0
    remaining = weight_kg

    prev_threshold = 0
    for threshold, rate in WEIGHT_TIERS:
        tier_weight = min(remaining, threshold - prev_threshold)
        if tier_weight <= 0:
            break
        surcharge += tier_weight * rate
        remaining -= tier_weight
        prev_threshold = threshold

    return round(surcharge, 2)


def calculate_price(request: PricingRequest) -> PricingResult:
    """
    Core pricing formula: P = (B × D × F × T) + M

    With additional adjustments for weight, priority, cargo risk, and route risk.
    """
    signals = get_signals(
        request.origin,
        request.destination,
        {
            "weather_index": request.weather_index,
            "fuel_price_index": request.fuel_price_index,
            "demand_index": request.demand_index,
            "traffic_index": request.traffic_index,
        },
    )

    # B: Base Cost = distance × cost_per_km × route_cost_factor
    base_cost = request.distance_km * request.carrier_cost_per_km * request.route_cost_factor

    # D: Demand Multiplier impact
    demand_surge = base_cost * (signals["demand_index"] - 1.0)

    # F: Fuel price adjustment
    fuel_adjustment = base_cost * (signals["fuel_price_index"] - 1.0) * 0.5

    # T: Weather + Traffic composite
    weather_traffic = (signals["weather_index"] + signals["traffic_index"]) / 2
    weather_traffic_cost = base_cost * (weather_traffic - 1.0) * 0.3

    # Weight surcharge
    weight_surcharge = calculate_weight_surcharge(request.cargo_weight_kg)

    # Priority premium
    priority_mult = PRIORITY_MULTIPLIERS.get(request.priority, 1.0)
    priority_premium = base_cost * (priority_mult - 1.0)

    # Cargo risk adjustment
    cargo_risk = CARGO_RISK.get(request.cargo_type, 1.0)
    risk_adjustment = base_cost * (cargo_risk - 1.0) * 0.2 + base_cost * (request.route_risk_factor - 1.0) * 0.15

    # Subtotal before margin
    subtotal = base_cost + demand_surge + fuel_adjustment + weather_traffic_cost + weight_surcharge + priority_premium + risk_adjustment

    # M: Margin (adaptive based on demand)
    margin_pct = DEFAULT_MARGIN_PCT
    if signals["demand_index"] > 1.3:
        margin_pct = min(margin_pct * 1.5, MAX_MARGIN_PCT)
    elif signals["demand_index"] < 0.8:
        margin_pct = max(margin_pct * 0.7, MIN_MARGIN_PCT)

    margin = subtotal * margin_pct

    # Final price
    final_price = round(subtotal + margin, 0)

    # Confidence score (based on data quality and carrier reliability)
    confidence = round(
        min(1.0, request.carrier_reliability * 0.5 + 0.3 + random.uniform(0, 0.2)),
        2,
    )

    # Generate explanation
    explanation_parts = []
    if demand_surge > 0:
        explanation_parts.append(f"Demand surge adds ${demand_surge:,.0f} due to {signals['demand_index']:.1f}x demand")
    if fuel_adjustment > 0:
        explanation_parts.append(f"Fuel index at {signals['fuel_price_index']:.2f}x adds ${fuel_adjustment:,.0f}")
    if priority_premium > 0:
        explanation_parts.append(f"{request.priority.title()} priority adds ${priority_premium:,.0f}")
    if weight_surcharge > 0:
        explanation_parts.append(f"Weight surcharge of ${weight_surcharge:,.0f} for {request.cargo_weight_kg}kg")

    explanation = (
        f"Base cost ${base_cost:,.0f} for {request.distance_km}km. "
        + ". ".join(explanation_parts) + "."
        if explanation_parts
        else f"Base cost ${base_cost:,.0f} for {request.distance_km}km with standard conditions."
    )

    breakdown = PricingBreakdown(
        base_cost=round(base_cost, 2),
        demand_surge=round(max(demand_surge, 0), 2),
        fuel_adjustment=round(max(fuel_adjustment, 0), 2),
        weather_traffic_factor=round(weather_traffic_cost, 2),
        weight_surcharge=round(weight_surcharge, 2),
        priority_premium=round(max(priority_premium, 0), 2),
        risk_adjustment=round(max(risk_adjustment, 0), 2),
        margin=round(margin, 2),
    )

    return PricingResult(
        price=final_price,
        breakdown=breakdown,
        confidence_score=confidence,
        signals_used=signals,
        explanation=explanation,
    )


# ─── FastAPI App ──────────────────────────────────────────────────────────────

app = FastAPI(
    title="Dynamic Pricing Service",
    description="P = (B × D × F × T) + M — Dynamic logistics pricing engine",
    version="1.0.0",
)


@app.get("/health")
async def health():
    return {"status": "healthy", "service": "pricing_service"}


@app.post("/pricing/calculate", response_model=PricingResult)
async def calculate(request: PricingRequest):
    """Calculate dynamic price for a shipment."""
    return calculate_price(request)


@app.get("/pricing/signals")
async def get_current_signals(origin: str = "New York", destination: str = "Los Angeles"):
    """Get current external signals for a route."""
    return get_signals(origin, destination, {})


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8004)
