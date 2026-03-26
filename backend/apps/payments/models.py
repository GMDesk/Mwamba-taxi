import uuid
from decimal import Decimal

from django.conf import settings
from django.db import models


# ────────────────────────────────────────────────────────────────────────
# Wallet
# ────────────────────────────────────────────────────────────────────────
class Wallet(models.Model):
    """Internal wallet for passengers and drivers."""

    class Status(models.TextChoices):
        ACTIVE = "active", "Actif"
        BLOCKED = "blocked", "Bloqué"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="wallet",
    )
    balance = models.DecimalField(
        "Solde disponible", max_digits=12, decimal_places=2, default=0
    )
    held_amount = models.DecimalField(
        "Montant bloqué", max_digits=12, decimal_places=2, default=0,
        help_text="Amount pre-authorized for an ongoing ride",
    )
    currency = models.CharField("Devise", max_length=5, default="CDF")
    status = models.CharField(
        max_length=10, choices=Status.choices, default=Status.ACTIVE
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "Portefeuille"
        verbose_name_plural = "Portefeuilles"

    def __str__(self):
        return f"Wallet {self.user.full_name} – {self.balance} {self.currency}"

    @property
    def available_balance(self) -> Decimal:
        return self.balance - self.held_amount

    def can_afford(self, amount: Decimal) -> bool:
        return self.status == self.Status.ACTIVE and self.available_balance >= amount

    def hold(self, amount: Decimal):
        """Pre-authorize (block) an amount for a ride."""
        self.held_amount += amount
        self.save(update_fields=["held_amount", "updated_at"])

    def release_hold(self, amount: Decimal):
        """Release a previously held amount."""
        self.held_amount = max(Decimal("0"), self.held_amount - amount)
        self.save(update_fields=["held_amount", "updated_at"])

    def debit(self, amount: Decimal):
        """Debit wallet (deduct from balance)."""
        self.balance -= amount
        self.save(update_fields=["balance", "updated_at"])

    def credit(self, amount: Decimal):
        """Credit wallet (add to balance)."""
        self.balance += amount
        self.save(update_fields=["balance", "updated_at"])


# ────────────────────────────────────────────────────────────────────────
# Wallet Transaction
# ────────────────────────────────────────────────────────────────────────
class WalletTransaction(models.Model):
    """Ledger entry for every wallet movement."""

    class TxType(models.TextChoices):
        DEPOSIT = "deposit", "Dépôt"
        RIDE_PAYMENT = "ride_payment", "Paiement course"
        RIDE_HOLD = "ride_hold", "Pré-autorisation"
        RIDE_HOLD_RELEASE = "hold_release", "Libération blocage"
        REFUND = "refund", "Remboursement"
        COMMISSION = "commission", "Commission"
        RIDE_EARNING = "ride_earning", "Revenu course"
        PAYOUT = "payout", "Retrait Mobile Money"

    class Status(models.TextChoices):
        PENDING = "pending", "En attente"
        COMPLETED = "completed", "Complété"
        FAILED = "failed", "Échoué"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    wallet = models.ForeignKey(
        Wallet, on_delete=models.CASCADE, related_name="transactions"
    )
    tx_type = models.CharField(
        "Type", max_length=15, choices=TxType.choices
    )
    amount = models.DecimalField("Montant", max_digits=12, decimal_places=2)
    balance_after = models.DecimalField(
        "Solde après", max_digits=12, decimal_places=2
    )
    status = models.CharField(
        max_length=10, choices=Status.choices, default=Status.COMPLETED
    )
    description = models.CharField(max_length=255, blank=True, default="")
    ride = models.ForeignKey(
        "rides.Ride", on_delete=models.SET_NULL, null=True, blank=True,
        related_name="wallet_transactions",
    )
    provider_reference = models.CharField(
        "Réf. fournisseur", max_length=100, blank=True, default=""
    )
    metadata = models.JSONField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "Transaction wallet"
        verbose_name_plural = "Transactions wallet"
        ordering = ["-created_at"]

    def __str__(self):
        return f"{self.get_tx_type_display()} {self.amount} – {self.get_status_display()}"


# ────────────────────────────────────────────────────────────────────────
# Payment (ride-level — kept for backward compat)
# ────────────────────────────────────────────────────────────────────────
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
        default=Method.WALLET,
    )
    status = models.CharField(
        "Statut", max_length=12, choices=Status.choices, default=Status.PENDING
    )

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


# ────────────────────────────────────────────────────────────────────────
# Driver Payout
# ────────────────────────────────────────────────────────────────────────
class DriverPayout(models.Model):
    """Payout record – money transferred to driver via Mobile Money."""

    class Status(models.TextChoices):
        PENDING = "pending", "En attente"
        PROCESSING = "processing", "En cours"
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
        max_length=12, choices=Status.choices, default=Status.PENDING
    )
    phone_number = models.CharField("Numéro retrait", max_length=16, blank=True, default="")

    provider_transaction_id = models.CharField(max_length=100, blank=True, default="")
    provider_response = models.JSONField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    completed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        verbose_name = "Versement chauffeur"
        verbose_name_plural = "Versements chauffeurs"
        ordering = ["-created_at"]

    def __str__(self):
        return f"Payout {self.amount} {self.currency} → {self.driver.full_name}"
