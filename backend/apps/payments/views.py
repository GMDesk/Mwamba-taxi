import logging
import uuid

from django.utils import timezone
from rest_framework import generics, permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.permissions import IsDriver

from . import pawapay
from .models import DriverPayout, Payment, Wallet, WalletTransaction
from .serializers import (
    DepositSerializer,
    DriverPayoutSerializer,
    PaymentSerializer,
    PayoutRequestSerializer,
    WalletSerializer,
    WalletTransactionSerializer,
)
from .wallet import (
    credit_wallet,
    debit_wallet,
    get_or_create_wallet,
)

logger = logging.getLogger(__name__)


# ═══════════════════════════════════════════════════════════════════════
# WALLET ENDPOINTS
# ═══════════════════════════════════════════════════════════════════════

class WalletDetailView(APIView):
    """Get current user's wallet (balance, held amount, status)."""

    def get(self, request):
        wallet = get_or_create_wallet(request.user)
        return Response(WalletSerializer(wallet).data)


class WalletTransactionListView(generics.ListAPIView):
    """Get wallet transaction history for the current user."""

    serializer_class = WalletTransactionSerializer

    def get_queryset(self):
        wallet = get_or_create_wallet(self.request.user)
        return WalletTransaction.objects.filter(wallet=wallet)


class DepositView(APIView):
    """Initiate wallet top-up via PawaPay Mobile Money."""

    def post(self, request):
        serializer = DepositSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        wallet = get_or_create_wallet(request.user)
        if wallet.status != Wallet.Status.ACTIVE:
            return Response(
                {"detail": "Votre portefeuille est bloqué."},
                status=status.HTTP_403_FORBIDDEN,
            )

        deposit_id = str(uuid.uuid4())
        amount = data["amount"]
        phone = data["phone_number"]

        # Create pending transaction
        tx = WalletTransaction.objects.create(
            wallet=wallet,
            tx_type=WalletTransaction.TxType.DEPOSIT,
            amount=amount,
            balance_after=wallet.balance,  # unchanged until callback
            status=WalletTransaction.Status.PENDING,
            description="Rechargement Mobile Money",
            provider_reference=deposit_id,
            metadata={"phone": phone},
        )

        # Call PawaPay
        result = pawapay.initiate_deposit(
            phone_number=phone,
            amount=float(amount),
            deposit_id=deposit_id,
        )

        if not result["success"]:
            tx.status = WalletTransaction.Status.FAILED
            tx.metadata = {**(tx.metadata or {}), "error": result["raw"]}
            tx.save(update_fields=["status", "metadata"])
            return Response(
                {"detail": "Échec de l'initiation du paiement. Réessayez."},
                status=status.HTTP_502_BAD_GATEWAY,
            )

        return Response({
            "deposit_id": deposit_id,
            "status": "pending",
            "message": "Confirmez le paiement sur votre téléphone.",
        })


# ═══════════════════════════════════════════════════════════════════════
# PAWAPAY CALLBACKS (webhooks)
# ═══════════════════════════════════════════════════════════════════════

class PawapayDepositCallbackView(APIView):
    """Callback from PawaPay when a deposit (top-up) completes or fails.

    IDEMPOTENT: If the transaction is already completed, do nothing.
    """

    permission_classes = [permissions.AllowAny]
    authentication_classes = []

    def post(self, request):
        # Verify signature
        sig = request.headers.get("X-Pawapay-Signature", "")
        if not pawapay.verify_callback_signature(request.body, sig):
            logger.warning("Invalid PawaPay deposit callback signature")
            return Response(status=status.HTTP_401_UNAUTHORIZED)

        deposit_id = request.data.get("depositId", "")
        cb_status = request.data.get("status", "")

        if not deposit_id:
            return Response(status=status.HTTP_400_BAD_REQUEST)

        try:
            tx = WalletTransaction.objects.select_related("wallet").get(
                provider_reference=deposit_id,
                tx_type=WalletTransaction.TxType.DEPOSIT,
            )
        except WalletTransaction.DoesNotExist:
            logger.warning("Deposit callback for unknown ref: %s", deposit_id)
            return Response(status=status.HTTP_404_NOT_FOUND)

        # Idempotency: already processed
        if tx.status == WalletTransaction.Status.COMPLETED:
            return Response({"status": "already_processed"})

        if cb_status == "COMPLETED":
            credit_wallet(
                tx.wallet,
                tx.amount,
                tx_type=WalletTransaction.TxType.DEPOSIT,
                description="Rechargement Mobile Money",
                provider_reference=deposit_id,
            )
            # Update the original pending tx
            tx.status = WalletTransaction.Status.COMPLETED
            tx.balance_after = tx.wallet.balance
            tx.metadata = {**(tx.metadata or {}), "callback": request.data}
            tx.save(update_fields=["status", "balance_after", "metadata"])
            logger.info("Deposit %s completed → wallet %s", deposit_id, tx.wallet.user_id)
        else:
            tx.status = WalletTransaction.Status.FAILED
            tx.metadata = {**(tx.metadata or {}), "callback": request.data}
            tx.save(update_fields=["status", "metadata"])
            logger.info("Deposit %s failed: %s", deposit_id, cb_status)

        return Response({"status": "ok"})


