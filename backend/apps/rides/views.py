import logging
from datetime import timedelta

from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer
from django.conf import settings
from django.utils import timezone
from rest_framework import generics, permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.models import DriverProfile
from apps.accounts.permissions import IsApprovedDriver, IsDriver, IsPassenger
from apps.promotions.models import PromoCode, PromoUsage

from .models import Ride, RideLocationLog, SOSAlert
from .pricing import estimate_price, haversine_distance
from .serializers import (
    EstimatePriceSerializer,
    RideCancelSerializer,
    RideCreateSerializer,
    RideLocationLogSerializer,
    RideSerializer,
    SOSAlertSerializer,
)

logger = logging.getLogger(__name__)

# How long a driver has to accept before we move to the next one (seconds)
DRIVER_ACCEPT_TIMEOUT = 30


class EstimatePriceView(APIView):
    """Get price estimate for a ride."""

    def post(self, request):
        serializer = EstimatePriceSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        d = serializer.validated_data
        result = estimate_price(
            float(d["pickup_latitude"]),
            float(d["pickup_longitude"]),
            float(d["destination_latitude"]),
            float(d["destination_longitude"]),
        )

        # Apply promo if any
        if d.get("promo_code"):
            try:
                promo = PromoCode.objects.get(code=d["promo_code"].upper())
                if promo.is_valid:
                    from decimal import Decimal
                    discount = promo.calculate_discount(Decimal(str(result["estimated_price"])))
                    result["discount"] = float(discount)
                    result["final_price"] = float(
                        Decimal(str(result["estimated_price"])) - discount
                    )
                    result["promo_applied"] = True
                else:
                    result["promo_applied"] = False
                    result["promo_error"] = "Code promo expiré ou invalide."
            except PromoCode.DoesNotExist:
                result["promo_applied"] = False
                result["promo_error"] = "Code promo introuvable."

        return Response(result)


