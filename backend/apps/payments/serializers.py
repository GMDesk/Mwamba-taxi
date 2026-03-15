from rest_framework import serializers

from .models import DriverPayout, Payment


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


class DriverPayoutSerializer(serializers.ModelSerializer):
    class Meta:
        model = DriverPayout
        fields = [
            "id", "amount", "currency", "status", "rides_count",
            "period_start", "period_end", "created_at", "completed_at",
        ]
