"""
Intelligent driver scoring engine for ride matching.

Score = (ETA weight) + (reliability) + (performance) – (penalties)

Factors:
  1. ETA / Distance to pickup  (primary, highest weight)
  2. Acceptance rate            (driver reliability)
  3. Cancellation rate          (negative penalty)
  4. Average rating             (quality signal)
  5. Recent activity            (active drivers prioritized)
  6. Fair distribution          (anti-monopolization: fewer rides today = bonus)
"""

import logging
from datetime import timedelta
from decimal import Decimal

from django.utils import timezone

from .pricing import haversine_distance

logger = logging.getLogger(__name__)

# ── Weight configuration ──────────────────────────────────────────────────
W_ETA = 0.35          # Distance / ETA (most important)
W_ACCEPTANCE = 0.20   # Acceptance rate
W_RATING = 0.15       # Average rating
W_ACTIVITY = 0.15     # Recent activity (how recently active)
W_FAIRNESS = 0.10     # Fair distribution (fewer rides today = higher score)
W_CANCEL_PENALTY = 0.05  # Cancellation penalty

# ── Thresholds ────────────────────────────────────────────────────────────
MAX_SEARCH_RADIUS_KM = 10    # Maximum search radius
MIN_SEARCH_RADIUS_KM = 2     # Start searching from this radius
RADIUS_STEP_KM = 3           # Expand radius in steps
AVG_SPEED_KMH = 20           # Average speed in Kinshasa traffic
DRIVER_ACCEPT_TIMEOUT = 15   # Seconds for driver to respond (5-10 per spec, 15 gives buffer)
MAX_RIDES_PER_DAY_FAIRNESS = 20  # Beyond this, fairness bonus = 0


def compute_driver_score(profile, pickup_lat: float, pickup_lng: float) -> dict:
    """Compute a global score for a driver candidate.

    Returns dict with 'score' (0-100), 'distance_km', 'eta_minutes',
    and individual component scores for transparency.
    """
    # ── 1. Distance & ETA ─────────────────────────────────────────────────
    dist_km = haversine_distance(
        pickup_lat, pickup_lng,
        float(profile.current_latitude),
        float(profile.current_longitude),
    )
    # Road factor: real roads are ~1.3x straight-line distance
    road_dist = dist_km * 1.3
    eta_minutes = (road_dist / AVG_SPEED_KMH) * 60

    # Score: closer = higher. Max 100 at 0km, 0 at MAX_SEARCH_RADIUS_KM
    eta_score = max(0, 100 * (1 - dist_km / MAX_SEARCH_RADIUS_KM))

    # ── 2. Acceptance rate ────────────────────────────────────────────────
    accept_rate = float(profile.acceptance_rate) if profile.acceptance_rate else 100.0
    accept_score = accept_rate  # Already 0-100

    # ── 3. Rating ─────────────────────────────────────────────────────────
    rating = float(profile.rating_average) if profile.rating_average else 5.0
    rating_score = (rating / 5.0) * 100  # Normalize to 0-100

    # ── 4. Recent activity ────────────────────────────────────────────────
    activity_score = 50.0  # Default: neutral
    if profile.last_ride_at:
        hours_since = (timezone.now() - profile.last_ride_at).total_seconds() / 3600
        if hours_since < 1:
            activity_score = 100.0   # Very active
        elif hours_since < 4:
            activity_score = 80.0
        elif hours_since < 12:
            activity_score = 60.0
        elif hours_since < 24:
            activity_score = 40.0
        else:
            activity_score = 20.0
    elif profile.total_rides > 0:
        activity_score = 30.0  # Has rides but no recent timestamp

    # ── 5. Fair distribution ──────────────────────────────────────────────
    today = timezone.now().date()
    rides_today = profile.rides_today if profile.rides_today_date == today else 0
    # Fewer rides today = higher fairness bonus
    fairness_score = max(0, 100 * (1 - rides_today / MAX_RIDES_PER_DAY_FAIRNESS))

    # ── 6. Cancellation penalty ───────────────────────────────────────────
    cancel_rate = float(profile.cancellation_rate) if profile.cancellation_rate else 0.0
    cancel_penalty = cancel_rate  # 0-100, higher = worse

    # ── Composite score ───────────────────────────────────────────────────
    score = (
        W_ETA * eta_score
        + W_ACCEPTANCE * accept_score
        + W_RATING * rating_score
        + W_ACTIVITY * activity_score
        + W_FAIRNESS * fairness_score
        - W_CANCEL_PENALTY * cancel_penalty
    )
    score = max(0, min(100, score))

    return {
        "score": round(score, 2),
        "distance_km": round(dist_km, 2),
        "road_distance_km": round(road_dist, 2),
        "eta_minutes": round(eta_minutes, 1),
        "components": {
            "eta": round(eta_score, 1),
            "acceptance": round(accept_score, 1),
            "rating": round(rating_score, 1),
            "activity": round(activity_score, 1),
            "fairness": round(fairness_score, 1),
            "cancel_penalty": round(cancel_penalty, 1),
        },
    }


def rank_drivers(profiles, pickup_lat: float, pickup_lng: float):
    """Score and rank a queryset of driver profiles.

    Returns list of (profile, score_data) sorted by score descending.
    """
    scored = []
    for profile in profiles:
        if not profile.current_latitude or not profile.current_longitude:
            continue
        score_data = compute_driver_score(profile, pickup_lat, pickup_lng)
        scored.append((profile, score_data))

    # Sort by score descending (best first)
    scored.sort(key=lambda x: x[1]["score"], reverse=True)
    return scored


def update_driver_stats_on_accept(profile):
    """Update driver stats when they accept a ride."""
    today = timezone.now().date()
    profile.total_accepted += 1
    profile.last_ride_at = timezone.now()

    if profile.rides_today_date != today:
        profile.rides_today = 1
        profile.rides_today_date = today
    else:
        profile.rides_today += 1

    # Recalculate acceptance rate
    total_offers = profile.total_accepted + profile.total_declined
    if total_offers > 0:
        profile.acceptance_rate = Decimal(str(
            round((profile.total_accepted / total_offers) * 100, 2)
        ))

    profile.save(update_fields=[
        "total_accepted", "last_ride_at", "rides_today",
        "rides_today_date", "acceptance_rate",
    ])


def update_driver_stats_on_decline(profile):
    """Update driver stats when they decline a ride."""
    profile.total_declined += 1

    total_offers = profile.total_accepted + profile.total_declined
    if total_offers > 0:
        profile.acceptance_rate = Decimal(str(
            round((profile.total_accepted / total_offers) * 100, 2)
        ))

    profile.save(update_fields=["total_declined", "acceptance_rate"])


def update_driver_stats_on_cancel(profile):
    """Update driver stats when they cancel an accepted ride."""
    profile.total_cancelled += 1

    total_completed = profile.total_rides  # total_rides = completed rides
    total_relevant = total_completed + profile.total_cancelled
    if total_relevant > 0:
        profile.cancellation_rate = Decimal(str(
            round((profile.total_cancelled / total_relevant) * 100, 2)
        ))

    profile.save(update_fields=["total_cancelled", "cancellation_rate"])
