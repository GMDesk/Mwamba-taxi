from django.contrib.auth import get_user_model
from rest_framework import serializers

from .models import DriverProfile, OTPCode

User = get_user_model()


class UserSerializer(serializers.ModelSerializer):
    referral_code = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = [
            "id", "phone_number", "full_name", "email", "role",
            "avatar", "is_phone_verified", "created_at", "referral_code",
        ]
        read_only_fields = ["id", "is_phone_verified", "created_at", "referral_code"]

    def get_referral_code(self, obj):
        # Generate a stable referral code from the user UUID (first 8 chars uppercased)
        return str(obj.id).replace('-', '')[:8].upper()


class UserCreateSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ["phone_number", "full_name", "password"]
        extra_kwargs = {"password": {"write_only": True, "min_length": 6}}

    def create(self, validated_data):
        return User.objects.create_user(**validated_data)


class DriverProfileSerializer(serializers.ModelSerializer):
    user = UserSerializer(read_only=True)

    class Meta:
        model = DriverProfile
        fields = [
            "id", "user", "vehicle_make", "vehicle_model", "vehicle_year",
            "vehicle_color", "license_plate", "drivers_license_photo",
            "vehicle_registration_photo", "vehicle_photo",
            "status", "is_online", "is_on_ride",
            "current_latitude", "current_longitude",
            "rating_average", "total_rides", "total_earnings",
            "created_at",
        ]
        read_only_fields = [
            "id", "status", "rating_average", "total_rides",
            "total_earnings", "created_at",
        ]


class DriverRegistrationSerializer(serializers.Serializer):
    """Handles driver registration: user + profile in one request."""

    # User fields
    phone_number = serializers.CharField(max_length=16)
    full_name = serializers.CharField(max_length=150)
    password = serializers.CharField(write_only=True, min_length=6)

    # Vehicle fields
    vehicle_make = serializers.CharField(max_length=50)
    vehicle_model = serializers.CharField(max_length=50)
    vehicle_year = serializers.IntegerField(required=False)
    vehicle_color = serializers.CharField(max_length=30, required=False, allow_blank=True)
    license_plate = serializers.CharField(max_length=20)

    # Documents (optional at registration, can be uploaded later)
    drivers_license_photo = serializers.ImageField(required=False, allow_null=True)
    vehicle_registration_photo = serializers.ImageField(required=False, allow_null=True)
    vehicle_photo = serializers.ImageField(required=False, allow_null=True)

    def validate_phone_number(self, value):
        if User.objects.filter(phone_number=value).exists():
            raise serializers.ValidationError("Ce numéro est déjà utilisé.")
        return value

    def validate_license_plate(self, value):
        if DriverProfile.objects.filter(license_plate=value).exists():
            raise serializers.ValidationError("Cette plaque est déjà enregistrée.")
        return value

    def create(self, validated_data):
        user_data = {
            "phone_number": validated_data["phone_number"],
            "full_name": validated_data["full_name"],
            "password": validated_data["password"],
            "role": User.Role.DRIVER,
        }
        user = User.objects.create_user(**user_data)

        profile_data = {
            k: validated_data[k]
            for k in [
                "vehicle_make", "vehicle_model", "vehicle_year",
                "vehicle_color", "license_plate",
                "drivers_license_photo", "vehicle_registration_photo",
                "vehicle_photo",
            ]
            if k in validated_data
        }
        DriverProfile.objects.create(user=user, **profile_data)
        return user


class RequestOTPSerializer(serializers.Serializer):
    phone_number = serializers.CharField(max_length=16)


class VerifyOTPSerializer(serializers.Serializer):
    phone_number = serializers.CharField(max_length=16)
    code = serializers.CharField(max_length=6, min_length=6)


class LoginSerializer(serializers.Serializer):
    phone_number = serializers.CharField(max_length=16)
    password = serializers.CharField(required=False, allow_blank=True)
    otp = serializers.CharField(required=False, max_length=6, min_length=6)

    def validate(self, attrs):
        if not attrs.get("password") and not attrs.get("otp"):
            raise serializers.ValidationError(
                "Vous devez fournir un mot de passe ou un code OTP."
            )
        return attrs


class DriverLocationUpdateSerializer(serializers.Serializer):
    latitude = serializers.DecimalField(max_digits=10, decimal_places=7)
    longitude = serializers.DecimalField(max_digits=10, decimal_places=7)


class DriverStatusSerializer(serializers.Serializer):
    is_online = serializers.BooleanField()


class ChangePasswordSerializer(serializers.Serializer):
    old_password = serializers.CharField()
    new_password = serializers.CharField(min_length=6)
