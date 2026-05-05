"""
API Gateway — Central entry point for the DynamicPricingEngine platform.
Routes requests to downstream microservices.

In development mode, services are imported directly.
In production, this would proxy to separate service instances via HTTP.
"""

import sys
import time
from pathlib import Path
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

# Add parent to path for direct imports in dev mode
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from services.route_service.main import app as route_app
from services.carrier_service.main import app as carrier_app
from services.pricing_service.main import app as pricing_app
from services.recommendation_service.main import app as recommendation_app
from services.booking_service.main import app as booking_app
from services.intent_service.main import app as intent_app


@asynccontextmanager
async def lifespan(app: FastAPI):
    print("🚀 DynamicPricingEngine Gateway starting...")
    print("📦 Services: intent, route, carrier, pricing, recommendation, booking")
    print("📄 API Docs: http://localhost:8000/docs")
    yield
    print("🛑 Gateway shutting down...")


# ─── Main Gateway App ────────────────────────────────────────────────────────

app = FastAPI(
    title="DynamicPricingEngine — API Gateway",
    description=(
        "Voice-first logistics pricing and booking platform.\n\n"
        "## Services\n"
        "- **Route**: Graph-based route optimization (Dijkstra / Yen's K-shortest)\n"
        "- **Carrier**: Multi-objective carrier scoring and ranking\n"
        "- **Pricing**: Dynamic pricing engine — P = (B × D × F × T) + M\n"
        "- **Recommendation**: Orchestrator producing top-N ranked options\n"
        "- **Booking**: Booking confirmation and tracking\n"
    ),
    version="1.0.0",
    lifespan=lifespan,
)

# ─── CORS ─────────────────────────────────────────────────────────────────────

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ─── Request logging middleware ───────────────────────────────────────────────

@app.middleware("http")
async def log_requests(request: Request, call_next):
    start = time.time()
    response = await call_next(request)
    duration = round((time.time() - start) * 1000, 1)
    print(f"  {request.method} {request.url.path} → {response.status_code} ({duration}ms)")
    return response


# ─── Health ───────────────────────────────────────────────────────────────────

@app.get("/", tags=["Gateway"])
async def root():
    return {
        "service": "DynamicPricingEngine Gateway",
        "version": "1.0.0",
        "status": "running",
        "docs": "/docs",
        "services": {
            "intent": "/intent/extract",
            "route": "/route/optimize",
            "carriers": "/carriers",
            "pricing": "/pricing/calculate",
            "recommendations": "/recommendations",
            "booking": "/booking/confirm",
        },
    }


@app.get("/health", tags=["Gateway"])
async def health():
    return {
        "status": "healthy",
        "service": "gateway",
        "uptime": "running",
        "services": ["intent", "route", "carrier", "pricing", "recommendation", "booking"],
    }


# ─── Mount sub-applications ──────────────────────────────────────────────────
# In dev mode, we mount the services directly.
# In production, these would be reverse-proxied to separate containers.

# Intent Service
app.include_router(intent_app.router, tags=["Intent Extraction"])

# Route Service
app.include_router(route_app.router, tags=["Route Optimization"])

# Carrier Service
app.include_router(carrier_app.router, tags=["Carrier Selection"])

# Pricing Service
app.include_router(pricing_app.router, tags=["Dynamic Pricing"])

# Recommendation Service
app.include_router(recommendation_app.router, tags=["Recommendations"])

# Booking Service
app.include_router(booking_app.router, tags=["Booking"])


# ─── Error handlers ──────────────────────────────────────────────────────────

@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    return JSONResponse(
        status_code=500,
        content={
            "error": "internal_server_error",
            "message": str(exc),
            "path": str(request.url.path),
        },
    )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000, reload=True)
