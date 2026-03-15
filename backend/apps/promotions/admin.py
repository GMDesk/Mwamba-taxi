from django.contrib import admin

from .models import PromoCode, PromoUsage, Referral


@admin.register(PromoCode)
class PromoCodeAdmin(admin.ModelAdmin):
    list_display = [
        "code", "discount_type", "discount_value", "max_uses",
        "used_count", "is_active", "valid_from", "valid_until",
    ]
    list_filter = ["discount_type", "is_active"]
    search_fields = ["code", "description"]


@admin.register(PromoUsage)
class PromoUsageAdmin(admin.ModelAdmin):
    list_display = ["promo_code", "user", "discount_applied", "used_at"]


@admin.register(Referral)
class ReferralAdmin(admin.ModelAdmin):
    list_display = ["referrer", "referred", "referral_code", "bonus_given", "created_at"]
