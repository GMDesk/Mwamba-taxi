from django.contrib.auth import get_user_model
User = get_user_model()
admin, created = User.objects.get_or_create(
    phone_number="+243900000001",
    defaults={
        "full_name": "Admin Mwamba",
        "role": "admin",
        "is_active": True,
        "is_staff": True,
        "is_phone_verified": True,
    }
)
if created:
    admin.set_password("Mwamba@2026")
    admin.save()
    print("ADMIN_CREATED:", admin.phone_number)
else:
    print("ADMIN_EXISTS:", admin.phone_number)
