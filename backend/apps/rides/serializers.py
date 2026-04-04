from rest_framework import serializers

from apps.accounts.serializers import UserSerializer

from .models import Ride, RideLocationLog, SOSAlert


class RideCreateSerializer(serializers.ModelSerializer):
    class Meta:
        model = Ride
        fields = [
            "pickup_address", "pickup_latitude", "pickup_longitude",
            "destination_address", "destination_latitude", "destination_longitude",
            "estimated_price", "distance_km", "estimated_duration_minutes",
        ]


class RideSerializer(serializers.ModelSerializer):
    passenger = UserSerializer(read_only=True)
    driver = UserSerializer(read_only=True)
    assigned_driver_info = serializers.SerializerMethodField()
    driver_vehicle = serializers.SerializerMethodField()
    driver_location = serializers.SerializerMethodField()

    class Meta:
        model = Ride
        fields = [
            "id", "passenger", "driver", "assigned_driver_info", "driver_vehicle",
            "driver_location",
            "pickup_address", "pickup_latitude", "pickup_longitude",
            "destination_address", "destination_latitude", "destination_longitude",
            "distance_km", "estimated_duration_minutes",
            "estimated_price", "final_price", "discount_amount",
            "commission_amount", "driver_earnings",
            "status", "cancellation_reason",
            "assignment_expires_at",
            "requested_at", "accepted_at", "started_at",
            "completed_at", "cancelled_at",
        ]

    def get_assigned_driver_info(self, obj):
        if obj.assigned_driver and hasattr(obj.assigned_driver, "driver_profile"):
            p = obj.assigned_driver.driver_profile
            return {
                "id": obj.assigned_driver.id,
                "name": obj.assigned_driver.full_name,
                "photo": obj.assigned_driver.avatar.url if obj.assigned_driver.avatar else None,
                "vehicle": f"{p.vehicle_make} {p.vehicle_model}",
                "vehicle_color": p.vehicle_color,
                "license_plate": p.license_plate,
                "rating": float(p.rating_average) if p.rating_average else None,
            }
        return None

    def get_driver_vehicle(self, obj):
        if obj.driver and hasattr(obj.driver, "driver_profile"):
            p = obj.driver.driver_profile
            return {
                "make": p.vehicle_make,
                "model": p.vehicle_model,
                "color": p.vehicle_color,
                "license_plate": p.license_plate,
            }
        return None

    def get_driver_location(self, obj):
        """Return the driver's latest GPS position from their profile."""
        user = obj.driver or obj.assigned_driver
        if user and hasattr(user, "driver_profile"):
            p = user.driver_profile
            if p.current_latitude is not None and p.current_longitude is not None:
                return {
                    "latitude": float(p.current_latitude),
                    "longitude": float(p.current_longitude),
                }
        return None


class RideLocationLogSerializer(serializers.ModelSerializer):
    class Meta:
        model = RideLocationLog
        fields = ["latitude", "longitude", "recorded_at"]


class SOSAlertSerializer(serializers.ModelSerializer):
    class Meta:
        model = SOSAlert
        fields = ["id", "ride", "latitude", "longitude", "message", "status", "created_at"]
        read_only_fields = ["id", "status", "created_at"]


class RideCancelSerializer(serializers.Serializer):
    reason = serializers.CharField(required=False, allow_blank=True, default="", max_length=500)


class EstimatePriceSerializer(serializers.Serializer):
    pickup_latitude = serializers.DecimalField(max_digits=10, decimal_places=7)
    pickup_longitude = serializers.DecimalField(max_digits=10, decimal_places=7)
    destination_latitude = serializers.DecimalField(max_digits=10, decimal_places=7)
    destination_longitude = serializers.DecimalField(max_digits=10, decimal_places=7)
    promo_code = serializers.CharField(required=False, allow_blank=True, default="")
