from decimal import Decimal

from rest_framework import serializers

from .models import DriverPayout, Payment, Wallet, WalletTransaction


# ─────────────────────── Wallet ──────────────────────────────────────
class WalletSerializer(serializers.ModelSerializer):
    available_balance = serializers.DecimalField(
        max_digits=12, decimal_places=2, read_only=True
    )

    class Meta:
        model = Wallet
        fields = [
            "id", "balance", "held_amount", "available_balance",
            "currency", "status", "created_at", "updated_at",
        ]
        read_only_fields = fields


class WalletTransactionSerializer(serializers.ModelSerializer):
    tx_type_display = serializers.CharField(
        source="get_tx_type_display", read_only=True
    )

    class Meta:
        model = WalletTransaction
        fields = [
            "id", "tx_type", "tx_type_display", "amount",
            "balance_after", "status", "description",
            "ride", "provider_reference", "created_at",
        ]
        read_only_fields = fields


class DepositSerializer(serializers.Serializer):
    """Initiate wallet top-up via Mobile Money."""
    amount = serializers.DecimalField(max_digits=10, decimal_places=2, min_value=Decimal("500"))
    phone_number = serializers.CharField(max_length=16)


class PayoutRequestSerializer(serializers.Serializer):
    """Driver requests withdrawal to Mobile Money."""
    amount = serializers.DecimalField(max_digits=10, decimal_places=2, min_value=Decimal("1000"))
    phone_number = serializers.CharField(max_length=16)


# ─────────────────────── Payment (ride-level) ────────────────────────
class PaymentSerializer(serializers.ModelSerializer):
    class Meta:
        model = Payment
        fields = [
            "id", "ride", "payer", "amount", "currency", "method",
            "status", "phone_number", "provider_transaction_id",
            "created_at", "completed_at",
        ]
        read_only_fields = [
            "id", "payer", "status", "provider_transaction_id",
            "created_at", "completed_at",
        ]


class InitiatePaymentSerializer(serializers.Serializer):
    ride_id = serializers.UUIDField()
    method = serializers.ChoiceField(choices=Payment.Method.choices)
    phone_number = serializers.CharField(max_length=16, required=False)


# ─────────────────────── Driver ──────────────────────────────────────
class DriverPayoutSerializer(serializers.ModelSerializer):
    class Meta:
        model = DriverPayout
        fields = [
            "id", "amount", "currency", "status", "phone_number",
            "provider_transaction_id", "created_at", "completed_at",
        ]
