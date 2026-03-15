from django.contrib import admin

from .models import Ride, RideLocationLog, SOSAlert


@admin.register(Ride)
class RideAdmin(admin.ModelAdmin):
    list_display = [
        "id", "passenger", "driver", "status",
        "estimated_price", "final_price", "requested_at",
    ]
    list_filter = ["status", "requested_at"]
    search_fields = [
        "passenger__full_name", "driver__full_name",
        "pickup_address", "destination_address",
    ]
    readonly_fields = ["commission_amount", "driver_earnings"]
    date_hierarchy = "requested_at"


@admin.register(SOSAlert)
class SOSAlertAdmin(admin.ModelAdmin):
    list_display = ["ride", "triggered_by", "status", "created_at"]
    list_filter = ["status"]
    actions = ["resolve_alerts"]

    @admin.action(description="Résoudre les alertes sélectionnées")
    def resolve_alerts(self, request, queryset):
        from django.utils import timezone
        queryset.update(status=SOSAlert.Status.RESOLVED, resolved_at=timezone.now())


@admin.register(RideLocationLog)
class RideLocationLogAdmin(admin.ModelAdmin):
    list_display = ["ride", "latitude", "longitude", "recorded_at"]
