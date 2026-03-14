import logging

from django.conf import settings
from django.utils import timezone
from rest_framework import generics, permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.models import DriverProfile
from apps.accounts.permissions import IsApprovedDriver, IsDriver, IsPassenger
from apps.promotions.models import PromoCode, PromoUsage

from .models import Ride, RideLocationLog, SOSAlert
from .pricing import estimate_price
from .serializers import (
    EstimatePriceSerializer,
    RideCancelSerializer,
    RideCreateSerializer,
    RideLocationLogSerializer,
    RideSerializer,
    SOSAlertSerializer,
)

logger = logging.getLogger(__name__)


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

        # Find nearest driver & send notification (async in production)
        _notify_nearby_drivers(ride)

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

        profile = request.user.driver_profile
        if profile.is_on_ride:
            return Response(
                {"detail": "Vous êtes déjà en course."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        ride.driver = request.user
        ride.status = Ride.Status.ACCEPTED
        ride.accepted_at = timezone.now()
        ride.save(update_fields=["driver", "status", "accepted_at"])

        profile.is_on_ride = True
        profile.save(update_fields=["is_on_ride"])

        # Notify passenger
        _send_ride_notification(
            ride.passenger,
            "Chauffeur trouvé !",
            f"{request.user.full_name} arrive vers vous.",
            {"ride_id": str(ride.id), "type": "ride_accepted"},
        )

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
def _notify_nearby_drivers(ride):
    """Send push notification to nearby drivers."""
    lat = float(ride.pickup_latitude)
    lng = float(ride.pickup_longitude)
    delta = 5 / 111.0

    drivers = DriverProfile.objects.filter(
        status=DriverProfile.Status.APPROVED,
        is_online=True,
        is_on_ride=False,
        current_latitude__range=(lat - delta, lat + delta),
        current_longitude__range=(lng - delta, lng + delta),
    ).select_related("user")[:10]

    for d in drivers:
        _send_ride_notification(
            d.user,
            "Nouvelle course disponible",
            f"De {ride.pickup_address} à {ride.destination_address}",
            {"ride_id": str(ride.id), "type": "new_ride_request"},
        )


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
