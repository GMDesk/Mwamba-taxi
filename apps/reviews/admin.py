from django.contrib import admin

from .models import Review


@admin.register(Review)
class ReviewAdmin(admin.ModelAdmin):
    list_display = ["reviewer", "reviewed_user", "rating", "created_at"]
    list_filter = ["rating"]
    search_fields = ["reviewer__full_name", "reviewed_user__full_name"]
