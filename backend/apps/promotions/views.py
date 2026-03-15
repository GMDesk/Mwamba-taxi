from decimal import Decimal

from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import PromoCode, PromoUsage
from .serializers import ValidatePromoSerializer


class ValidatePromoCodeView(APIView):
    """Validate and preview a promo code."""

    def post(self, request):
        serializer = ValidatePromoSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        try:
            promo = PromoCode.objects.get(code=data["code"].upper())
        except PromoCode.DoesNotExist:
            return Response(
                {"valid": False, "message": "Code promo introuvable."},
                status=status.HTTP_404_NOT_FOUND,
            )

        if not promo.is_valid:
            return Response(
                {"valid": False, "message": "Code promo expiré ou désactivé."}
            )

        # Check per-user limit
        user_uses = PromoUsage.objects.filter(
            promo_code=promo, user=request.user
        ).count()
        if user_uses >= promo.max_uses_per_user:
            return Response(
                {"valid": False, "message": "Vous avez déjà utilisé ce code promo."}
            )

        ride_amount = data.get("ride_amount", Decimal("0"))
        if ride_amount and ride_amount < promo.min_ride_amount:
            return Response(
                {
                    "valid": False,
                    "message": f"Montant minimum requis : {promo.min_ride_amount} CDF.",
                }
            )

        discount = promo.calculate_discount(ride_amount) if ride_amount else 0

        return Response({
            "valid": True,
            "code": promo.code,
            "discount_type": promo.discount_type,
            "discount_value": str(promo.discount_value),
            "estimated_discount": str(discount),
            "description": promo.description,
        })
