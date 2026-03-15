import logging

from django.utils import timezone
from rest_framework import generics, permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.permissions import IsDriver
from apps.rides.models import Ride

from .maxicash import MaxicashClient
from .models import DriverPayout, Payment
from .serializers import (
    DriverPayoutSerializer,
    InitiatePaymentSerializer,
    PaymentSerializer,
)

logger = logging.getLogger(__name__)


class InitiatePaymentView(APIView):
    """Initiate payment for a completed ride."""

    def post(self, request):
        serializer = InitiatePaymentSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        try:
            ride = Ride.objects.get(
                id=data["ride_id"],
                passenger=request.user,
                status=Ride.Status.COMPLETED,
            )
        except Ride.DoesNotExist:
            return Response(
                {"detail": "Course non trouvée ou non terminée."},
                status=status.HTTP_404_NOT_FOUND,
            )

        # Check if already paid
        if hasattr(ride, "payment") and ride.payment.status == Payment.Status.COMPLETED:
            return Response(
                {"detail": "Cette course est déjà payée."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        amount = float(ride.final_price or ride.estimated_price)
        method = data["method"]

        payment, created = Payment.objects.get_or_create(
            ride=ride,
            defaults={
                "payer": request.user,
                "amount": amount,
                "method": method,
                "phone_number": data.get("phone_number", request.user.phone_number),
            },
        )

        if method == Payment.Method.MOBILE_MONEY:
            client = MaxicashClient()
            result = client.initiate_payment(
                phone_number=payment.phone_number,
                amount=amount,
                reference=str(ride.id),
            )
            payment.provider_response = result.get("raw")
            if result["success"]:
                payment.status = Payment.Status.PROCESSING
                payment.provider_transaction_id = result["transaction_id"]
            else:
                payment.status = Payment.Status.FAILED
            payment.save()
        elif method == Payment.Method.CASH:
            payment.status = Payment.Status.COMPLETED
            payment.completed_at = timezone.now()
            payment.save()

        return Response(PaymentSerializer(payment).data)


class PaymentStatusView(generics.RetrieveAPIView):
    """Check payment status."""

    serializer_class = PaymentSerializer
    lookup_field = "id"
    lookup_url_kwarg = "payment_id"

    def get_queryset(self):
        return Payment.objects.filter(payer=self.request.user)


class PaymentWebhookView(APIView):
    """Webhook for Maxicash payment status updates."""

    permission_classes = [permissions.AllowAny]

    def post(self, request):
        transaction_id = request.data.get("transactionId")
        payment_status = request.data.get("status")

        if not transaction_id:
            return Response(status=status.HTTP_400_BAD_REQUEST)

        try:
            payment = Payment.objects.get(provider_transaction_id=transaction_id)
        except Payment.DoesNotExist:
            return Response(status=status.HTTP_404_NOT_FOUND)

        if payment_status == "success":
            payment.status = Payment.Status.COMPLETED
            payment.completed_at = timezone.now()
        elif payment_status == "failed":
            payment.status = Payment.Status.FAILED

        payment.provider_response = request.data
        payment.save()

        return Response({"status": "ok"})


class PaymentHistoryView(generics.ListAPIView):
    """Get payment history."""

    serializer_class = PaymentSerializer

    def get_queryset(self):
        return Payment.objects.filter(payer=self.request.user)


class DriverEarningsView(APIView):
    """Get driver earnings summary."""

    permission_classes = [permissions.IsAuthenticated, IsDriver]

    def get(self, request):
        profile = request.user.driver_profile
        recent_rides = Ride.objects.filter(
            driver=request.user,
            status=Ride.Status.COMPLETED,
        ).order_by("-completed_at")[:10]

        today = timezone.now().date()
        today_rides = Ride.objects.filter(
            driver=request.user,
            status=Ride.Status.COMPLETED,
            completed_at__date=today,
        )
        today_earnings = sum(r.driver_earnings for r in today_rides)

        return Response({
            "total_earnings": str(profile.total_earnings),
            "total_rides": profile.total_rides,
            "today_earnings": str(today_earnings),
            "today_rides": today_rides.count(),
            "rating": str(profile.rating_average),
        })


class DriverPayoutHistoryView(generics.ListAPIView):
    """Get driver payout history."""

    serializer_class = DriverPayoutSerializer
    permission_classes = [permissions.IsAuthenticated, IsDriver]

    def get_queryset(self):
        return DriverPayout.objects.filter(driver=self.request.user)
