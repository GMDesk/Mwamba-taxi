import logging

from django.conf import settings
from django.contrib.auth import get_user_model
from django.utils import timezone
from rest_framework import generics, permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.tokens import RefreshToken

from .models import DriverProfile, OTPCode
from .permissions import IsApprovedDriver, IsDriver
from .serializers import (
    ChangePasswordSerializer,
    DriverLocationUpdateSerializer,
    DriverProfileSerializer,
    DriverRegistrationSerializer,
    DriverStatusSerializer,
    LoginSerializer,
    RequestOTPSerializer,
    UserCreateSerializer,
    UserSerializer,
    VerifyOTPSerializer,
)

User = get_user_model()
logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------
class RegisterPassengerView(generics.CreateAPIView):
    """Register a new passenger."""

    serializer_class = UserCreateSerializer
    permission_classes = [permissions.AllowAny]

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.save()
        refresh = RefreshToken.for_user(user)
        return Response(
            {
                "user": UserSerializer(user).data,
                "tokens": {
                    "refresh": str(refresh),
                    "access": str(refresh.access_token),
                },
            },
            status=status.HTTP_201_CREATED,
        )


class RegisterDriverView(APIView):
    """Register a new driver with vehicle & documents."""

    permission_classes = [permissions.AllowAny]

    def post(self, request):
        serializer = DriverRegistrationSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.save()
        refresh = RefreshToken.for_user(user)
        return Response(
            {
                "user": UserSerializer(user).data,
                "driver_profile": DriverProfileSerializer(user.driver_profile).data,
                "tokens": {
                    "refresh": str(refresh),
                    "access": str(refresh.access_token),
                },
                "message": "Inscription réussie. Votre compte est en attente de validation.",
            },
            status=status.HTTP_201_CREATED,
        )


class LoginView(APIView):
    """Login via password or OTP."""

    permission_classes = [permissions.AllowAny]

    def post(self, request):
        serializer = LoginSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        try:
            user = User.objects.get(phone_number=data["phone_number"])
        except User.DoesNotExist:
            return Response(
                {"detail": "Identifiants invalides."},
                status=status.HTTP_401_UNAUTHORIZED,
            )

        if not user.is_active:
            return Response(
                {"detail": "Votre compte est désactivé."},
                status=status.HTTP_403_FORBIDDEN,
            )

        # Password auth
        if data.get("password"):
            if not user.check_password(data["password"]):
                return Response(
                    {"detail": "Identifiants invalides."},
                    status=status.HTTP_401_UNAUTHORIZED,
                )
        # OTP auth
        elif data.get("otp"):
            otp_record = (
                OTPCode.objects.filter(
                    phone_number=data["phone_number"], is_used=False
                )
                .order_by("-created_at")
                .first()
            )
            if not otp_record or not otp_record.verify(data["otp"]):
                return Response(
                    {"detail": "Code OTP invalide ou expiré."},
                    status=status.HTTP_401_UNAUTHORIZED,
                )

        refresh = RefreshToken.for_user(user)
        response_data = {
            "user": UserSerializer(user).data,
            "tokens": {
                "refresh": str(refresh),
                "access": str(refresh.access_token),
            },
        }
        if user.is_driver and hasattr(user, "driver_profile"):
            response_data["driver_profile"] = DriverProfileSerializer(
                user.driver_profile
            ).data
        return Response(response_data)


class RequestOTPView(APIView):
    """Send OTP to phone number."""

    permission_classes = [permissions.AllowAny]

    def post(self, request):
        serializer = RequestOTPSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        phone = serializer.validated_data["phone_number"]

        # Rate limit: max 3 OTPs per phone per 10 minutes
        recent = OTPCode.objects.filter(
            phone_number=phone,
            created_at__gte=timezone.now() - timezone.timedelta(minutes=10),
        ).count()
        if recent >= 3:
            return Response(
                {"detail": "Trop de demandes. Réessayez dans quelques minutes."},
                status=status.HTTP_429_TOO_MANY_REQUESTS,
            )

        code = OTPCode.generate_code()
        OTPCode.objects.create(
            phone_number=phone,
            code_hash=OTPCode.hash_code(code),
        )

        # Send SMS via Twilio (or log in dev)
        if settings.TWILIO_ACCOUNT_SID:
            from apps.notifications.services import send_sms

            send_sms(phone, f"Votre code Mwamba Taxi : {code}")
        else:
            logger.info("OTP for %s: %s", phone, code)

        return Response({"message": "Code OTP envoyé."})


