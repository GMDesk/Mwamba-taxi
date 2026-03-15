from django.urls import path

from . import views

app_name = "reviews"

urlpatterns = [
    path("create/", views.CreateReviewView.as_view(), name="create"),
    path("driver/<uuid:driver_id>/", views.DriverReviewsView.as_view(), name="driver-reviews"),
]
