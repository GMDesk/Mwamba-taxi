"""
Celery tasks for ride management.

- check_assignment_timeouts: Runs every 5 seconds, auto-reassigns rides
  when the assigned driver hasn't responded within the timeout window.
"""

import logging

from celery import shared_task
from django.utils import timezone

logger = logging.getLogger(__name__)


@shared_task(name="rides.check_assignment_timeouts")
def check_assignment_timeouts():
    """Find rides whose assignment has expired and reassign them.

    This task runs periodically (every 5s via celery-beat) so that even if
    the client-side timeout fires late (or doesn't fire at all due to
    connectivity issues), the server still guarantees reassignment.
    """
    from .models import Ride

    expired_rides = Ride.objects.filter(
        status=Ride.Status.REQUESTED,
        assigned_driver__isnull=False,
        assignment_expires_at__lt=timezone.now(),
    ).select_related("assigned_driver")

    for ride in expired_rides:
        driver = ride.assigned_driver
        logger.info(
            "Assignment timeout: ride=%s driver=%s",
            ride.id, driver.id if driver else None,
        )

        # Move driver to declined list
        declined = ride.declined_driver_ids or []
        if driver and driver.id not in declined:
            declined.append(driver.id)
        ride.declined_driver_ids = declined
        ride.assigned_driver = None
        ride.assignment_expires_at = None
        ride.save(update_fields=[
            "declined_driver_ids", "assigned_driver", "assignment_expires_at",
        ])

        # Update driver stats
        if driver and hasattr(driver, "driver_profile"):
            from .scoring import update_driver_stats_on_decline
            update_driver_stats_on_decline(driver.driver_profile)

        # Notify the timed-out driver
        try:
            from asgiref.sync import async_to_sync
            from channels.layers import get_channel_layer
            channel_layer = get_channel_layer()
            async_to_sync(channel_layer.group_send)(
                f"driver_{driver.id}",
                {
                    "type": "ride_reassigned",
                    "ride_id": str(ride.id),
                },
            )
        except Exception:
            logger.exception("Failed to notify driver of timeout")

        # Try to find the next best driver
        from .views import _auto_assign_nearest_driver
        _auto_assign_nearest_driver(ride)


@shared_task(name="rides.cleanup_stale_rides")
def cleanup_stale_rides():
    """Mark rides stuck in REQUESTED with no driver for > 5 minutes as no_driver."""
    from datetime import timedelta
    from .models import Ride

    cutoff = timezone.now() - timedelta(minutes=5)
    stale = Ride.objects.filter(
        status=Ride.Status.REQUESTED,
        assigned_driver__isnull=True,
        requested_at__lt=cutoff,
    )
    count = stale.update(status=Ride.Status.NO_DRIVER)
    if count:
        logger.info("Cleaned up %d stale rides", count)
