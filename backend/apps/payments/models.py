import uuid

from django.conf import settings
from django.db import models


class Payment(models.Model):
    """Payment record for a ride."""

    class Method(models.TextChoices):
        MOBILE_MONEY = "mobile_money", "Mobile Money"
        CASH = "cash", "Espèces"
        WALLET = "wallet", "Portefeuille"

    class Status(models.TextChoices):
        PENDING = "pending", "En attente"
        PROCESSING = "processing", "En cours"
        COMPLETED = "completed", "Complété"
        FAILED = "failed", "Échoué"
        REFUNDED = "refunded", "Remboursé"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    ride = models.OneToOneField(
        "rides.Ride", on_delete=models.CASCADE, related_name="payment"
    )
    payer = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="payments",
    )
    amount = models.DecimalField("Montant", max_digits=10, decimal_places=2)
    currency = models.CharField("Devise", max_length=5, default="CDF")
    method = models.CharField(
        "Moyen de paiement",
        max_length=15,
        choices=Method.choices,
        default=Method.MOBILE_MONEY,
    )
    status = models.CharField(
        "Statut", max_length=12, choices=Status.choices, default=Status.PENDING
    )

    # Maxicash / provider reference
    provider_transaction_id = models.CharField(
        "ID transaction fournisseur", max_length=100, blank=True, default=""
    )
    provider_response = models.JSONField(
        "Réponse fournisseur", null=True, blank=True
    )

    phone_number = models.CharField(
        "Numéro Mobile Money", max_length=16, blank=True, default=""
    )

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    completed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        verbose_name = "Paiement"
        verbose_name_plural = "Paiements"
        ordering = ["-created_at"]

    def __str__(self):
        return f"Paiement {self.amount} {self.currency} – {self.get_status_display()}"


class DriverPayout(models.Model):
    """Payout record – money transferred to driver."""

    class Status(models.TextChoices):
        PENDING = "pending", "En attente"
        COMPLETED = "completed", "Complété"
        FAILED = "failed", "Échoué"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    driver = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="payouts",
    )
    amount = models.DecimalField("Montant", max_digits=10, decimal_places=2)
    currency = models.CharField("Devise", max_length=5, default="CDF")
    status = models.CharField(
        max_length=10, choices=Status.choices, default=Status.PENDING
    )
    rides_count = models.PositiveIntegerField("Nombre de courses", default=0)
    period_start = models.DateField("Début période")
    period_end = models.DateField("Fin période")

    provider_transaction_id = models.CharField(max_length=100, blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True)
    completed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        verbose_name = "Versement chauffeur"
        verbose_name_plural = "Versements chauffeurs"
        ordering = ["-created_at"]
