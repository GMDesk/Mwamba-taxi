from django.contrib.auth import get_user_model
User = get_user_model()
print("TOTAL_USERS:", User.objects.count())
for u in User.objects.all()[:10]:
    print("USER:", u.phone_number, u.full_name, u.role, "active:", u.is_active, "has_pw:", u.has_usable_password())
