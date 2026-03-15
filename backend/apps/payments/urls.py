from django.urls import path

from . import views

app_name = "payments"

urlpatterns = [
    path("initiate/", views.InitiatePaymentView.as_view(), name="initiate"),
    path("<uuid:payment_id>/status/", views.PaymentStatusView.as_view(), name="status"),
    path("webhook/maxicash/", views.PaymentWebhookView.as_view(), name="maxicash-webhook"),
    path("history/", views.PaymentHistoryView.as_view(), name="history"),
    path("earnings/", views.DriverEarningsView.as_view(), name="driver-earnings"),
    path("payouts/", views.DriverPayoutHistoryView.as_view(), name="driver-payouts"),
]
