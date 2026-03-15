import hashlib
import secrets
import uuid

from django.conf import settings
from django.contrib.auth.models import AbstractBaseUser, BaseUserManager, PermissionsMixin
from django.core.validators import RegexValidator
from django.db import models
from django.utils import timezone


phone_validator = RegexValidator(
    regex=r"^\+?[1-9]\d{7,14}$",
    message="Le numéro de téléphone doit être au format international. Ex: +243812345678",
)


class UserManager(BaseUserManager):
    """Custom user manager – phone number as primary identifier."""

    def create_user(self, phone_number, password=None, **extra_fields):
        if not phone_number:
            raise ValueError("Le numéro de téléphone est obligatoire.")
        user = self.model(phone_number=phone_number, **extra_fields)
        if password:
            user.set_password(password)
        user.save(using=self._db)
        return user

    def create_superuser(self, phone_number, password=None, **extra_fields):
        extra_fields.setdefault("is_staff", True)
        extra_fields.setdefault("is_superuser", True)
        extra_fields.setdefault("role", User.Role.ADMIN)
        return self.create_user(phone_number, password, **extra_fields)


class User(AbstractBaseUser, PermissionsMixin):
    """Base user model for passengers, drivers, and admins."""

    class Role(models.TextChoices):
        PASSENGER = "passenger", "Passager"
        DRIVER = "driver", "Chauffeur"
        ADMIN = "admin", "Administrateur"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    phone_number = models.CharField(
        "Numéro de téléphone",
        max_length=16,
        unique=True,
        validators=[phone_validator],
    )
    full_name = models.CharField("Nom complet", max_length=150)
    email = models.EmailField("Email", blank=True, default="")
    role = models.CharField(
        "Rôle",
        max_length=10,
        choices=Role.choices,
        default=Role.PASSENGER,
    )
    avatar = models.ImageField("Photo de profil", upload_to="avatars/", blank=True)
    is_active = models.BooleanField("Actif", default=True)
    is_staff = models.BooleanField("Staff", default=False)
    is_phone_verified = models.BooleanField("Téléphone vérifié", default=False)
    fcm_token = models.CharField("Token FCM", max_length=255, blank=True, default="")
    created_at = models.DateTimeField("Créé le", auto_now_add=True)
    updated_at = models.DateTimeField("Modifié le", auto_now=True)

    objects = UserManager()

    USERNAME_FIELD = "phone_number"
    REQUIRED_FIELDS = ["full_name"]

    class Meta:
        verbose_name = "Utilisateur"
        verbose_name_plural = "Utilisateurs"
        ordering = ["-created_at"]

    def __str__(self):
        return f"{self.full_name} ({self.phone_number})"

    @property
    def is_driver(self):
        return self.role == self.Role.DRIVER

    @property
    def is_passenger(self):
        return self.role == self.Role.PASSENGER


class DriverProfile(models.Model):
    """Extended profile for drivers with vehicle & document info."""

    class Status(models.TextChoices):
        PENDING = "pending", "En attente"
        APPROVED = "approved", "Approuvé"
        REJECTED = "rejected", "Rejeté"
        SUSPENDED = "suspended", "Suspendu"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="driver_profile",
    )
    # Vehicle info
    vehicle_make = models.CharField("Marque véhicule", max_length=50)
    vehicle_model = models.CharField("Modèle véhicule", max_length=50)
    vehicle_year = models.PositiveIntegerField("Année du véhicule", null=True, blank=True)
    vehicle_color = models.CharField("Couleur véhicule", max_length=30)
    license_plate = models.CharField("Plaque d'immatriculation", max_length=20, unique=True)

    # Documents
    drivers_license_photo = models.ImageField(
        "Photo permis de conduire", upload_to="documents/licenses/"
    )
    vehicle_registration_photo = models.ImageField(
        "Photo carte grise", upload_to="documents/registrations/"
    )
    vehicle_photo = models.ImageField(
        "Photo du véhicule", upload_to="documents/vehicles/"
    )

    # Status
    status = models.CharField(
        "Statut du compte",
        max_length=10,
        choices=Status.choices,
        default=Status.PENDING,
    )
    rejection_reason = models.TextField("Raison du rejet", blank=True, default="")

    # Location & availability
    is_online = models.BooleanField("En ligne", default=False)
    is_on_ride = models.BooleanField("En course", default=False)
    current_latitude = models.DecimalField(
        "Latitude", max_digits=10, decimal_places=7, null=True, blank=True
    )
    current_longitude = models.DecimalField(
        "Longitude", max_digits=10, decimal_places=7, null=True, blank=True
    )
    last_location_update = models.DateTimeField(
        "Dernière mise à jour position", null=True, blank=True
    )

    # Stats
    rating_average = models.DecimalField(
        "Note moyenne", max_digits=3, decimal_places=2, default=5.00
    )
    total_rides = models.PositiveIntegerField("Courses totales", default=0)
    total_earnings = models.DecimalField(
        "Revenus totaux", max_digits=12, decimal_places=2, default=0.00
    )

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "Profil chauffeur"
        verbose_name_plural = "Profils chauffeurs"

    def __str__(self):
        return f"Chauffeur {self.user.full_name} – {self.license_plate}"

    @property
    def is_available(self):
        return (
            self.status == self.Status.APPROVED
            and self.is_online
            and not self.is_on_ride
        )


class OTPCode(models.Model):
    """One-Time Password for phone verification."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    phone_number = models.CharField(max_length=16, validators=[phone_validator])
    code_hash = models.CharField(max_length=64)
    is_used = models.BooleanField(default=False)
    attempts = models.PositiveSmallIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()

    class Meta:
        verbose_name = "Code OTP"
        verbose_name_plural = "Codes OTP"
        ordering = ["-created_at"]

    def save(self, *args, **kwargs):
        if not self.expires_at:
            self.expires_at = timezone.now() + timezone.timedelta(
                minutes=settings.OTP_EXPIRY_MINUTES
            )
        super().save(*args, **kwargs)

    @staticmethod
    def generate_code():
        """Generate a secure random OTP code."""
        code = "".join([str(secrets.randbelow(10)) for _ in range(settings.OTP_LENGTH)])
        return code

    @staticmethod
    def hash_code(code: str) -> str:
        return hashlib.sha256(code.encode()).hexdigest()

    @property
    def is_expired(self):
        return timezone.now() > self.expires_at

    def verify(self, code: str) -> bool:
        if self.is_used or self.is_expired:
            return False
        if self.attempts >= 5:
            return False
        self.attempts += 1
        self.save(update_fields=["attempts"])
        if self.hash_code(code) == self.code_hash:
            self.is_used = True
            self.save(update_fields=["is_used"])
            return True
        return False
