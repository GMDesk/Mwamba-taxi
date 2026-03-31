from django.urls import path

from . import views

app_name = "payments"

urlpatterns = [
    # Wallet
    path("wallet/", views.WalletDetailView.as_view(), name="wallet-detail"),
    path("wallet/transactions/", views.WalletTransactionListView.as_view(), name="wallet-transactions"),
    path("wallet/deposit/", views.DepositView.as_view(), name="wallet-deposit"),

    # PawaPay Callbacks (webhooks — no auth required)
    path("pawapay/deposit/callback/", views.PawapayDepositCallbackView.as_view(), name="pawapay-deposit-callback"),
    path("pawapay/payout/callback/", views.PawapayPayoutCallbackView.as_view(), name="pawapay-payout-callback"),
    path("pawapay/refund/callback/", views.PawapayRefundCallbackView.as_view(), name="pawapay-refund-callback"),

    # Legacy payment endpoints
    path("<uuid:payment_id>/status/", views.PaymentStatusView.as_view(), name="status"),
    path("history/", views.PaymentHistoryView.as_view(), name="history"),

    # Driver
    path("earnings/", views.DriverEarningsView.as_view(), name="driver-earnings"),
    path("payout/request/", views.DriverPayoutRequestView.as_view(), name="driver-payout-request"),
    path("payouts/", views.DriverPayoutHistoryView.as_view(), name="driver-payouts"),

    # Admin — PawaPay health check
    path("pawapay/active-correspondents/", views.PawapayActiveCorrespondentsView.as_view(), name="pawapay-active-correspondents"),
]
