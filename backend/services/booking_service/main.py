"""
Booking Service — Handles booking confirmation and tracking.
Stores bookings in-memory for MVP (PostgreSQL in production).
"""

import uuid
from datetime import datetime, timedelta

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field


# ─── In-memory store (replace with PostgreSQL in production) ──────────────────

_bookings: dict[str, dict] = {}


# ─── Models ───────────────────────────────────────────────────────────────────

class BookingRequest(BaseModel):
    option_id: str
    carrier: str
    carrier_id: str
    route: list[str]
    price: float
    eta_hours: float
    customer_name: str | None = None
    customer_email: str | None = None
    customer_phone: str | None = None
    shipment_id: str | None = None


class BookingConfirmation(BaseModel):
    booking_id: str
    tracking_id: str
    status: str
    option_id: str
    carrier: str
    route: list[str]
    price: float
    eta_hours: float
    booked_at: str
    estimated_delivery: str
    customer_name: str | None = None


class BookingListResponse(BaseModel):
    bookings: list[BookingConfirmation]
    total: int


# ─── FastAPI App ──────────────────────────────────────────────────────────────

app = FastAPI(
    title="Booking Service",
    description="Booking confirmation and tracking",
    version="1.0.0",
)


@app.get("/health")
async def health():
    return {"status": "healthy", "service": "booking_service", "total_bookings": len(_bookings)}


@app.post("/booking/confirm", response_model=BookingConfirmation)
async def confirm_booking(request: BookingRequest):
    """Confirm a booking from a pricing option."""
    booking_id = f"BK-{uuid.uuid4().hex[:8].upper()}"
    tracking_id = f"TRK-{uuid.uuid4().hex[:10].upper()}"
    now = datetime.utcnow()
    delivery = now + timedelta(hours=request.eta_hours)

    confirmation = BookingConfirmation(
        booking_id=booking_id,
        tracking_id=tracking_id,
        status="confirmed",
        option_id=request.option_id,
        carrier=request.carrier,
        route=request.route,
        price=request.price,
        eta_hours=request.eta_hours,
        booked_at=now.isoformat(),
        estimated_delivery=delivery.isoformat(),
        customer_name=request.customer_name,
    )

    _bookings[booking_id] = confirmation.model_dump()
    return confirmation


@app.get("/booking/{booking_id}", response_model=BookingConfirmation)
async def get_booking(booking_id: str):
    """Get booking status by ID."""
    if booking_id not in _bookings:
        raise HTTPException(404, f"Booking '{booking_id}' not found")
    return _bookings[booking_id]


@app.get("/booking/{booking_id}/track")
async def track_booking(booking_id: str):
    """Get tracking info for a booking."""
    if booking_id not in _bookings:
        raise HTTPException(404, f"Booking '{booking_id}' not found")

    booking = _bookings[booking_id]
    return {
        "tracking_id": booking["tracking_id"],
        "status": booking["status"],
        "carrier": booking["carrier"],
        "route": booking["route"],
        "current_location": booking["route"][0],  # Simulated
        "eta_hours": booking["eta_hours"],
        "estimated_delivery": booking["estimated_delivery"],
    }


@app.get("/bookings", response_model=BookingListResponse)
async def list_bookings():
    """List all bookings."""
    bookings = [BookingConfirmation(**b) for b in _bookings.values()]
    return BookingListResponse(bookings=bookings, total=len(bookings))


@app.delete("/booking/{booking_id}")
async def cancel_booking(booking_id: str):
    """Cancel a booking."""
    if booking_id not in _bookings:
        raise HTTPException(404, f"Booking '{booking_id}' not found")

    _bookings[booking_id]["status"] = "cancelled"
    return {"message": f"Booking {booking_id} cancelled", "status": "cancelled"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8006)
