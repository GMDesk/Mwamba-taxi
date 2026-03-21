from django.contrib.auth import get_user_model
User = get_user_model()
for u in User.objects.filter(role="admin"):
    print("PHONE_REPR:", repr(u.phone_number))
    print("LEN:", len(u.phone_number))
