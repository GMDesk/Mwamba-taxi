from django.contrib.auth import get_user_model
User = get_user_model()
u = User.objects.get(phone_number="+243900000001")
print("CHECK_PW_Mwamba@2026:", u.check_password("Mwamba@2026"))
u2 = User.objects.get(phone_number="+243900000000")
print("CHECK_PW_Mwamba@Super2026:", u2.check_password("Mwamba@Super2026"))
