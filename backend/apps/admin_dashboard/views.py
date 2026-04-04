from django.contrib.auth import get_user_model
from django.db.models import Avg, Count, Q, Sum
from django.db.models.functions import TruncDate, TruncMonth
from django.utils import timezone
from rest_framework import generics, permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.models import DriverProfile
from apps.accounts.permissions import IsAdmin
from apps.notifications.models import Notification
from apps.payments.models import Payment
from apps.promotions.models import PromoCode
from apps.reviews.models import Review
from apps.rides.models import Ride, SOSAlert

from .serializers import (
    AdminDriverProfileSerializer,
    AdminNotificationSerializer,
    AdminPaymentSerializer,
    AdminPromoCodeSerializer,
    AdminRegisterSerializer,
    AdminReviewSerializer,
    AdminRideSerializer,
    AdminSOSAlertSerializer,
    AdminUserSerializer,
)

User = get_user_model()


class AdminRegisterView(APIView):
    """Create a new admin account. Requires existing admin authentication."""

    permission_classes = [permissions.IsAuthenticated, IsAdmin]

    def post(self, request):
        serializer = AdminRegisterSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.save()
        return Response(
            {
                "user": AdminUserSerializer(user).data,
                "message": "Administrateur créé avec succès.",
            },
            status=status.HTTP_201_CREATED,
        )


class DashboardStatsView(APIView):
    """Global statistics for admin dashboard."""

    permission_classes = [permissions.IsAuthenticated, IsAdmin]

    def get(self, request):
        now = timezone.now()
        today = now.date()
        month_start = today.replace(day=1)

        total_users = User.objects.filter(role="passenger").count()
        total_drivers = User.objects.filter(role="driver").count()
        approved_drivers = DriverProfile.objects.filter(status="approved").count()
        pending_drivers = DriverProfile.objects.filter(status="pending").count()
        online_drivers = DriverProfile.objects.filter(
            status="approved", is_online=True
        ).count()

        total_rides = Ride.objects.count()
        completed_rides = Ride.objects.filter(status="completed").count()
        today_rides = Ride.objects.filter(requested_at__date=today).count()
        active_rides = Ride.objects.filter(
            status__in=["requested", "accepted", "driver_arriving", "in_progress"]
        ).count()

        total_revenue = (
            Payment.objects.filter(status="completed").aggregate(
                total=Sum("amount")
            )["total"]
            or 0
        )
        today_revenue = (
            Payment.objects.filter(
                status="completed", completed_at__date=today
            ).aggregate(total=Sum("amount"))["total"]
            or 0
        )
        month_revenue = (
            Payment.objects.filter(
                status="completed", completed_at__date__gte=month_start
            ).aggregate(total=Sum("amount"))["total"]
            or 0
        )

        total_commission = (
            Ride.objects.filter(status="completed").aggregate(
                total=Sum("commission_amount")
            )["total"]
            or 0
        )

        active_sos = SOSAlert.objects.filter(status="active").count()

        return Response({
            "users": {
                "total_passengers": total_users,
                "total_drivers": total_drivers,
                "approved_drivers": approved_drivers,
                "pending_drivers": pending_drivers,
                "online_drivers": online_drivers,
            },
            "rides": {
                "total": total_rides,
                "completed": completed_rides,
                "today": today_rides,
                "active": active_rides,
            },
            "revenue": {
                "total": str(total_revenue),
                "today": str(today_revenue),
                "month": str(month_revenue),
                "total_commission": str(total_commission),
                "currency": "CDF",
            },
            "alerts": {
                "active_sos": active_sos,
            },
        })


class DashboardChartDataView(APIView):
    """Chart data for rides and revenue over time."""

    permission_classes = [permissions.IsAuthenticated, IsAdmin]

    def get(self, request):
        period = request.query_params.get("period", "30")  # days
        days = min(int(period), 365)
        start_date = timezone.now() - timezone.timedelta(days=days)

        rides_by_day = (
            Ride.objects.filter(requested_at__gte=start_date)
            .annotate(date=TruncDate("requested_at"))
            .values("date")
            .annotate(count=Count("id"))
            .order_by("date")
        )

        revenue_by_day = (
            Payment.objects.filter(
                status="completed", completed_at__gte=start_date
            )
            .annotate(date=TruncDate("completed_at"))
            .values("date")
            .annotate(total=Sum("amount"))
            .order_by("date")
        )

        return Response({
            "rides_by_day": [
                {"date": str(r["date"]), "count": r["count"]}
                for r in rides_by_day
            ],
            "revenue_by_day": [
                {"date": str(r["date"]), "total": str(r["total"])}
                for r in revenue_by_day
            ],
        })


# ---------------------------------------------------------------------------
# Admin CRUD endpoints
# ---------------------------------------------------------------------------
class AdminUserListView(generics.ListAPIView):
    """List all users (with filters)."""

    serializer_class = AdminUserSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdmin]
    filterset_fields = ["role", "is_active", "is_phone_verified"]
    search_fields = ["full_name", "phone_number", "email"]

    def get_queryset(self):
        return User.objects.all()


