from django.urls import path

from . import views

app_name = "admin_dashboard"

urlpatterns = [
    # Admin registration
    path("register/", views.AdminRegisterView.as_view(), name="admin-register"),
    # Stats
    path("stats/", views.DashboardStatsView.as_view(), name="stats"),
    path("charts/", views.DashboardChartDataView.as_view(), name="charts"),
    # Users
    path("users/", views.AdminUserListView.as_view(), name="user-list"),
    path("users/<uuid:id>/", views.AdminUserDetailView.as_view(), name="user-detail"),
    # Drivers
    path("drivers/", views.AdminDriverListView.as_view(), name="driver-list"),
    path("drivers/<uuid:driver_id>/approval/", views.AdminDriverApprovalView.as_view(), name="driver-approval"),
    # Rides
    path("rides/", views.AdminRideListView.as_view(), name="ride-list"),
    path("rides/<uuid:id>/", views.AdminRideDetailView.as_view(), name="ride-detail"),
    # SOS
    path("sos/", views.AdminSOSAlertListView.as_view(), name="sos-list"),
    path("sos/<uuid:alert_id>/resolve/", views.AdminSOSResolveView.as_view(), name="sos-resolve"),
    # Payments
    path("payments/", views.AdminPaymentListView.as_view(), name="payment-list"),
    # Promotions
    path("promos/", views.AdminPromoListCreateView.as_view(), name="promo-list"),
    path("promos/<uuid:id>/", views.AdminPromoDetailView.as_view(), name="promo-detail"),
    # Reviews
    path("reviews/", views.AdminReviewListView.as_view(), name="review-list"),
    # Notifications
    path("notifications/", views.AdminNotificationListView.as_view(), name="notification-list"),
]
