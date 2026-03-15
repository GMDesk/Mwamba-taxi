from django.urls import path

from . import views

app_name = "promotions"

urlpatterns = [
    path("validate/", views.ValidatePromoCodeView.as_view(), name="validate"),
]