class VerifyOTPView(APIView):
    """Verify OTP & mark phone as verified."""

    permission_classes = [permissions.AllowAny]

    def post(self, request):
        serializer = VerifyOTPSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        otp_record = (
            OTPCode.objects.filter(
                phone_number=data["phone_number"], is_used=False
            )
            .order_by("-created_at")
            .first()
        )

        if not otp_record or not otp_record.verify(data["code"]):
            return Response(
                {"detail": "Code OTP invalide ou expiré."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Mark phone verified
        User.objects.filter(phone_number=data["phone_number"]).update(
            is_phone_verified=True
        )
        return Response({"message": "Numéro vérifié avec succès."})


class LogoutView(APIView):
    """Blacklist refresh token."""

    def post(self, request):
        try:
            refresh_token = request.data.get("refresh")
            token = RefreshToken(refresh_token)
            token.blacklist()
            return Response({"message": "Déconnexion réussie."})
        except Exception:
            return Response(
                {"detail": "Token invalide."},
                status=status.HTTP_400_BAD_REQUEST,
            )


# ---------------------------------------------------------------------------
# Profile
# ---------------------------------------------------------------------------
class ProfileView(generics.RetrieveUpdateAPIView):
    """Get / update current user profile."""

    serializer_class = UserSerializer

    def get_object(self):
        return self.request.user


class ChangePasswordView(APIView):
    """Change user password."""

    def post(self, request):
        serializer = ChangePasswordSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = request.user
        if not user.check_password(serializer.validated_data["old_password"]):
            return Response(
                {"detail": "Ancien mot de passe incorrect."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        user.set_password(serializer.validated_data["new_password"])
        user.save()
        return Response({"message": "Mot de passe modifié."})


class DriverProfileView(generics.RetrieveUpdateAPIView):
    """Get / update driver profile."""

    serializer_class = DriverProfileSerializer
    permission_classes = [permissions.IsAuthenticated, IsDriver]

    def get_object(self):
        return self.request.user.driver_profile


class DriverLocationView(APIView):
    """Update driver GPS location."""

    permission_classes = [permissions.IsAuthenticated, IsApprovedDriver]

    def post(self, request):
        serializer = DriverLocationUpdateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        profile = request.user.driver_profile
        profile.current_latitude = serializer.validated_data["latitude"]
        profile.current_longitude = serializer.validated_data["longitude"]
        profile.last_location_update = timezone.now()
        profile.save(
            update_fields=["current_latitude", "current_longitude", "last_location_update"]
        )
        return Response({"message": "Position mise à jour."})


class DriverStatusView(APIView):
    """Toggle driver online/offline status."""

    permission_classes = [permissions.IsAuthenticated, IsApprovedDriver]

    def post(self, request):
        serializer = DriverStatusSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        profile = request.user.driver_profile
        profile.is_online = serializer.validated_data["is_online"]
        profile.save(update_fields=["is_online"])
        status_text = "en ligne" if profile.is_online else "hors ligne"
        return Response({"message": f"Vous êtes maintenant {status_text}."})


class NearbyDriversView(APIView):
    """Get nearby available drivers (for passengers)."""

    def get(self, request):
        lat = request.query_params.get("latitude")
        lng = request.query_params.get("longitude")
        radius_km = float(request.query_params.get("radius", 5))

        if not lat or not lng:
            return Response(
                {"detail": "latitude et longitude requis."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        lat, lng = float(lat), float(lng)
        # Simple bounding box filter (approximate)
        delta = radius_km / 111.0  # ~1 degree ≈ 111 km
        drivers = DriverProfile.objects.filter(
            status=DriverProfile.Status.APPROVED,
            is_online=True,
            is_on_ride=False,
            current_latitude__range=(lat - delta, lat + delta),
            current_longitude__range=(lng - delta, lng + delta),
        ).select_related("user")[:20]

        data = [
            {
                "id": str(d.id),
                "driver_name": d.user.full_name,
                "latitude": str(d.current_latitude),
                "longitude": str(d.current_longitude),
                "rating": str(d.rating_average),
                "vehicle_make": d.vehicle_make,
                "vehicle_model": d.vehicle_model,
                "vehicle_color": d.vehicle_color,
                "license_plate": d.license_plate,
            }
            for d in drivers
        ]
        return Response(data)
