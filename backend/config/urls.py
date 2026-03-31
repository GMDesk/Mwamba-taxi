"""
Mwamba Taxi – Root URL Configuration
"""
from django.conf import settings
from django.conf.urls.static import static
from django.contrib import admin
from django.http import JsonResponse
from django.urls import include, path
from drf_spectacular.views import (
    SpectacularAPIView,
    SpectacularRedocView,
    SpectacularSwaggerView,
)


def health_check(request):
    """Health check endpoint for Docker / load balancer / monitoring."""
    from django.db import connection
    try:
        connection.ensure_connection()
        db_ok = True
    except Exception:
        db_ok = False

    healthy = db_ok
    data = {
        "status": "healthy" if healthy else "unhealthy",
        "database": "ok" if db_ok else "error",
        "version": "1.0.0",
    }
    return JsonResponse(data, status=200 if healthy else 503)


urlpatterns = [
    # Health check (pas d'auth — utilisé par Docker, Nginx, monitoring)
    path("api/health/", health_check, name="health-check"),
    # Admin
    path("admin/", admin.site.urls),
    # API v1
    path("api/v1/auth/", include("apps.accounts.urls")),
    path("api/v1/rides/", include("apps.rides.urls")),
    path("api/v1/payments/", include("apps.payments.urls")),
    path("api/v1/notifications/", include("apps.notifications.urls")),
    path("api/v1/promotions/", include("apps.promotions.urls")),
    path("api/v1/reviews/", include("apps.reviews.urls")),
    path("api/v1/dashboard/", include("apps.admin_dashboard.urls")),
    # API Documentation
    path("api/schema/", SpectacularAPIView.as_view(), name="schema"),
    path(
        "api/docs/",
        SpectacularSwaggerView.as_view(url_name="schema"),
        name="swagger-ui",
    ),
    #
    path(
        "api/redoc/",
        SpectacularRedocView.as_view(url_name="schema"),
        name="redoc",
    ),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)

# Admin site customization
admin.site.site_header = "Mwamba Taxi Administration"
admin.site.site_title = "Mwamba Taxi"
admin.site.index_title = "Tableau de bord"
