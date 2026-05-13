"""
Intent Extraction Service — Two-stage pipeline:
1. Audio → Whisper (ASR) → raw transcript
2. Transcript → LLM → structured ShipmentIntent JSON

Supports both text and audio input.
"""

import json
import re
import uuid
from datetime import datetime

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from .llm_client import extract_intent_with_llm, generate_explanation


# ─── Models ───────────────────────────────────────────────────────────────────

class IntentRequest(BaseModel):
    text: str | None = Field(None, description="Text query to extract intent from")
    audio_base64: str | None = Field(None, description="Base64-encoded audio for ASR")


class Location(BaseModel):
    lat: float = 0
    lng: float = 0
    city: str = ""


class Cargo(BaseModel):
    type: str = "general"
    weight_kg: float = 1000
    volume_cbm: float = 5


class Constraints(BaseModel):
    max_price: float | None = None
    preferred_carrier: str | None = None
    max_eta_hours: float | None = None
    requires_reefer: bool = False


class ShipmentIntent(BaseModel):
    shipment_id: str = ""
    origin: Location = Field(default_factory=Location)
    destination: Location = Field(default_factory=Location)
    cargo: Cargo = Field(default_factory=Cargo)
    priority: str = "standard"
    constraints: Constraints = Field(default_factory=Constraints)
    raw_query: str | None = None


class IntentResponse(BaseModel):
    intent: ShipmentIntent
    confidence: float
    raw_transcript: str | None = None
    extraction_method: str = "llm"


# ─── City coordinates lookup ─────────────────────────────────────────────────

CITY_COORDS = {
    "New York": (19.0760, 72.8777),
    "Philadelphia": (18.5204, 73.8567),
    "Los Angeles": (28.7041, 77.1025),
    "Dallas": (12.9716, 77.5946),
    "Houston": (13.0827, 80.2707),
    "Austin": (17.3850, 78.4867),
    "Miami": (22.5726, 88.3639),
    "Boston": (23.0225, 72.5714),
    "Las Vegas": (26.9124, 75.7873),
    "Atlanta": (26.8467, 80.9462),
    "Charlotte": (26.4499, 80.3319),
    "Pittsburgh": (21.1458, 79.0882),
    "Chicago": (22.7196, 75.8577),
    "Detroit": (23.2599, 77.4126),
    "Baltimore": (19.9975, 73.7898),
    "Orlando": (25.3176, 82.9739),
    "Tampa": (25.6093, 85.1376),
    "Seattle": (30.7333, 76.7794),
    "San Diego": (9.9312, 76.2673),
    "San Francisco": (17.6868, 83.2185),
    "Dehradun": (30.3165, 78.0322),
    "Amritsar": (31.6340, 74.8723),
}


def get_city_location(city_name: str) -> Location:
    """Get coordinates for a city name (fuzzy match)."""
    # Exact match
    if city_name in CITY_COORDS:
        lat, lng = CITY_COORDS[city_name]
        return Location(lat=lat, lng=lng, city=city_name)

    # Case-insensitive match
    for city, coords in CITY_COORDS.items():
        if city.lower() == city_name.lower():
            return Location(lat=coords[0], lng=coords[1], city=city)

    # Partial match
    for city, coords in CITY_COORDS.items():
        if city_name.lower() in city.lower() or city.lower() in city_name.lower():
            return Location(lat=coords[0], lng=coords[1], city=city)

    return Location(city=city_name)


# ─── Fallback regex-based intent extraction ──────────────────────────────────

