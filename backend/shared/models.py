"""
Shared Pydantic models for the DynamicPricingEngine platform.
All models match the JSON schemas defined in the system specification.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field


# ─── Enums ────────────────────────────────────────────────────────────────────

class Priority(str, Enum):
    ECONOMY = "economy"
    STANDARD = "standard"
    EXPRESS = "express"


class CargoType(str, Enum):
    FMCG = "FMCG"
    ELECTRONICS = "electronics"
    PHARMACEUTICALS = "pharmaceuticals"
    AUTOMOTIVE = "automotive"
    TEXTILES = "textiles"
    CHEMICALS = "chemicals"
    PERISHABLE = "perishable"
    GENERAL = "general"


class FleetType(str, Enum):
    TRUCK = "truck"
    REEFER = "reefer"
    FLATBED = "flatbed"
    CONTAINER = "container"
    TANKER = "tanker"


class BookingStatus(str, Enum):
    PENDING = "pending"
    CONFIRMED = "confirmed"
    IN_TRANSIT = "in_transit"
    DELIVERED = "delivered"
    CANCELLED = "cancelled"


# ─── Location ─────────────────────────────────────────────────────────────────

class Location(BaseModel):
    lat: float = Field(..., description="Latitude")
    lng: float = Field(..., description="Longitude")
    city: str = Field(..., description="City name")


# ─── Cargo ─────────────────────────────────────────────────────────────────────

class Cargo(BaseModel):
    type: CargoType = Field(..., description="Type of cargo")
    weight_kg: float = Field(..., gt=0, description="Weight in kilograms")
    volume_cbm: float = Field(..., gt=0, description="Volume in cubic meters")


# ─── Constraints ───────────────────────────────────────────────────────────────

class ShipmentConstraints(BaseModel):
    max_price: Optional[float] = Field(None, description="Maximum acceptable price in INR")
    preferred_carrier: Optional[str] = Field(None, description="Preferred carrier ID")
    max_eta_hours: Optional[float] = Field(None, description="Maximum ETA in hours")
    requires_reefer: bool = Field(False, description="Requires refrigerated transport")


# ─── Shipment Intent ──────────────────────────────────────────────────────────

class ShipmentIntent(BaseModel):
    """Extracted structured intent from voice/text input."""
    shipment_id: str = Field(default_factory=lambda: f"SHP-{uuid.uuid4().hex[:8].upper()}")
    origin: Location
    destination: Location
    cargo: Cargo
    priority: Priority = Priority.STANDARD
    constraints: ShipmentConstraints = Field(default_factory=ShipmentConstraints)
    raw_query: Optional[str] = Field(None, description="Original voice/text query")
    timestamp: datetime = Field(default_factory=datetime.utcnow)


# ─── Carrier ──────────────────────────────────────────────────────────────────

class CarrierData(BaseModel):
    """Carrier profile with capabilities and scoring attributes."""
    carrier_id: str
    name: str
    fleet_type: list[FleetType]
    cost_per_km: float = Field(..., gt=0, description="Base cost per kilometer in INR")
    reliability_score: float = Field(..., ge=0, le=1, description="0-1 reliability score")
    availability: bool = True
    avg_speed_kmh: float = Field(60.0, gt=0, description="Average speed in km/h")
    min_weight_kg: float = Field(0, ge=0)
    max_weight_kg: float = Field(50000, gt=0)
    coverage_cities: list[str] = Field(default_factory=list)
    rating: float = Field(4.0, ge=0, le=5)


# ─── External Signals ────────────────────────────────────────────────────────

class ExternalSignals(BaseModel):
    """Real-time external market signals affecting pricing."""
    weather_index: float = Field(1.0, ge=0, le=2, description="1.0 = normal, >1 = adverse")
    fuel_price_index: float = Field(1.0, ge=0, le=3, description="1.0 = baseline fuel price")
    demand_index: float = Field(1.0, ge=0, le=3, description="1.0 = normal demand")
    traffic_index: float = Field(1.0, ge=0, le=3, description="1.0 = normal traffic")
    timestamp: datetime = Field(default_factory=datetime.utcnow)


# ─── Pricing ──────────────────────────────────────────────────────────────────

class PricingBreakdown(BaseModel):
    """Detailed breakdown of how the final price was calculated."""
    base_cost: float = Field(..., description="Distance × cost_per_km")
    demand_surge: float = Field(..., description="Demand multiplier impact")
    fuel_adjustment: float = Field(..., description="Fuel price adjustment")
    weather_traffic_factor: float = Field(..., description="Weather + traffic impact")
    margin: float = Field(..., description="Service margin")


class PricingOutput(BaseModel):
    """A single pricing option returned to the user."""
    option_id: str = Field(default_factory=lambda: f"OPT-{uuid.uuid4().hex[:6].upper()}")
    carrier: str
    carrier_id: str
    route: list[str] = Field(..., description="List of waypoint cities")
    distance_km: float
    eta_hours: float
    price: float = Field(..., description="Final price in INR")
    breakdown: PricingBreakdown
    confidence_score: float = Field(..., ge=0, le=1)
    explanation: str = Field(..., description="Natural language explanation")
    badge: Optional[str] = Field(None, description="e.g. 'Best Value', 'Fastest'")


# ─── Route ────────────────────────────────────────────────────────────────────

class RouteEdge(BaseModel):
    from_city: str
    to_city: str
    distance_km: float
    time_hours: float
    cost_factor: float = 1.0
    risk_factor: float = 1.0


class RouteOption(BaseModel):
    """A single optimized route."""
    route_id: str = Field(default_factory=lambda: f"RT-{uuid.uuid4().hex[:6].upper()}")
    waypoints: list[str]
    total_distance_km: float
    total_time_hours: float
    total_cost_factor: float = 1.0
    total_risk_factor: float = 1.0


# ─── Booking ──────────────────────────────────────────────────────────────────

class BookingRequest(BaseModel):
    option_id: str
    shipment_intent: ShipmentIntent
    pricing_option: PricingOutput
    customer_name: Optional[str] = None
    customer_email: Optional[str] = None
    customer_phone: Optional[str] = None


class BookingConfirmation(BaseModel):
    booking_id: str = Field(default_factory=lambda: f"BK-{uuid.uuid4().hex[:8].upper()}")
    tracking_id: str = Field(default_factory=lambda: f"TRK-{uuid.uuid4().hex[:10].upper()}")
    status: BookingStatus = BookingStatus.CONFIRMED
    option_id: str
    carrier: str
    route: list[str]
    price: float
    eta_hours: float
    booked_at: datetime = Field(default_factory=datetime.utcnow)
    estimated_delivery: Optional[datetime] = None


# ─── Recommendation Request / Response ────────────────────────────────────────

class RecommendationRequest(BaseModel):
    intent: ShipmentIntent
    max_options: int = Field(3, ge=1, le=10)


class RecommendationResponse(BaseModel):
    shipment_id: str
    options: list[PricingOutput]
    signals_used: ExternalSignals
    processing_time_ms: float
    generated_at: datetime = Field(default_factory=datetime.utcnow)


# ─── Intent Extraction ────────────────────────────────────────────────────────

class IntentExtractionRequest(BaseModel):
    text: Optional[str] = Field(None, description="Text query to extract intent from")
    audio_base64: Optional[str] = Field(None, description="Base64-encoded audio for ASR")


class IntentExtractionResponse(BaseModel):
    intent: ShipmentIntent
    confidence: float = Field(..., ge=0, le=1)
    raw_transcript: Optional[str] = None
    extraction_method: str = "llm"
