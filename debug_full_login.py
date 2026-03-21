from django.contrib.auth import get_user_model
from apps.accounts.serializers import LoginSerializer
User = get_user_model()

# Simulate what the view does
data = {"phone_number": "+243900000001", "password": "Mwamba@2026"}
serializer = LoginSerializer(data=data)
valid = serializer.is_valid()
print("VALID:", valid)
if valid:
    vd = serializer.validated_data
    print("VALIDATED:", vd)
    try:
        user = User.objects.get(phone_number=vd["phone_number"])
        print("USER_FOUND:", user.phone_number, user.full_name)
        print("CHECK:", user.check_password(vd["password"]))
    except User.DoesNotExist:
        print("USER_NOT_FOUND")
else:
    print("ERRORS:", serializer.errors)
