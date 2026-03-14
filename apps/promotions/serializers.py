from rest_framework import serializers

from .models import PromoCode, Referral


class PromoCodeSerializer(serializers.ModelSerializer):
    class Meta:
        model = PromoCode
        fields = [
            "id", "code", "description", "discount_type",
            "discount_value", "max_discount", "min_ride_amount",
            "max_uses", "used_count", "is_active",
            "valid_from", "valid_until",
        ]


class ValidatePromoSerializer(serializers.Serializer):
    code = serializers.CharField(max_length=20)
    ride_amount = serializers.DecimalField(
        max_digits=10, decimal_places=2, required=False
    )


class ReferralSerializer(serializers.ModelSerializer):
    referrer_name = serializers.CharField(source="referrer.full_name", read_only=True)

    class Meta:
        model = Referral
        fields = ["id", "referral_code", "referrer_name", "bonus_given", "created_at"]
