from django.contrib.auth import get_user_model
from rest_framework import serializers

from apps.accounts.models import DriverProfile
from apps.accounts.serializers import UserSerializer
from apps.notifications.models import Notification
from apps.payments.models import Payment
from apps.promotions.models import PromoCode
from apps.reviews.models import Review
from apps.rides.models import Ride, SOSAlert

User = get_user_model()


class AdminRegisterSerializer(serializers.Serializer):
    """Serializer for creating a new admin account."""

    phone_number = serializers.CharField(max_length=16)
    full_name = serializers.CharField(max_length=150)
    email = serializers.EmailField(required=False, allow_blank=True)
    password = serializers.CharField(write_only=True, min_length=6)
    password_confirm = serializers.CharField(write_only=True, min_length=6)

    def validate_phone_number(self, value):
        if User.objects.filter(phone_number=value).exists():
            raise serializers.ValidationError("Ce numéro est déjà utilisé.")
        return value

    def validate(self, attrs):
        if attrs["password"] != attrs["password_confirm"]:
            raise serializers.ValidationError(
                {"password_confirm": "Les mots de passe ne correspondent pas."}
            )
        return attrs

    def create(self, validated_data):
        validated_data.pop("password_confirm")
        user = User.objects.create_user(
            phone_number=validated_data["phone_number"],
            full_name=validated_data["full_name"],
            email=validated_data.get("email", ""),
            password=validated_data["password"],
            role=User.Role.ADMIN,
            is_staff=True,
            is_phone_verified=True,
        )
        return user


class AdminUserSerializer(UserSerializer):
    """UserSerializer with admin-required fields."""

    class Meta(UserSerializer.Meta):
        fields = UserSerializer.Meta.fields + ["is_active"]


class AdminDriverProfileSerializer(serializers.ModelSerializer):
    user = AdminUserSerializer(read_only=True)

    class Meta:
        model = DriverProfile
        fields = [
            "id", "user", "vehicle_make", "vehicle_model", "vehicle_year",
            "vehicle_color", "license_plate", "drivers_license_photo",
            "vehicle_registration_photo", "vehicle_photo", "status",
            "rejection_reason", "is_online", "is_on_ride",
            "current_latitude", "current_longitude", "rating_average",
            "total_rides", "total_earnings", "created_at",
        ]


class AdminRideSerializer(serializers.ModelSerializer):
    passenger = AdminUserSerializer(read_only=True)
    driver = AdminUserSerializer(read_only=True)

    class Meta:
        model = Ride
        fields = [
            "id", "passenger", "driver", "pickup_address",
            "pickup_latitude", "pickup_longitude", "destination_address",
            "destination_latitude", "destination_longitude", "distance_km",
            "estimated_duration_minutes", "estimated_price", "final_price",
            "discount_amount", "commission_amount", "driver_earnings",
            "status", "cancellation_reason", "requested_at", "accepted_at",
            "started_at", "completed_at", "cancelled_at",
        ]


class AdminSOSAlertSerializer(serializers.ModelSerializer):
    triggered_by = AdminUserSerializer(read_only=True)

    class Meta:
        model = SOSAlert
        fields = [
            "id", "ride", "triggered_by", "latitude", "longitude",
            "status", "message", "created_at", "resolved_at",
        ]


class AdminPaymentSerializer(serializers.ModelSerializer):
    payer = AdminUserSerializer(read_only=True)

    class Meta:
        model = Payment
        fields = [
            "id", "ride", "payer", "amount", "currency", "method",
            "status", "phone_number", "provider_transaction_id",
            "created_at", "completed_at",
        ]


class AdminPromoCodeSerializer(serializers.ModelSerializer):
    class Meta:
        model = PromoCode
        fields = [
            "id", "code", "description", "discount_type",
            "discount_value", "max_discount", "min_ride_amount",
            "max_uses", "used_count", "max_uses_per_user",
            "is_active", "valid_from", "valid_until", "created_at",
        ]


class AdminReviewSerializer(serializers.ModelSerializer):
    reviewer = AdminUserSerializer(read_only=True)
    reviewed_user = AdminUserSerializer(read_only=True)

    class Meta:
        model = Review
        fields = [
            "id", "ride", "reviewer", "reviewed_user",
            "rating", "comment", "created_at",
        ]


class AdminNotificationSerializer(serializers.ModelSerializer):
    recipient = AdminUserSerializer(read_only=True)

    class Meta:
        model = Notification
        fields = [
            "id", "recipient", "title", "body", "channel",
            "category", "data", "is_read", "sent_at",
        ]
