import uuid

from django.conf import settings
from django.db import models


class Notification(models.Model):
    """Push / SMS notification record."""

    class Channel(models.TextChoices):
        PUSH = "push", "Push"
        SMS = "sms", "SMS"
        IN_APP = "in_app", "In-App"

    class Category(models.TextChoices):
        RIDE = "ride", "Course"
        PAYMENT = "payment", "Paiement"
        PROMO = "promo", "Promotion"
        SYSTEM = "system", "Système"
        SOS = "sos", "SOS"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    recipient = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="notifications",
    )
    title = models.CharField("Titre", max_length=150)
    body = models.TextField("Contenu")
    channel = models.CharField(
        max_length=10, choices=Channel.choices, default=Channel.PUSH
    )
    category = models.CharField(
        max_length=10, choices=Category.choices, default=Category.SYSTEM
    )
    data = models.JSONField("Données supplémentaires", null=True, blank=True)
    is_read = models.BooleanField("Lu", default=False)
    sent_at = models.DateTimeField("Envoyé le", auto_now_add=True)

    class Meta:
        verbose_name = "Notification"
        verbose_name_plural = "Notifications"
        ordering = ["-sent_at"]
        indexes = [
            models.Index(fields=["recipient", "-sent_at"]),
        ]

    def __str__(self):
        return f"{self.title} → {self.recipient}"
