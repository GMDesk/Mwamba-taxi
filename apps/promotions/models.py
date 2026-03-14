import uuid

from django.conf import settings
from django.db import models
from django.utils import timezone


class PromoCode(models.Model):
    """Promotional code for discounts."""

    class DiscountType(models.TextChoices):
        PERCENTAGE = "percentage", "Pourcentage"
        FIXED = "fixed", "Montant fixe"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    code = models.CharField("Code", max_length=20, unique=True, db_index=True)
    description = models.TextField("Description", blank=True, default="")
    discount_type = models.CharField(
        "Type de réduction",
        max_length=10,
        choices=DiscountType.choices,
        default=DiscountType.PERCENTAGE,
    )
    discount_value = models.DecimalField(
        "Valeur de la réduction", max_digits=10, decimal_places=2
    )
    max_discount = models.DecimalField(
        "Réduction maximale", max_digits=10, decimal_places=2, null=True, blank=True
    )
    min_ride_amount = models.DecimalField(
        "Montant minimum de course",
        max_digits=10,
        decimal_places=2,
        default=0.00,
    )
    max_uses = models.PositiveIntegerField("Utilisations max", default=100)
    used_count = models.PositiveIntegerField("Utilisations", default=0)
    max_uses_per_user = models.PositiveIntegerField(
        "Max par utilisateur", default=1
    )
    is_active = models.BooleanField("Actif", default=True)
    valid_from = models.DateTimeField("Valide à partir de", default=timezone.now)
    valid_until = models.DateTimeField("Valide jusqu'au")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "Code promo"
        verbose_name_plural = "Codes promo"
        ordering = ["-created_at"]

    def __str__(self):
        return self.code

    @property
    def is_valid(self):
        now = timezone.now()
        return (
            self.is_active
            and self.valid_from <= now <= self.valid_until
            and self.used_count < self.max_uses
        )

    def calculate_discount(self, amount):
        if self.discount_type == self.DiscountType.PERCENTAGE:
            discount = amount * (self.discount_value / 100)
        else:
            discount = self.discount_value

        if self.max_discount:
            discount = min(discount, self.max_discount)
        return round(discount, 2)


class PromoUsage(models.Model):
    """Tracks which user used which promo code."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    promo_code = models.ForeignKey(
        PromoCode, on_delete=models.CASCADE, related_name="usages"
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="promo_usages"
    )
    ride = models.ForeignKey(
        "rides.Ride", on_delete=models.SET_NULL, null=True, blank=True
    )
    discount_applied = models.DecimalField(max_digits=10, decimal_places=2)
    used_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "Utilisation promo"
        verbose_name_plural = "Utilisations promo"


class Referral(models.Model):
    """Referral / parrainage codes and bonuses."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    referrer = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="referrals_made",
    )
    referred = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="referred_by",
    )
    referral_code = models.CharField(max_length=20, db_index=True)
    bonus_given = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "Parrainage"
        verbose_name_plural = "Parrainages"
