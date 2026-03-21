from django.contrib.auth import get_user_model
User = get_user_model()
u = User.objects.get(phone_number="+243900000001")
u.set_password("Mwamba@2026")
u.role = "admin"
u.is_staff = True
u.is_phone_verified = True
u.save()
print("ADMIN_PASS_RESET:", u.phone_number, "CHECK:", u.check_password("Mwamba@2026"))
