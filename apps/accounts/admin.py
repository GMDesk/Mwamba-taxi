from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin

from .models import DriverProfile, OTPCode, User


@admin.register(User)
class UserAdmin(BaseUserAdmin):
    list_display = [
        "phone_number", "full_name", "role", "is_active",
        "is_phone_verified", "created_at",
    ]
    list_filter = ["role", "is_active", "is_phone_verified", "created_at"]
    search_fields = ["phone_number", "full_name", "email"]
    ordering = ["-created_at"]
    fieldsets = (
        (None, {"fields": ("phone_number", "password")}),
        ("Informations personnelles", {"fields": ("full_name", "email", "avatar")}),
        ("Rôle & Statut", {"fields": ("role", "is_active", "is_phone_verified")}),
        ("Permissions", {"fields": ("is_staff", "is_superuser", "groups", "user_permissions")}),
        ("Notifications", {"fields": ("fcm_token",)}),
    )
    add_fieldsets = (
        (None, {
            "classes": ("wide",),
            "fields": ("phone_number", "full_name", "password1", "password2", "role"),
        }),
    )


@admin.register(DriverProfile)
class DriverProfileAdmin(admin.ModelAdmin):
    list_display = [
        "user", "license_plate", "vehicle_make", "vehicle_model",
        "status", "is_online", "rating_average", "total_rides",
    ]
    list_filter = ["status", "is_online"]
    search_fields = ["user__full_name", "user__phone_number", "license_plate"]
    readonly_fields = ["rating_average", "total_rides", "total_earnings"]
    actions = ["approve_drivers", "suspend_drivers"]

    @admin.action(description="Approuver les chauffeurs sélectionnés")
    def approve_drivers(self, request, queryset):
        queryset.update(status=DriverProfile.Status.APPROVED)

    @admin.action(description="Suspendre les chauffeurs sélectionnés")
    def suspend_drivers(self, request, queryset):
        queryset.update(status=DriverProfile.Status.SUSPENDED, is_online=False)


@admin.register(OTPCode)
class OTPCodeAdmin(admin.ModelAdmin):
    list_display = ["phone_number", "is_used", "attempts", "created_at", "expires_at"]
    list_filter = ["is_used"]
    readonly_fields = ["code_hash"]