class RequestRideView(APIView):
    """Passenger requests a ride."""

    permission_classes = [permissions.IsAuthenticated, IsPassenger]

    def post(self, request):
        serializer = RideCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        # Check no active ride
        active = Ride.objects.filter(
            passenger=request.user,
            status__in=[
                Ride.Status.REQUESTED,
                Ride.Status.ACCEPTED,
                Ride.Status.DRIVER_ARRIVING,
                Ride.Status.IN_PROGRESS,
            ],
        ).exists()
        if active:
            return Response(
                {"detail": "Vous avez déjà une course en cours."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        ride = serializer.save(passenger=request.user)

        # Auto-assign the nearest available driver
        _auto_assign_nearest_driver(ride)

        return Response(RideSerializer(ride).data, status=status.HTTP_201_CREATED)


class AcceptRideView(APIView):
    """Driver accepts a ride request."""

    permission_classes = [permissions.IsAuthenticated, IsApprovedDriver]

    def post(self, request, ride_id):
        try:
            ride = Ride.objects.get(id=ride_id, status=Ride.Status.REQUESTED)
        except Ride.DoesNotExist:
            return Response(
                {"detail": "Course non disponible."},
                status=status.HTTP_404_NOT_FOUND,
            )

        # Verify this driver is the one currently assigned
        if ride.assigned_driver and ride.assigned_driver != request.user:
            return Response(
                {"detail": "Cette course est assignée à un autre chauffeur."},
                status=status.HTTP_403_FORBIDDEN,
            )

        profile = request.user.driver_profile
        if profile.is_on_ride:
            return Response(
                {"detail": "Vous êtes déjà en course."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        ride.driver = request.user
        ride.assigned_driver = None
        ride.assignment_expires_at = None
        ride.status = Ride.Status.ACCEPTED
        ride.accepted_at = timezone.now()
        ride.save(update_fields=[
            "driver", "assigned_driver", "assignment_expires_at",
            "status", "accepted_at",
        ])

        profile.is_on_ride = True
        profile.save(update_fields=["is_on_ride"])

        # Notify passenger via WebSocket
        _notify_passenger_ws(ride, "driver_assigned", {
            "status": "accepted",
            "driver_name": request.user.full_name,
            "driver_id": request.user.id,
        })

        # Notify passenger via push
        _send_ride_notification(
            ride.passenger,
            "Chauffeur trouvé !",
            f"{request.user.full_name} arrive vers vous.",
            {"ride_id": str(ride.id), "type": "ride_accepted"},
        )

        return Response(RideSerializer(ride).data)


class DeclineRideView(APIView):
    """Driver declines a ride — reassign to next nearest driver."""

    permission_classes = [permissions.IsAuthenticated, IsApprovedDriver]

    def post(self, request, ride_id):
        try:
            ride = Ride.objects.get(id=ride_id, status=Ride.Status.REQUESTED)
        except Ride.DoesNotExist:
            return Response(
                {"detail": "Course non disponible."},
                status=status.HTTP_404_NOT_FOUND,
            )

        # Record this driver as having declined
        declined = ride.declined_driver_ids or []
        if request.user.id not in declined:
            declined.append(request.user.id)
        ride.declined_driver_ids = declined
        ride.assigned_driver = None
        ride.assignment_expires_at = None
        ride.save(update_fields=["declined_driver_ids", "assigned_driver", "assignment_expires_at"])

        # Try next nearest driver
        _auto_assign_nearest_driver(ride)

        return Response(RideSerializer(ride).data)


class TimeoutRideAssignmentView(APIView):
    """Called when assignment timer expires — same as decline, auto-reassign."""

    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, ride_id):
        try:
            ride = Ride.objects.get(id=ride_id, status=Ride.Status.REQUESTED)
        except Ride.DoesNotExist:
            return Response(
                {"detail": "Course non disponible."},
                status=status.HTTP_404_NOT_FOUND,
            )

        # Only allow if assignment has actually expired or the caller is the passenger
        if ride.assigned_driver:
            declined = ride.declined_driver_ids or []
            if ride.assigned_driver.id not in declined:
                declined.append(ride.assigned_driver.id)
            ride.declined_driver_ids = declined

        ride.assigned_driver = None
        ride.assignment_expires_at = None
        ride.save(update_fields=["declined_driver_ids", "assigned_driver", "assignment_expires_at"])

        _auto_assign_nearest_driver(ride)

        return Response(RideSerializer(ride).data)


class StartRideView(APIView):
    """Driver starts the ride (passenger picked up)."""

    permission_classes = [permissions.IsAuthenticated, IsApprovedDriver]

    def post(self, request, ride_id):
        try:
            ride = Ride.objects.get(
                id=ride_id,
                driver=request.user,
                status__in=[Ride.Status.ACCEPTED, Ride.Status.DRIVER_ARRIVING],
            )
        except Ride.DoesNotExist:
            return Response(
                {"detail": "Course non trouvée."},
                status=status.HTTP_404_NOT_FOUND,
            )

        ride.status = Ride.Status.IN_PROGRESS
        ride.started_at = timezone.now()
        ride.save(update_fields=["status", "started_at"])

        _send_ride_notification(
            ride.passenger,
            "Course démarrée",
            "Votre course est en cours.",
            {"ride_id": str(ride.id), "type": "ride_started"},
        )

        return Response(RideSerializer(ride).data)


class CompleteRideView(APIView):
    """Driver completes the ride."""

    permission_classes = [permissions.IsAuthenticated, IsApprovedDriver]

    def post(self, request, ride_id):
        try:
            ride = Ride.objects.get(
                id=ride_id,
                driver=request.user,
                status=Ride.Status.IN_PROGRESS,
            )
        except Ride.DoesNotExist:
            return Response(
                {"detail": "Course non trouvée."},
                status=status.HTTP_404_NOT_FOUND,
            )

        ride.status = Ride.Status.COMPLETED
        ride.completed_at = timezone.now()
        ride.final_price = ride.final_price or ride.estimated_price
        ride.calculate_commission()
        ride.save()

        # Update driver profile
        profile = request.user.driver_profile
        profile.is_on_ride = False
        profile.total_rides += 1
        profile.total_earnings += ride.driver_earnings
        profile.save(update_fields=["is_on_ride", "total_rides", "total_earnings"])

        _send_ride_notification(
            ride.passenger,
            "Course terminée",
            f"Montant : {ride.final_price} CDF",
            {"ride_id": str(ride.id), "type": "ride_completed"},
        )

        return Response(RideSerializer(ride).data)


class CancelRideView(APIView):
    """Cancel a ride (by passenger or driver)."""

    def post(self, request, ride_id):
        cancellable = [
            Ride.Status.REQUESTED,
            Ride.Status.ACCEPTED,
            Ride.Status.DRIVER_ARRIVING,
        ]
        try:
            ride = Ride.objects.get(id=ride_id, status__in=cancellable)
        except Ride.DoesNotExist:
            return Response(
                {"detail": "Course non trouvée ou non annulable."},
                status=status.HTTP_404_NOT_FOUND,
            )

        # Verify user is passenger or driver on this ride
        if request.user != ride.passenger and request.user != ride.driver:
            return Response(
                {"detail": "Non autorisé."}, status=status.HTTP_403_FORBIDDEN
            )

        serializer = RideCancelSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        if request.user == ride.passenger:
            ride.status = Ride.Status.CANCELLED_BY_PASSENGER
        else:
            ride.status = Ride.Status.CANCELLED_BY_DRIVER

        ride.cancellation_reason = serializer.validated_data.get("reason", "")
        ride.cancelled_at = timezone.now()
        ride.save(update_fields=["status", "cancellation_reason", "cancelled_at"])

        # Free up driver
        if ride.driver and hasattr(ride.driver, "driver_profile"):
            ride.driver.driver_profile.is_on_ride = False
            ride.driver.driver_profile.save(update_fields=["is_on_ride"])

        return Response(RideSerializer(ride).data)


class RideDetailView(generics.RetrieveAPIView):
    """Get ride details."""

    serializer_class = RideSerializer
    lookup_field = "id"
    lookup_url_kwarg = "ride_id"

    def get_queryset(self):
        user = self.request.user
        from django.db.models import Q
        return Ride.objects.filter(Q(passenger=user) | Q(driver=user))


class PassengerRideHistoryView(generics.ListAPIView):
    """Get ride history for the current passenger."""

    serializer_class = RideSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        return Ride.objects.filter(passenger=self.request.user)


class DriverRideHistoryView(generics.ListAPIView):
    """Get ride history for the current driver."""

    serializer_class = RideSerializer
    permission_classes = [permissions.IsAuthenticated, IsDriver]

    def get_queryset(self):
        return Ride.objects.filter(driver=self.request.user)


class RideLocationLogView(APIView):
    """Log GPS position during ride (by driver)."""

    permission_classes = [permissions.IsAuthenticated, IsApprovedDriver]

    def post(self, request, ride_id):
        try:
            ride = Ride.objects.get(
                id=ride_id,
                driver=request.user,
                status=Ride.Status.IN_PROGRESS,
            )
        except Ride.DoesNotExist:
            return Response(
                {"detail": "Course non trouvée."},
                status=status.HTTP_404_NOT_FOUND,
            )

        serializer = RideLocationLogSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        serializer.save(ride=ride)
        return Response(serializer.data, status=status.HTTP_201_CREATED)

    def get(self, request, ride_id):
        """Get all GPS logs for a ride."""
        from django.db.models import Q
        ride = Ride.objects.filter(
            id=ride_id
        ).filter(
            Q(passenger=request.user) | Q(driver=request.user)
        ).first()
        if not ride:
            return Response(status=status.HTTP_404_NOT_FOUND)
        logs = ride.location_logs.all()
        return Response(RideLocationLogSerializer(logs, many=True).data)


class SOSAlertView(APIView):
    """Create SOS alert during a ride."""

    def post(self, request, ride_id):
        try:
            ride = Ride.objects.get(id=ride_id, status=Ride.Status.IN_PROGRESS)
        except Ride.DoesNotExist:
            return Response(
                {"detail": "Course non trouvée."},
                status=status.HTTP_404_NOT_FOUND,
            )

        if request.user != ride.passenger and request.user != ride.driver:
            return Response(status=status.HTTP_403_FORBIDDEN)

        serializer = SOSAlertSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        alert = serializer.save(ride=ride, triggered_by=request.user)

        logger.critical(
            "SOS ALERT: ride=%s user=%s lat=%s lng=%s",
            ride.id, request.user.id, alert.latitude, alert.longitude,
        )

        # Notify admin (critical)
        _send_ride_notification(
            None,  # Admin channel
            "🚨 ALERTE SOS",
            f"Course {ride.id} – {request.user.full_name}",
            {"ride_id": str(ride.id), "type": "sos", "alert_id": str(alert.id)},
            admin_alert=True,
        )

        return Response(SOSAlertSerializer(alert).data, status=status.HTTP_201_CREATED)


class DriverPendingRidesView(generics.ListAPIView):
    """Get nearby pending ride requests for driver."""

    serializer_class = RideSerializer
    permission_classes = [permissions.IsAuthenticated, IsApprovedDriver]

    def get_queryset(self):
        profile = self.request.user.driver_profile
        if not profile.current_latitude or not profile.current_longitude:
            return Ride.objects.none()

        lat = float(profile.current_latitude)
        lng = float(profile.current_longitude)
        delta = 5 / 111.0  # 5km radius

        return Ride.objects.filter(
            status=Ride.Status.REQUESTED,
            pickup_latitude__range=(lat - delta, lat + delta),
            pickup_longitude__range=(lng - delta, lng + delta),
        ).order_by("requested_at")[:10]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def _auto_assign_nearest_driver(ride):
    """Find the nearest available driver and assign them to this ride.

    Sends a targeted WebSocket notification to that specific driver.
    If no driver is available, marks ride as no_driver.
    """
    lat = float(ride.pickup_latitude)
    lng = float(ride.pickup_longitude)
    delta = 15 / 111.0  # 15km search radius

    declined = ride.declined_driver_ids or []

    drivers = DriverProfile.objects.filter(
        status=DriverProfile.Status.APPROVED,
        is_online=True,
        is_on_ride=False,
        current_latitude__range=(lat - delta, lat + delta),
        current_longitude__range=(lng - delta, lng + delta),
    ).exclude(
        user_id__in=declined,
    ).select_related("user")

    if not drivers.exists():
        ride.status = Ride.Status.NO_DRIVER
        ride.assigned_driver = None
        ride.assignment_expires_at = None
        ride.save(update_fields=["status", "assigned_driver", "assignment_expires_at"])
        # Notify passenger that no drivers are available
        _notify_passenger_ws(ride, "no_driver", {
            "status": "no_driver",
            "message": "Aucun chauffeur disponible pour le moment.",
        })
        _send_ride_notification(
            ride.passenger,
            "Aucun chauffeur disponible",
            "Réessayez dans quelques instants.",
            {"ride_id": str(ride.id), "type": "no_driver"},
        )
        return

    # Sort by real haversine distance and pick the closest
    driver_distances = []
    for d in drivers:
        if d.current_latitude and d.current_longitude:
            dist = haversine_distance(
                lat, lng,
                float(d.current_latitude), float(d.current_longitude),
            )
            driver_distances.append((d, dist))

    if not driver_distances:
        ride.status = Ride.Status.NO_DRIVER
        ride.save(update_fields=["status"])
        _notify_passenger_ws(ride, "no_driver", {
            "status": "no_driver",
            "message": "Aucun chauffeur disponible pour le moment.",
        })
        return

    driver_distances.sort(key=lambda x: x[1])
    nearest_profile, distance_km = driver_distances[0]

    # Assign this driver
    ride.assigned_driver = nearest_profile.user
    ride.assignment_expires_at = timezone.now() + timedelta(seconds=DRIVER_ACCEPT_TIMEOUT)
    ride.save(update_fields=["assigned_driver", "assignment_expires_at"])

    # Notify the specific driver via WebSocket
    _send_ride_to_driver_ws(nearest_profile.user.id, ride, distance_km)

    # Also send push notification
    _send_ride_notification(
        nearest_profile.user,
        "Nouvelle course pour vous !",
        f"De {ride.pickup_address} à {ride.destination_address} ({distance_km:.1f} km)",
        {"ride_id": str(ride.id), "type": "new_ride_request"},
    )

    # Notify passenger that a driver was found and is being requested
    _notify_passenger_ws(ride, "driver_assigned", {
        "status": "driver_requested",
        "assigned_driver": {
            "name": nearest_profile.user.full_name,
            "vehicle": f"{nearest_profile.vehicle_make} {nearest_profile.vehicle_model}",
            "rating": float(nearest_profile.rating_average) if nearest_profile.rating_average else None,
            "distance_km": round(distance_km, 1),
        },
        "expires_at": ride.assignment_expires_at.isoformat(),
        "timeout_seconds": DRIVER_ACCEPT_TIMEOUT,
    })


def _send_ride_to_driver_ws(driver_user_id, ride, distance_km):
    """Send ride request to a specific driver via WebSocket channel layer."""
    try:
        channel_layer = get_channel_layer()
        async_to_sync(channel_layer.group_send)(
            f"driver_{driver_user_id}",
            {
                "type": "ride_request",
                "data": {
                    "id": str(ride.id),
                    "pickup_address": ride.pickup_address,
                    "pickup_latitude": str(ride.pickup_latitude),
                    "pickup_longitude": str(ride.pickup_longitude),
                    "destination_address": ride.destination_address,
                    "destination_latitude": str(ride.destination_latitude),
                    "destination_longitude": str(ride.destination_longitude),
                    "estimated_price": str(ride.estimated_price),
                    "distance_km": str(ride.distance_km or ""),
                    "passenger_name": ride.passenger.full_name,
                    "distance_to_pickup_km": round(distance_km, 1),
                    "timeout_seconds": DRIVER_ACCEPT_TIMEOUT,
                },
            },
        )
    except Exception:
        logger.exception("Failed to send ride request to driver via WS")


def _notify_passenger_ws(ride, event_type, data):
    """Send real-time update to the passenger via the ride tracking WebSocket."""
    try:
        channel_layer = get_channel_layer()
        async_to_sync(channel_layer.group_send)(
            f"ride_{ride.id}",
            {
                "type": "status.update",
                "status": event_type,
                "message": "",
                **data,
            },
        )
    except Exception:
        logger.exception("Failed to send WS notification to passenger")


def _send_ride_notification(user, title, body, data=None, admin_alert=False):
    """Helper to send notification (delegates to notification service)."""
    try:
        from apps.notifications.services import send_push_notification

        if admin_alert:
            from django.contrib.auth import get_user_model
            User = get_user_model()
            admins = User.objects.filter(role="admin", is_active=True)
            for admin_user in admins:
                send_push_notification(admin_user, title, body, data)
        elif user:
            send_push_notification(user, title, body, data)
    except Exception:
        logger.exception("Failed to send notification")
