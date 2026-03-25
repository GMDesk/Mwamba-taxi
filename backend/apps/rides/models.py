import uuid

from django.conf import settings
from django.contrib.postgres.fields import ArrayField
from django.db import models


class Ride(models.Model):
    """Core ride model – represents a trip from A to B."""

    class Status(models.TextChoices):
        REQUESTED = "requested", "Demandée"
        ACCEPTED = "accepted", "Acceptée"
        DRIVER_ARRIVING = "driver_arriving", "Chauffeur en route"
        IN_PROGRESS = "in_progress", "En cours"
        COMPLETED = "completed", "Terminée"
        CANCELLED_BY_PASSENGER = "cancelled_passenger", "Annulée par passager"
        CANCELLED_BY_DRIVER = "cancelled_driver", "Annulée par chauffeur"
        NO_DRIVER = "no_driver", "Aucun chauffeur disponible"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    passenger = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="rides_as_passenger",
        verbose_name="Passager",
    )
    driver = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="rides_as_driver",
        verbose_name="Chauffeur",
    )

    # Pickup
    pickup_address = models.CharField("Adresse de départ", max_length=300)
    pickup_latitude = models.DecimalField(
        "Latitude départ", max_digits=10, decimal_places=7
    )
    pickup_longitude = models.DecimalField(
        "Longitude départ", max_digits=10, decimal_places=7
    )

    # Destination
    destination_address = models.CharField("Adresse d'arrivée", max_length=300)
    destination_latitude = models.DecimalField(
        "Latitude arrivée", max_digits=10, decimal_places=7
    )
    destination_longitude = models.DecimalField(
        "Longitude arrivée", max_digits=10, decimal_places=7
    )

    # Distance & duration
    distance_km = models.DecimalField(
        "Distance (km)", max_digits=7, decimal_places=2, null=True, blank=True
    )
    estimated_duration_minutes = models.PositiveIntegerField(
        "Durée estimée (min)", null=True, blank=True
    )

    # Pricing
    estimated_price = models.DecimalField(
        "Prix estimé", max_digits=10, decimal_places=2
    )
    final_price = models.DecimalField(
        "Prix final", max_digits=10, decimal_places=2, null=True, blank=True
    )
    commission_amount = models.DecimalField(
        "Commission", max_digits=10, decimal_places=2, default=0.00
    )
    driver_earnings = models.DecimalField(
        "Revenu chauffeur", max_digits=10, decimal_places=2, default=0.00
    )

    # Status
    status = models.CharField(
        "Statut", max_length=25, choices=Status.choices, default=Status.REQUESTED
    )
    cancellation_reason = models.TextField("Raison d'annulation", blank=True, default="")

    # Promo
    promo_code = models.ForeignKey(
        "promotions.PromoCode",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="rides",
    )
    discount_amount = models.DecimalField(
        "Réduction", max_digits=10, decimal_places=2, default=0.00
    )

    # Auto-assignment
    assigned_driver = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="rides_assigned",
        verbose_name="Chauffeur assigné",
        help_text="Currently assigned driver (pending acceptance)",
    )
    assignment_expires_at = models.DateTimeField(
        "Expiration assignation", null=True, blank=True
    )
    declined_driver_ids = models.JSONField(
        "Chauffeurs ayant décliné", default=list, blank=True
    )

    # Timestamps
    requested_at = models.DateTimeField("Demandé le", auto_now_add=True)
    accepted_at = models.DateTimeField("Accepté le", null=True, blank=True)
    started_at = models.DateTimeField("Démarré le", null=True, blank=True)
    completed_at = models.DateTimeField("Terminé le", null=True, blank=True)
    cancelled_at = models.DateTimeField("Annulé le", null=True, blank=True)

    class Meta:
        verbose_name = "Course"
        verbose_name_plural = "Courses"
        ordering = ["-requested_at"]
        indexes = [
            models.Index(fields=["status"]),
            models.Index(fields=["passenger", "-requested_at"]),
            models.Index(fields=["driver", "-requested_at"]),
        ]

    def __str__(self):
        return f"Course {self.id!s:.8} – {self.get_status_display()}"

    def calculate_commission(self):
        """Calculate platform commission & driver earnings."""
        price = self.final_price or self.estimated_price
        rate = settings.COMMISSION_RATE / 100
        self.commission_amount = round(price * rate, 2)
        self.driver_earnings = price - self.commission_amount - self.discount_amount


class RideLocationLog(models.Model):
    """GPS breadcrumb trail for a ride – for route tracking."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    ride = models.ForeignKey(
        Ride, on_delete=models.CASCADE, related_name="location_logs"
    )
    latitude = models.DecimalField(max_digits=10, decimal_places=7)
    longitude = models.DecimalField(max_digits=10, decimal_places=7)
    recorded_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "Position GPS"
        verbose_name_plural = "Positions GPS"
        ordering = ["recorded_at"]


class SOSAlert(models.Model):
    """Emergency SOS alert from a ride."""

    class Status(models.TextChoices):
        ACTIVE = "active", "Active"
        RESOLVED = "resolved", "Résolue"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    ride = models.ForeignKey(Ride, on_delete=models.CASCADE, related_name="sos_alerts")
    triggered_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE
    )
    latitude = models.DecimalField(max_digits=10, decimal_places=7)
    longitude = models.DecimalField(max_digits=10, decimal_places=7)
    status = models.CharField(
        max_length=10, choices=Status.choices, default=Status.ACTIVE
    )
    message = models.TextField(blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True)
    resolved_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        verbose_name = "Alerte SOS"
        verbose_name_plural = "Alertes SOS"
        ordering = ["-created_at"]
