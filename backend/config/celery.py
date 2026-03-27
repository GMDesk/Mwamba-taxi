"""
Celery application for Mwamba Taxi.
"""
import os
from celery import Celery

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")
app = Celery("mwamba_taxi")
app.config_from_object("django.conf:settings", namespace="CELERY")
app.autodiscover_tasks()

# Periodic tasks for ride management
app.conf.beat_schedule = {
    "check-assignment-timeouts": {
        "task": "rides.check_assignment_timeouts",
        "schedule": 5.0,  # every 5 seconds
    },
    "cleanup-stale-rides": {
        "task": "rides.cleanup_stale_rides",
        "schedule": 60.0,  # every minute
    },
}
