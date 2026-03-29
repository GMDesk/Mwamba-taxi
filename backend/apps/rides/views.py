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
from apps.payments.models import Payment
from apps.payments.wallet import (
    get_or_create_wallet,
    hold_funds,
    process_ride_payment,
    release_hold,
)
from apps.promotions.models import PromoCode, PromoUsage

from .models import Ride, RideLocationLog, SOSAlert
from .pricing import estimate_price, haversine_distance
from .scoring import (
    DRIVER_ACCEPT_TIMEOUT,
    MAX_SEARCH_RADIUS_KM,
    rank_drivers,
    update_driver_stats_on_accept,
    update_driver_stats_on_cancel,
    update_driver_stats_on_decline,
)
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

        # Include wallet balance if authenticated
        if request.user.is_authenticated:
            wallet = get_or_create_wallet(request.user)
            result["wallet_balance"] = float(wallet.balance)
            result["wallet_sufficient"] = wallet.can_afford(
                __import__("decimal").Decimal(str(result["estimated_price"]))
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
                Ride.Status.DRIVER_ARRIVED,
                Ride.Status.IN_PROGRESS,
            ],
        ).exists()
        if active:
            return Response(
                {"detail": "Vous avez déjà une course en cours."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Payment method (wallet or cash)
        payment_method = request.data.get("payment_method", "wallet")

        ride = serializer.save(passenger=request.user)

        # Pre-authorize wallet if paying by wallet
        if payment_method == "wallet":
            from decimal import Decimal
            wallet = get_or_create_wallet(request.user)
            estimated = Decimal(str(ride.estimated_price))
            if wallet.can_afford(estimated):
                hold_funds(wallet, estimated, ride=ride)
            else:
                # Not enough balance — still allow ride (fallback to cash)
                payment_method = "cash"

        # Create payment record
        Payment.objects.create(
            ride=ride,
            payer=request.user,
            amount=ride.estimated_price,
            method=payment_method,
        )

        # Auto-assign the nearest available driver
        _auto_assign_nearest_driver(ride)

        data = RideSerializer(ride).data
        data["payment_method"] = payment_method
        return Response(data, status=status.HTTP_201_CREATED)


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

        # Update scoring stats
        update_driver_stats_on_accept(profile)

        # Notify passenger via WebSocket
        _notify_passenger_ws(ride, "driver_assigned", {
            "status": "accepted",
            "driver_name": request.user.full_name,
            "driver_id": str(request.user.id),
            "driver_phone": request.user.phone_number,
            "driver_photo": request.user.avatar.url if request.user.avatar else None,
            "driver_rating": float(profile.rating_average) if profile.rating_average else None,
            "vehicle": f"{profile.vehicle_make} {profile.vehicle_model}",
            "vehicle_color": profile.vehicle_color,
            "license_plate": profile.license_plate,
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

        # Update scoring stats
        if hasattr(request.user, "driver_profile"):
            update_driver_stats_on_decline(request.user.driver_profile)

        # Try next best driver
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
                status__in=[Ride.Status.ACCEPTED, Ride.Status.DRIVER_ARRIVING, Ride.Status.DRIVER_ARRIVED],
            )
        except Ride.DoesNotExist:
            return Response(
                {"detail": "Course non trouvée."},
                status=status.HTTP_404_NOT_FOUND,
            )

        ride.status = Ride.Status.IN_PROGRESS
        ride.started_at = timezone.now()
        ride.save(update_fields=["status", "started_at"])

        _notify_passenger_ws(ride, "in_progress", {
            "status": "in_progress",
        })

        _send_ride_notification(
            ride.passenger,
            "Course démarrée",
            "Votre course est en cours.",
            {"ride_id": str(ride.id), "type": "ride_started"},
        )

        return Response(RideSerializer(ride).data)


class DriverArrivedView(APIView):
    """Driver notifies they have arrived at the pickup point."""

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

        ride.status = Ride.Status.DRIVER_ARRIVED
        ride.save(update_fields=["status"])

        _notify_passenger_ws(ride, "driver_arrived", {
            "status": "driver_arrived",
        })

        _send_ride_notification(
            ride.passenger,
            "Chauffeur arrivé",
            "Votre chauffeur est arrivé au point de prise en charge.",
            {"ride_id": str(ride.id), "type": "driver_arrived"},
        )

        return Response(RideSerializer(ride).data)


class DriverArrivingView(APIView):
    """Driver marks themselves as en route to pickup (accepted → driver_arriving)."""

    permission_classes = [permissions.IsAuthenticated, IsApprovedDriver]

    def post(self, request, ride_id):
        try:
            ride = Ride.objects.get(
                id=ride_id,
                driver=request.user,
                status=Ride.Status.ACCEPTED,
            )
        except Ride.DoesNotExist:
            return Response(
                {"detail": "Course non trouvée."},
                status=status.HTTP_404_NOT_FOUND,
            )

        ride.status = Ride.Status.DRIVER_ARRIVING
        ride.save(update_fields=["status"])

        _notify_passenger_ws(ride, "driver_arriving", {
            "status": "driver_arriving",
        })

        _send_ride_notification(
            ride.passenger,
            "Chauffeur en route",
            "Votre chauffeur est en route vers vous.",
            {"ride_id": str(ride.id), "type": "driver_arriving"},
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

        # Process payment based on method
        payment_info = {}
        try:
            payment = Payment.objects.get(ride=ride)
        except Payment.DoesNotExist:
            payment = None

        if payment and payment.method == Payment.Method.WALLET:
            try:
                payment_info = process_ride_payment(ride)
                payment.status = Payment.Status.COMPLETED
                payment.completed_at = timezone.now()
                payment.save(update_fields=["status", "completed_at", "updated_at"])
            except Exception as e:
                logger.error("Wallet payment failed for ride %s: %s", ride.id, e)
                # Fallback: calculate commission normally, mark payment failed
                ride.calculate_commission()
                ride.save(update_fields=["commission_amount", "driver_earnings"])
                if payment:
                    payment.status = Payment.Status.FAILED
                    payment.save(update_fields=["status", "updated_at"])
                payment_info = {"method": "cash", "error": str(e)}
        else:
            # Cash payment — just calculate commission
            ride.calculate_commission()
            if payment:
                payment.status = Payment.Status.COMPLETED
                payment.completed_at = timezone.now()
                payment.save(update_fields=["status", "completed_at", "updated_at"])
            payment_info = {
                "method": "cash",
                "total_price": float(ride.final_price),
                "commission": float(ride.commission_amount),
                "driver_share": float(ride.driver_earnings),
            }

        ride.save()

        # Update driver profile
        profile = request.user.driver_profile
        profile.is_on_ride = False
        profile.total_rides += 1
        profile.total_earnings += ride.driver_earnings
        profile.save(update_fields=["is_on_ride", "total_rides", "total_earnings"])

        _notify_passenger_ws(ride, "completed", {
            "status": "completed",
            "final_price": str(ride.final_price),
        })

        _send_ride_notification(
            ride.passenger,
            "Course terminée",
            f"Montant : {ride.final_price} CDF",
            {"ride_id": str(ride.id), "type": "ride_completed", "payment": payment_info},
        )

        return Response(RideSerializer(ride).data)


class CancelRideView(APIView):
    """Cancel a ride (by passenger or driver)."""

    def post(self, request, ride_id):
        cancellable = [
            Ride.Status.REQUESTED,
            Ride.Status.ACCEPTED,
            Ride.Status.DRIVER_ARRIVING,
            Ride.Status.DRIVER_ARRIVED,
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

        is_driver_cancel = request.user != ride.passenger
        if is_driver_cancel:
            ride.status = Ride.Status.CANCELLED_BY_DRIVER
        else:
            ride.status = Ride.Status.CANCELLED_BY_PASSENGER

        ride.cancellation_reason = serializer.validated_data.get("reason", "")
        ride.cancelled_at = timezone.now()
        ride.save(update_fields=["status", "cancellation_reason", "cancelled_at"])

        # Release wallet hold if any
        try:
            passenger_wallet = get_or_create_wallet(ride.passenger)
            if passenger_wallet.held_amount > 0:
                release_hold(passenger_wallet, passenger_wallet.held_amount, ride=ride)
            # Mark payment as refunded
            try:
                payment = Payment.objects.get(ride=ride)
                payment.status = Payment.Status.FAILED
                payment.save(update_fields=["status", "updated_at"])
            except Payment.DoesNotExist:
                pass
        except Exception as e:
            logger.error("Failed to release hold for ride %s: %s", ride.id, e)

        # Free up driver and update stats
        if ride.driver and hasattr(ride.driver, "driver_profile"):
            profile = ride.driver.driver_profile
            profile.is_on_ride = False
            profile.save(update_fields=["is_on_ride"])
            if is_driver_cancel:
                update_driver_stats_on_cancel(profile)

        # Notify both parties via WebSocket
        cancel_status = "cancelled_by_driver" if is_driver_cancel else "cancelled_by_passenger"
        _notify_passenger_ws(ride, cancel_status, {
            "ride_id": str(ride.id),
            "message": "La course a été annulée.",
        })
        # Notify the driver via their personal WS channel
        if ride.driver:
            try:
                channel_layer = get_channel_layer()
                async_to_sync(channel_layer.group_send)(
                    f"driver_{ride.driver.id}",
                    {
                        "type": "ride_cancelled",
                        "ride_id": str(ride.id),
                    },
                )
            except Exception:
                logger.exception("Failed to notify driver of cancellation")

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


class ActiveRideView(APIView):
    """Return the passenger's active ride, if any."""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        ride = (
            Ride.objects.filter(
                passenger=request.user,
                status__in=[
                    Ride.Status.REQUESTED,
                    Ride.Status.ACCEPTED,
                    Ride.Status.DRIVER_ARRIVING,
                    Ride.Status.DRIVER_ARRIVED,
                    Ride.Status.IN_PROGRESS,
                ],
            )
            .order_by("-requested_at")
            .first()
        )
        if ride is None:
            return Response({"active": False}, status=status.HTTP_200_OK)
        data = RideSerializer(ride).data
        data["active"] = True
        return Response(data, status=status.HTTP_200_OK)


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
    """Find the best available driver using the scoring engine and assign them.

    Uses a multi-factor scoring algorithm:
      - ETA / distance (primary)
      - Acceptance rate
      - Rating
      - Recent activity
      - Fair distribution (anti-monopolization)
      - Cancellation penalty

    Sends a targeted WebSocket notification to the best-scoring driver.
    If no driver is available, marks ride as no_driver.
    """
    lat = float(ride.pickup_latitude)
    lng = float(ride.pickup_longitude)
    delta = MAX_SEARCH_RADIUS_KM / 111.0

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

    # Rank drivers using the scoring engine
    ranked = rank_drivers(drivers, lat, lng)

    if not ranked:
        ride.status = Ride.Status.NO_DRIVER
        ride.assigned_driver = None
        ride.assignment_expires_at = None
        ride.save(update_fields=["status", "assigned_driver", "assignment_expires_at"])
        _notify_passenger_ws(ride, "no_driver", {
            "status": "no_driver",
            "message": "Aucun chauffeur disponible pour le moment.",
        })
        return

    best_profile, score_data = ranked[0]
    distance_km = score_data["distance_km"]
    eta_minutes = score_data["eta_minutes"]

    logger.info(
        "Assigning ride %s to driver %s (score=%.1f, dist=%.1fkm, eta=%.1fmin)",
        ride.id, best_profile.user.full_name, score_data["score"],
        distance_km, eta_minutes,
    )

    # Assign this driver
    ride.assigned_driver = best_profile.user
    ride.assignment_expires_at = timezone.now() + timedelta(seconds=DRIVER_ACCEPT_TIMEOUT)
    ride.save(update_fields=["assigned_driver", "assignment_expires_at"])

    # Notify the specific driver via WebSocket
    _send_ride_to_driver_ws(best_profile, ride, distance_km, eta_minutes)

    # Also send push notification
    _send_ride_notification(
        best_profile.user,
        "Nouvelle course pour vous !",
        f"De {ride.pickup_address} à {ride.destination_address} ({distance_km:.1f} km)",
        {"ride_id": str(ride.id), "type": "new_ride_request"},
    )

    # Notify passenger — rich driver info
    _notify_passenger_ws(ride, "driver_assigned", {
        "status": "driver_requested",
        "assigned_driver": {
            "name": best_profile.user.full_name,
            "photo": best_profile.user.avatar.url if best_profile.user.avatar else None,
            "vehicle": f"{best_profile.vehicle_make} {best_profile.vehicle_model}",
            "vehicle_color": best_profile.vehicle_color,
            "license_plate": best_profile.license_plate,
            "rating": float(best_profile.rating_average) if best_profile.rating_average else None,
            "distance_km": round(distance_km, 1),
            "eta_minutes": round(eta_minutes, 1),
        },
        "expires_at": ride.assignment_expires_at.isoformat(),
        "timeout_seconds": DRIVER_ACCEPT_TIMEOUT,
    })


def _send_ride_to_driver_ws(driver_profile, ride, distance_km, eta_minutes=None):
    """Send ride request to a specific driver via WebSocket channel layer.

    Includes rich data: pickup/destination, passenger info, fare, ETA.
    """
    if eta_minutes is None:
        eta_minutes = round((distance_km * 1.3 / 20) * 60, 1)

    try:
        channel_layer = get_channel_layer()
        async_to_sync(channel_layer.group_send)(
            f"driver_{driver_profile.user.id}",
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
                    "eta_to_pickup_minutes": round(eta_minutes, 1),
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
