from django.db.models import Avg
from rest_framework import generics, permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.models import DriverProfile
from apps.rides.models import Ride

from .models import Review
from .serializers import CreateReviewSerializer, ReviewSerializer


class CreateReviewView(APIView):
    """Passenger rates the driver after a completed ride."""

    def post(self, request):
        serializer = CreateReviewSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        try:
            ride = Ride.objects.get(
                id=data["ride_id"],
                passenger=request.user,
                status=Ride.Status.COMPLETED,
            )
        except Ride.DoesNotExist:
            return Response(
                {"detail": "Course non trouvée ou non terminée."},
                status=status.HTTP_404_NOT_FOUND,
            )

        if hasattr(ride, "review"):
            return Response(
                {"detail": "Vous avez déjà noté cette course."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if not ride.driver:
            return Response(
                {"detail": "Aucun chauffeur pour cette course."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        review = Review.objects.create(
            ride=ride,
            reviewer=request.user,
            reviewed_user=ride.driver,
            rating=data["rating"],
            comment=data.get("comment", ""),
        )

        # Update driver average rating
        avg = Review.objects.filter(
            reviewed_user=ride.driver
        ).aggregate(avg=Avg("rating"))["avg"]
        if avg and hasattr(ride.driver, "driver_profile"):
            ride.driver.driver_profile.rating_average = round(avg, 2)
            ride.driver.driver_profile.save(update_fields=["rating_average"])

        return Response(ReviewSerializer(review).data, status=status.HTTP_201_CREATED)


class DriverReviewsView(generics.ListAPIView):
    """Get all reviews for a specific driver."""

    serializer_class = ReviewSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        driver_id = self.kwargs.get("driver_id")
        return Review.objects.filter(reviewed_user_id=driver_id)
