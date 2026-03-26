from django.contrib.auth import get_user_model
User = get_user_model()
u = User.objects.get(phone_number="+243900000000")
u.set_password("Mwamba@Super2026")
u.is_superuser = True
u.is_staff = True
u.is_active = True
u.save()
# Verify
ok = u.check_password("Mwamba@Super2026")
print(f"RESET_OK:{ok} PHONE:{u.phone_number} SUPER:{u.is_superuser}")
