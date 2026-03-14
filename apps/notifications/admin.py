from django.contrib import admin

from .models import Notification


@admin.register(Notification)
class NotificationAdmin(admin.ModelAdmin):
    list_display = ["recipient", "title", "channel", "category", "is_read", "sent_at"]
    list_filter = ["channel", "category", "is_read"]
    search_fields = ["recipient__full_name", "title"]
