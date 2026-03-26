from datetime import datetime
from decimal import Decimal
from math import atan2, cos, radians, sin, sqrt


# ──────────────────── Tarifs (marché urbain africain) ──────────────────
BASE_FARE_CDF = Decimal("1000.00")     # Tarif de base
PRICE_PER_KM_CDF = Decimal("500.00")   # Prix par km
PRICE_PER_MIN_CDF = Decimal("100.00")  # Prix par minute
WAIT_PER_MIN_CDF = Decimal("100.00")   # Temps d'attente par minute
MIN_FARE_CDF = Decimal("1500.00")      # Tarif minimum
AVG_SPEED_KMH = 25                      # Vitesse moyenne Kinshasa

# Surge / ajustements
SURGE_PEAK_HOURS = [(6, 9), (17, 20)]   # Heures de pointe (matin, soir)
SURGE_MULTIPLIER = Decimal("1.3")        # ×1.3 en heure de pointe


def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate distance in km between two GPS points."""
    R = 6371  # Earth radius in km
    dlat = radians(lat2 - lat1)
    dlon = radians(lon2 - lon1)
    a = sin(dlat / 2) ** 2 + cos(radians(lat1)) * cos(radians(lat2)) * sin(dlon / 2) ** 2
    c = 2 * atan2(sqrt(a), sqrt(1 - a))
    return R * c


def _is_peak_hour() -> bool:
    """Check if current time is in peak hours."""
    hour = datetime.now().hour
    return any(start <= hour < end for start, end in SURGE_PEAK_HOURS)


def estimate_price(
    pickup_lat: float,
    pickup_lng: float,
    dest_lat: float,
    dest_lng: float,
) -> dict:
    """Estimate ride price based on distance + time + surge."""
    distance_km = haversine_distance(pickup_lat, pickup_lng, dest_lat, dest_lng)
    # Apply road factor (roads aren't straight)
    road_distance = Decimal(str(round(distance_km * 1.3, 2)))
    duration_min = int(float(road_distance) / AVG_SPEED_KMH * 60)

    price = (
        BASE_FARE_CDF
        + (road_distance * PRICE_PER_KM_CDF)
        + (Decimal(duration_min) * PRICE_PER_MIN_CDF)
    )

    # Surge pricing
    surge = Decimal("1.0")
    if _is_peak_hour():
        surge = SURGE_MULTIPLIER
        price = price * surge

    price = max(price, MIN_FARE_CDF)
    # Round to nearest 500 CDF
    price = Decimal(str(round(float(price) / 500) * 500))

    return {
        "distance_km": float(road_distance),
        "estimated_duration_minutes": duration_min,
        "estimated_price": float(price),
        "currency": "CDF",
        "surge_multiplier": float(surge),
        "is_peak_hour": surge > 1,
    }
