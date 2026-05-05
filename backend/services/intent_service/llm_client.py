"""
LLM Client — Communicates with Ollama for intent extraction and explanation generation.
"""

import json
import httpx
from typing import Optional

# Ollama configuration
OLLAMA_BASE_URL = "http://localhost:11434"
OLLAMA_MODEL = "mistral:7b"
TIMEOUT = 60.0

# ─── System prompts ──────────────────────────────────────────────────────────

INTENT_SYSTEM_PROMPT = """You are a logistics intent extraction AI. Given a natural language query about shipping/freight, extract structured information.

Return ONLY valid JSON with these fields:
{
  "origin": "city name",
  "destination": "city name",
  "cargo_type": "one of: FMCG, electronics, pharmaceuticals, automotive, textiles, chemicals, perishable, general",
  "weight_kg": number,
  "volume_cbm": number,
  "priority": "one of: economy, standard, express",
  "max_price": number or null,
  "requires_reefer": boolean
}

Available cities: Mumbai, Pune, Delhi, Bangalore, Chennai, Hyderabad, Kolkata, Ahmedabad, Jaipur, Lucknow, Kanpur, Nagpur, Indore, Bhopal, Nashik, Varanasi, Patna, Chandigarh, Kochi, Visakhapatnam

Examples:
User: "Ship 2 tons of electronics from Mumbai to Delhi urgently"
Response: {"origin": "Mumbai", "destination": "Delhi", "cargo_type": "electronics", "weight_kg": 2000, "volume_cbm": 10, "priority": "express", "max_price": null, "requires_reefer": false}

User: "I need to send 500kg of medicines from Chennai to Kolkata, budget under 30000"
Response: {"origin": "Chennai", "destination": "Kolkata", "cargo_type": "pharmaceuticals", "weight_kg": 500, "volume_cbm": 3, "priority": "standard", "max_price": 30000, "requires_reefer": false}

Return ONLY the JSON object, no explanation or markdown."""

EXPLANATION_SYSTEM_PROMPT = """You are a logistics pricing analyst. Given pricing details, generate a clear 2-3 sentence explanation of why this option was recommended. Be specific about the trade-offs and what makes it a good choice. Keep it conversational and helpful."""


# ─── LLM API calls ───────────────────────────────────────────────────────────

async def _call_ollama(prompt: str, system: str, model: str = None) -> Optional[str]:
    """Call Ollama API with the given prompt and system message."""
    model = model or OLLAMA_MODEL

    try:
        async with httpx.AsyncClient(timeout=TIMEOUT) as client:
            response = await client.post(
                f"{OLLAMA_BASE_URL}/api/generate",
                json={
                    "model": model,
                    "prompt": prompt,
                    "system": system,
                    "stream": False,
                    "options": {
                        "temperature": 0.1,
                        "top_p": 0.9,
                    },
                },
            )
            if response.status_code == 200:
                data = response.json()
                return data.get("response", "")
            return None
    except (httpx.ConnectError, httpx.TimeoutException):
        return None


async def extract_intent_with_llm(text: str) -> Optional[dict]:
    """
    Use LLM to extract structured intent from natural language.
    Returns parsed JSON dict or None if LLM is unavailable.
    """
    response = await _call_ollama(
        prompt=f"Extract shipping intent from: \"{text}\"",
        system=INTENT_SYSTEM_PROMPT,
    )

    if not response:
        return None

    # Try to parse JSON from response
    try:
        # Clean up response - sometimes LLM wraps in markdown
        cleaned = response.strip()
        if cleaned.startswith("```"):
            cleaned = cleaned.split("```")[1]
            if cleaned.startswith("json"):
                cleaned = cleaned[4:]
        cleaned = cleaned.strip()

        return json.loads(cleaned)
    except json.JSONDecodeError:
        # Try to extract JSON from the response
        import re
        json_match = re.search(r'\{[^{}]*\}', response, re.DOTALL)
        if json_match:
            try:
                return json.loads(json_match.group())
            except json.JSONDecodeError:
                return None
        return None


async def generate_explanation(pricing_details: dict) -> Optional[str]:
    """
    Use LLM to generate a natural language explanation of pricing.
    """
    prompt = f"Explain this logistics pricing option:\n{json.dumps(pricing_details, indent=2)}"

    response = await _call_ollama(
        prompt=prompt,
        system=EXPLANATION_SYSTEM_PROMPT,
    )

    return response
