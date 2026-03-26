from django.contrib.auth import get_user_model
User = get_user_model()
for u in User.objects.filter(is_staff=True):
    print(f"PHONE:{u.phone_number} STAFF:{u.is_staff} SUPER:{u.is_superuser} ROLE:{u.role} ACTIVE:{u.is_active} VERIFIED:{u.is_phone_verified}")
print("---DONE---")
