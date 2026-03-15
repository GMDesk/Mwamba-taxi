from django.contrib import admin

from .models import DriverPayout, Payment


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
    list_display = ["driver", "amount", "currency", "status", "rides_count", "created_at"]
    list_filter = ["status"]