def extract_intent_regex(text: str) -> ShipmentIntent:
    """
    Fallback regex-based extraction when LLM is not available.
    Parses natural language queries for shipment details.
    """
    text_lower = text.lower()

    # Extract cities
    origin_city = ""
    dest_city = ""
    city_names = list(CITY_COORDS.keys())

    # Look for "from X to Y" pattern
    from_to = re.search(r'from\s+(\w+)\s+to\s+(\w+)', text_lower)
    if from_to:
        for city in city_names:
            if city.lower() == from_to.group(1):
                origin_city = city
            if city.lower() == from_to.group(2):
                dest_city = city

    # Look for "X to Y" pattern
    if not origin_city or not dest_city:
        for i, city1 in enumerate(city_names):
            for city2 in city_names[i + 1:]:
                if city1.lower() in text_lower and city2.lower() in text_lower:
                    # Determine order by position in text
                    pos1 = text_lower.index(city1.lower())
                    pos2 = text_lower.index(city2.lower())
                    if pos1 < pos2:
                        origin_city = origin_city or city1
                        dest_city = dest_city or city2
                    else:
                        origin_city = origin_city or city2
                        dest_city = dest_city or city1

    # Extract weight
    weight = 1000
    weight_match = re.search(r'(\d+)\s*(kg|kilo|tons?)', text_lower)
    if weight_match:
        w = float(weight_match.group(1))
        if 'ton' in weight_match.group(2):
            w *= 1000
        weight = w

    # Extract cargo type
    cargo_type = "general"
    cargo_keywords = {
        "electronics": ["electronics", "laptop", "phone", "gadget"],
        "FMCG": ["fmcg", "grocery", "food", "consumer"],
        "pharmaceuticals": ["pharma", "medicine", "medical", "drug"],
        "perishable": ["perishable", "fruit", "vegetable", "dairy"],
        "chemicals": ["chemical", "hazardous", "industrial"],
        "textiles": ["textile", "cloth", "fabric", "garment"],
        "automotive": ["auto", "car", "vehicle", "parts"],
    }
    for ctype, keywords in cargo_keywords.items():
        if any(kw in text_lower for kw in keywords):
            cargo_type = ctype
            break

    # Extract priority
    priority = "standard"
    if any(w in text_lower for w in ["urgent", "express", "fast", "rush", "asap"]):
        priority = "express"
    elif any(w in text_lower for w in ["cheap", "budget", "economy", "lowest"]):
        priority = "economy"

    # Extract price constraint
    max_price = None
    price_match = re.search(r'(?:under|below|max|budget)\s*(?:\$|usd)?\s*(\d[\d,]*)', text_lower)
    if price_match:
        max_price = float(price_match.group(1).replace(",", ""))

    return ShipmentIntent(
        shipment_id=f"SHP-{uuid.uuid4().hex[:8].upper()}",
        origin=get_city_location(origin_city) if origin_city else Location(),
        destination=get_city_location(dest_city) if dest_city else Location(),
        cargo=Cargo(type=cargo_type, weight_kg=weight, volume_cbm=max(weight / 200, 1)),
        priority=priority,
        constraints=Constraints(max_price=max_price),
        raw_query=text,
    )


# ─── FastAPI App ──────────────────────────────────────────────────────────────

app = FastAPI(
    title="Intent Extraction Service",
    description="Extracts structured shipment intent from voice/text input",
    version="1.0.0",
)


@app.get("/health")
async def health():
    return {"status": "healthy", "service": "intent_service"}


@app.post("/intent/extract", response_model=IntentResponse)
async def extract_intent(request: IntentRequest):
    """
    Extract structured shipment intent from text or audio input.

    Pipeline:
    1. If audio: Whisper ASR → transcript
    2. Transcript/text → LLM intent extraction (or regex fallback)
    """
    if not request.text and not request.audio_base64:
        raise HTTPException(400, "Either 'text' or 'audio_base64' must be provided")

    transcript = request.text
    extraction_method = "llm"

    # ASR step (if audio provided)
    if request.audio_base64 and not request.text:
        # TODO: Call Whisper via Ollama
        # For now, return error suggesting text input
        raise HTTPException(
            501,
            "Audio ASR not yet configured. Please provide text input or configure Ollama with Whisper."
        )

    # Try LLM extraction first
    try:
        intent_data = await extract_intent_with_llm(transcript)
        if intent_data:
            # Parse LLM response into ShipmentIntent
            intent = ShipmentIntent(
                shipment_id=f"SHP-{uuid.uuid4().hex[:8].upper()}",
                origin=get_city_location(intent_data.get("origin", "")),
                destination=get_city_location(intent_data.get("destination", "")),
                cargo=Cargo(
                    type=intent_data.get("cargo_type", "general"),
                    weight_kg=intent_data.get("weight_kg", 1000),
                    volume_cbm=intent_data.get("volume_cbm", 5),
                ),
                priority=intent_data.get("priority", "standard"),
                constraints=Constraints(
                    max_price=intent_data.get("max_price"),
                    requires_reefer=intent_data.get("requires_reefer", False),
                ),
                raw_query=transcript,
            )
            return IntentResponse(
                intent=intent,
                confidence=0.9,
                raw_transcript=transcript,
                extraction_method="llm",
            )
    except Exception:
        extraction_method = "regex"

    # Fallback to regex extraction
    intent = extract_intent_regex(transcript)
    confidence = 0.6
    if intent.origin.city and intent.destination.city:
        confidence = 0.75

    return IntentResponse(
        intent=intent,
        confidence=confidence,
        raw_transcript=transcript,
        extraction_method=extraction_method,
    )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)
