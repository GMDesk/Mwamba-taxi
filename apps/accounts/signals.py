from django.db.models.signals import post_save
from django.dispatch import receiver

from .models import DriverProfile, User


@receiver(post_save, sender=User)
def create_driver_profile_placeholder(sender, instance, created, **kwargs):
    """No auto-creation; driver profile is created during driver registration."""
    pass
