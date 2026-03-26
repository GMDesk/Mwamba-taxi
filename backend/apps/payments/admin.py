from django.contrib import admin

from .models import DriverPayout, Payment, Wallet, WalletTransaction


@admin.register(Wallet)
class WalletAdmin(admin.ModelAdmin):
    list_display = ["user", "balance", "held_amount", "currency", "status", "updated_at"]
    list_filter = ["status", "currency"]
    search_fields = ["user__full_name"]


@admin.register(WalletTransaction)
class WalletTransactionAdmin(admin.ModelAdmin):
    list_display = ["wallet", "tx_type", "amount", "balance_after", "status", "created_at"]
    list_filter = ["tx_type", "status"]
    date_hierarchy = "created_at"


@admin.register(Payment)
class PaymentAdmin(admin.ModelAdmin):
    list_display = [
        "id", "ride", "payer", "amount", "currency",
        "method", "status", "created_at",
    ]
    list_filter = ["method", "status", "currency"]
    search_fields = ["payer__full_name", "provider_transaction_id"]
    date_hierarchy = "created_at"


@admin.register(DriverPayout)
class DriverPayoutAdmin(admin.ModelAdmin):
    list_display = ["driver", "amount", "currency", "status", "phone_number", "created_at"]
    list_filter = ["status"]