class PawapayPayoutCallbackView(APIView):
    """Callback from PawaPay when a driver payout completes or fails."""

    permission_classes = [permissions.AllowAny]
    authentication_classes = []

    def post(self, request):
        sig = request.headers.get("X-Pawapay-Signature", "")
        if not pawapay.verify_callback_signature(request.body, sig):
            logger.warning("Invalid PawaPay payout callback signature")
            return Response(status=status.HTTP_401_UNAUTHORIZED)

        payout_id = request.data.get("payoutId", "")
        cb_status = request.data.get("status", "")

        if not payout_id:
            return Response(status=status.HTTP_400_BAD_REQUEST)

        try:
            payout = DriverPayout.objects.get(provider_transaction_id=payout_id)
        except DriverPayout.DoesNotExist:
            logger.warning("Payout callback for unknown ref: %s", payout_id)
            return Response(status=status.HTTP_404_NOT_FOUND)

        # Idempotency
        if payout.status == DriverPayout.Status.COMPLETED:
            return Response({"status": "already_processed"})

        if cb_status == "COMPLETED":
            payout.status = DriverPayout.Status.COMPLETED
            payout.completed_at = timezone.now()
            payout.provider_response = request.data
            payout.save(update_fields=["status", "completed_at", "provider_response"])
            logger.info("Payout %s completed for driver %s", payout_id, payout.driver_id)
        else:
            # Failed — refund the driver wallet
            payout.status = DriverPayout.Status.FAILED
            payout.provider_response = request.data
            payout.save(update_fields=["status", "provider_response"])

            driver_wallet = get_or_create_wallet(payout.driver)
            credit_wallet(
                driver_wallet,
                payout.amount,
                tx_type=WalletTransaction.TxType.REFUND,
                description="Retrait échoué – remboursement",
                provider_reference=payout_id,
            )
            logger.info("Payout %s failed – refunded driver %s", payout_id, payout.driver_id)

        return Response({"status": "ok"})


class PawapayRefundCallbackView(APIView):
    """Callback from PawaPay when a refund completes or fails."""

    permission_classes = [permissions.AllowAny]
    authentication_classes = []

    def post(self, request):
        sig = request.headers.get("X-Pawapay-Signature", "")
        if not pawapay.verify_callback_signature(request.body, sig):
            return Response(status=status.HTTP_401_UNAUTHORIZED)

        refund_id = request.data.get("refundId", "")
        cb_status = request.data.get("status", "")

        logger.info("PawaPay refund callback: %s → %s", refund_id, cb_status)

        # Find matching transaction and update
        try:
            tx = WalletTransaction.objects.get(
                provider_reference=refund_id,
                tx_type=WalletTransaction.TxType.REFUND,
            )
        except WalletTransaction.DoesNotExist:
            return Response(status=status.HTTP_404_NOT_FOUND)

        if cb_status == "COMPLETED":
            tx.status = WalletTransaction.Status.COMPLETED
        else:
            tx.status = WalletTransaction.Status.FAILED
        tx.metadata = {**(tx.metadata or {}), "callback": request.data}
        tx.save(update_fields=["status", "metadata"])

        return Response({"status": "ok"})


# ═══════════════════════════════════════════════════════════════════════
# LEGACY PAYMENT ENDPOINTS
# ═══════════════════════════════════════════════════════════════════════

class PaymentStatusView(generics.RetrieveAPIView):
    """Check payment status."""

    serializer_class = PaymentSerializer
    lookup_field = "id"
    lookup_url_kwarg = "payment_id"

    def get_queryset(self):
        return Payment.objects.filter(payer=self.request.user)


class PaymentHistoryView(generics.ListAPIView):
    """Get payment history."""

    serializer_class = PaymentSerializer

    def get_queryset(self):
        return Payment.objects.filter(payer=self.request.user)


# ═══════════════════════════════════════════════════════════════════════
# DRIVER ENDPOINTS
# ═══════════════════════════════════════════════════════════════════════

