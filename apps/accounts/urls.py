from django.urls import path
from rest_framework_simplejwt.views import TokenRefreshView

from . import views

app_name = "accounts"

urlpatterns = [
    # Auth
    path("register/passenger/", views.RegisterPassengerView.as_view(), name="register-passenger"),
    path("register/driver/", views.RegisterDriverView.as_view(), name="register-driver"),
    path("login/", views.LoginView.as_view(), name="login"),
    path("logout/", views.LogoutView.as_view(), name="logout"),
    path("token/refresh/", TokenRefreshView.as_view(), name="token-refresh"),
    # OTP
    path("otp/request/", views.RequestOTPView.as_view(), name="otp-request"),
    path("otp/verify/", views.VerifyOTPView.as_view(), name="otp-verify"),
    # Profile
    path("profile/", views.ProfileView.as_view(), name="profile"),
    path("profile/password/", views.ChangePasswordView.as_view(), name="change-password"),
    # Driver
    path("driver/profile/", views.DriverProfileView.as_view(), name="driver-profile"),
    path("driver/location/", views.DriverLocationView.as_view(), name="driver-location"),
    path("driver/status/", views.DriverStatusView.as_view(), name="driver-status"),
    path("drivers/nearby/", views.NearbyDriversView.as_view(), name="nearby-drivers"),
]
