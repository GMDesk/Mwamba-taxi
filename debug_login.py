from django.contrib.auth import get_user_model
User = get_user_model()
for u in User.objects.filter(role="admin"):
    print("PHONE:", u.phone_number)
    print("NAME:", u.full_name)
    print("ACTIVE:", u.is_active)
    print("STAFF:", u.is_staff)
    print("SUPER:", u.is_superuser)
    print("HAS_PASS:", u.has_usable_password())
    print("CHECK_PASS:", u.check_password("Mwamba@2026"))
    print("CHECK_PASS2:", u.check_password("Mwamba@Super2026"))
    print("---")