class AdminUserDetailView(generics.RetrieveUpdateDestroyAPIView):
    """View/edit/deactivate a user."""

    serializer_class = AdminUserSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdmin]
    lookup_field = "id"

    def get_queryset(self):
        return User.objects.all()

    def perform_destroy(self, instance):
        # Soft-delete: deactivate instead
        instance.is_active = False
        instance.save(update_fields=["is_active"])


class AdminDriverListView(generics.ListAPIView):
    """List all driver profiles."""

    serializer_class = AdminDriverProfileSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdmin]
    filterset_fields = ["status", "is_online"]

    def get_queryset(self):
        return DriverProfile.objects.select_related("user").all()


class AdminDriverApprovalView(APIView):
    """Approve or reject a driver."""

    permission_classes = [permissions.IsAuthenticated, IsAdmin]

    def post(self, request, driver_id):
        try:
            profile = DriverProfile.objects.get(id=driver_id)
        except DriverProfile.DoesNotExist:
            return Response(status=status.HTTP_404_NOT_FOUND)

        action = request.data.get("action")  # "approve" or "reject"
        if action == "approve":
            profile.status = DriverProfile.Status.APPROVED
            profile.rejection_reason = ""
        elif action == "reject":
            profile.status = DriverProfile.Status.REJECTED
            profile.rejection_reason = request.data.get("reason", "")
        elif action == "suspend":
            profile.status = DriverProfile.Status.SUSPENDED
        else:
            return Response(
                {"detail": "Action invalide. Utilisez: approve, reject, suspend."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        profile.save(update_fields=["status", "rejection_reason"])
        return Response(AdminDriverProfileSerializer(profile).data)


class AdminRideListView(generics.ListAPIView):
    """List all rides."""

    serializer_class = AdminRideSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdmin]
    filterset_fields = ["status"]
    search_fields = ["passenger__full_name", "driver__full_name", "pickup_address"]

    def get_queryset(self):
        return Ride.objects.select_related("passenger", "driver").all()


class AdminRideDetailView(generics.RetrieveAPIView):
    """View ride details."""

    serializer_class = AdminRideSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdmin]
    lookup_field = "id"

    def get_queryset(self):
        return Ride.objects.select_related("passenger", "driver").all()


class AdminSOSAlertListView(generics.ListAPIView):
    """List SOS alerts."""

    serializer_class = AdminSOSAlertSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdmin]
    filterset_fields = ["status"]

    def get_queryset(self):
        return SOSAlert.objects.select_related("ride", "triggered_by").all()


class AdminSOSResolveView(APIView):
    """Resolve an SOS alert."""

    permission_classes = [permissions.IsAuthenticated, IsAdmin]

    def post(self, request, alert_id):
        try:
            alert = SOSAlert.objects.get(id=alert_id)
        except SOSAlert.DoesNotExist:
            return Response(status=status.HTTP_404_NOT_FOUND)

        alert.status = SOSAlert.Status.RESOLVED
        alert.resolved_at = timezone.now()
        alert.save(update_fields=["status", "resolved_at"])
        return Response(AdminSOSAlertSerializer(alert).data)


# ---------------------------------------------------------------------------
# Payments
# ---------------------------------------------------------------------------
class AdminPaymentListView(generics.ListAPIView):
    """List all payments."""

    serializer_class = AdminPaymentSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdmin]
    filterset_fields = ["status", "method"]
    search_fields = ["payer__full_name", "provider_transaction_id"]

    def get_queryset(self):
        return Payment.objects.select_related("ride", "payer").order_by("-created_at")


# ---------------------------------------------------------------------------
# Promotions
# ---------------------------------------------------------------------------
class AdminPromoListCreateView(generics.ListCreateAPIView):
    """List or create promo codes."""

    serializer_class = AdminPromoCodeSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdmin]
    filterset_fields = ["is_active", "discount_type"]
    search_fields = ["code", "description"]

    def get_queryset(self):
        return PromoCode.objects.order_by("-created_at")


class AdminPromoDetailView(generics.RetrieveUpdateAPIView):
    """View or update a promo code."""

    serializer_class = AdminPromoCodeSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdmin]
    lookup_field = "id"

    def get_queryset(self):
        return PromoCode.objects.all()


# ---------------------------------------------------------------------------
# Reviews
# ---------------------------------------------------------------------------
class AdminReviewListView(generics.ListAPIView):
    """List all reviews."""

    serializer_class = AdminReviewSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdmin]
    filterset_fields = ["rating"]
    search_fields = ["reviewer__full_name", "reviewed_user__full_name"]

    def get_queryset(self):
        return Review.objects.select_related(
            "ride", "reviewer", "reviewed_user"
        ).order_by("-created_at")


# ---------------------------------------------------------------------------
# Notifications
# ---------------------------------------------------------------------------
class AdminNotificationListView(generics.ListAPIView):
    """List all notifications."""

    serializer_class = AdminNotificationSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdmin]
    filterset_fields = ["channel", "category", "is_read"]

    def get_queryset(self):
        return Notification.objects.select_related("recipient").order_by("-sent_at")