class DriverEarningsView(APIView):
    """Get driver earnings summary + wallet balance."""

    permission_classes = [permissions.IsAuthenticated, IsDriver]

    def get(self, request):
        profile = request.user.driver_profile
        wallet = get_or_create_wallet(request.user)

        today = timezone.now().date()
        from apps.rides.models import Ride
        today_rides = Ride.objects.filter(
            driver=request.user,
            status=Ride.Status.COMPLETED,
            completed_at__date=today,
        )
        today_earnings = sum(r.driver_earnings for r in today_rides)

        from django.db.models import Sum
        from datetime import timedelta
        week_start = today - timedelta(days=today.weekday())
        month_start = today.replace(day=1)

        week_earnings = Ride.objects.filter(
            driver=request.user,
            status=Ride.Status.COMPLETED,
            completed_at__date__gte=week_start,
        ).aggregate(total=Sum("driver_earnings"))["total"] or 0

        month_earnings = Ride.objects.filter(
            driver=request.user,
            status=Ride.Status.COMPLETED,
            completed_at__date__gte=month_start,
        ).aggregate(total=Sum("driver_earnings"))["total"] or 0

        return Response({
            "wallet_balance": str(wallet.balance),
            "wallet_currency": wallet.currency,
            "total_earnings": str(profile.total_earnings),
            "total_rides": profile.total_rides,
            "today": float(today_earnings),
            "today_rides": today_rides.count(),
            "this_week": float(week_earnings),
            "this_month": float(month_earnings),
            "avg_rating": float(profile.rating_average) if profile.rating_average else 0,
            "acceptance_rate": float(profile.acceptance_rate),
            "total_balance": float(wallet.balance),
            "total_commission": float(
                Ride.objects.filter(
                    driver=request.user,
                    status=Ride.Status.COMPLETED,
                ).aggregate(total=Sum("commission_amount"))["total"] or 0
            ),
        })


class DriverPayoutRequestView(APIView):
    """Driver requests withdrawal from wallet to Mobile Money."""

    permission_classes = [permissions.IsAuthenticated, IsDriver]

    def post(self, request):
        serializer = PayoutRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        wallet = get_or_create_wallet(request.user)
        amount = data["amount"]
        phone = data["phone_number"]

        if not wallet.can_afford(amount):
            return Response(
                {"detail": "Solde insuffisant."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        payout_id = str(uuid.uuid4())

        # Debit wallet first
        debit_wallet(
            wallet,
            amount,
            tx_type=WalletTransaction.TxType.PAYOUT,
            description=f"Retrait vers {phone}",
            provider_reference=payout_id,
        )

        # Create payout record
        payout = DriverPayout.objects.create(
            driver=request.user,
            amount=amount,
            phone_number=phone,
            status=DriverPayout.Status.PROCESSING,
            provider_transaction_id=payout_id,
        )

        # Call PawaPay payout
        result = pawapay.initiate_payout(
            phone_number=phone,
            amount=float(amount),
            payout_id=payout_id,
        )

        if not result["success"]:
            # Refund wallet
            payout.status = DriverPayout.Status.FAILED
            payout.provider_response = result["raw"]
            payout.save(update_fields=["status", "provider_response"])

            credit_wallet(
                wallet,
                amount,
                tx_type=WalletTransaction.TxType.REFUND,
                description="Retrait échoué – remboursement",
                provider_reference=payout_id,
            )
            return Response(
                {"detail": "Échec du retrait. Votre solde a été rétabli."},
                status=status.HTTP_502_BAD_GATEWAY,
            )

        return Response({
            "payout_id": payout_id,
            "amount": str(amount),
            "status": "processing",
            "message": "Retrait en cours de traitement.",
        })


class DriverPayoutHistoryView(generics.ListAPIView):
    """Get driver payout history."""

    serializer_class = DriverPayoutSerializer
    permission_classes = [permissions.IsAuthenticated, IsDriver]

    def get_queryset(self):
        return DriverPayout.objects.filter(driver=self.request.user)


# ═══════════════════════════════════════════════════════════════════════
# ADMIN / HEALTH CHECK
# ═══════════════════════════════════════════════════════════════════════

class PawapayActiveCorrespondentsView(APIView):
    """Check which PawaPay correspondents are active (admin only)."""

    permission_classes = [permissions.IsAdminUser]

    def get(self, request):
        result = pawapay.get_active_correspondents()
        expected = {"VODACOM_CD", "AIRTEL_CD", "ORANGE_CD"}
        active_ids = set()
        for c in result.get("correspondents", []):
            if isinstance(c, dict):
                active_ids.add(c.get("correspondent", ""))
            elif isinstance(c, str):
                active_ids.add(c)

        missing = expected - active_ids
        return Response({
            "pawapay_reachable": result["success"],
            "active_correspondents": result["correspondents"],
            "expected": list(expected),
            "missing": list(missing) if missing else [],
            "all_live": result["success"] and not missing,
        })
