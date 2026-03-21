from django.contrib.auth import get_user_model
User = get_user_model()
su, created = User.objects.get_or_create(
    phone_number="+243900000000",
    defaults={
        "full_name": "Super Admin",
        "role": "admin",
        "is_active": True,
        "is_staff": True,
        "is_superuser": True,
        "is_phone_verified": True,
    }
)
su.set_password("Mwamba@Super2026")
su.role = "admin"
su.is_staff = True
su.is_superuser = True
su.is_phone_verified = True
su.save()
if created:
    print("SUPERUSER_CREATED:", su.phone_number)
else:
    print("SUPERUSER_UPDATED:", su.phone_number)
