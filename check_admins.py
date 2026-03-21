from django.contrib.auth import get_user_model
User = get_user_model()
admins = User.objects.filter(role="admin")
print("ADMIN_COUNT:", admins.count())
for u in admins:
    print("ADMIN:", u.phone_number, u.full_name)
if admins.count() == 0:
    print("NO_ADMIN_FOUND")
