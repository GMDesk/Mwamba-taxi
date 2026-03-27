from django.urls import path

from . import views

app_name = "rides"

urlpatterns = [
    # Price estimation
    path("estimate/", views.EstimatePriceView.as_view(), name="estimate-price"),
    # Ride lifecycle
    path("request/", views.RequestRideView.as_view(), name="request-ride"),
    path("<uuid:ride_id>/accept/", views.AcceptRideView.as_view(), name="accept-ride"),
    path("<uuid:ride_id>/decline/", views.DeclineRideView.as_view(), name="decline-ride"),
    path("<uuid:ride_id>/timeout/", views.TimeoutRideAssignmentView.as_view(), name="timeout-ride"),
    path("<uuid:ride_id>/arriving/", views.DriverArrivingView.as_view(), name="driver-arriving"),
    path("<uuid:ride_id>/arrived/", views.DriverArrivedView.as_view(), name="driver-arrived"),
    path("<uuid:ride_id>/start/", views.StartRideView.as_view(), name="start-ride"),
    path("<uuid:ride_id>/complete/", views.CompleteRideView.as_view(), name="complete-ride"),
    path("<uuid:ride_id>/cancel/", views.CancelRideView.as_view(), name="cancel-ride"),
    path("<uuid:ride_id>/", views.RideDetailView.as_view(), name="ride-detail"),
    # GPS tracking
    path("<uuid:ride_id>/location/", views.RideLocationLogView.as_view(), name="ride-location"),
    # SOS
    path("<uuid:ride_id>/sos/", views.SOSAlertView.as_view(), name="ride-sos"),
    # History
    path("history/passenger/", views.PassengerRideHistoryView.as_view(), name="passenger-history"),
    path("history/driver/", views.DriverRideHistoryView.as_view(), name="driver-history"),
    # Active ride check
    path("active/", views.ActiveRideView.as_view(), name="active-ride"),
    # Driver pending rides
    path("pending/", views.DriverPendingRidesView.as_view(), name="driver-pending"),
]
