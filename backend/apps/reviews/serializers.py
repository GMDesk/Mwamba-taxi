from rest_framework import serializers

from .models import Review


class ReviewSerializer(serializers.ModelSerializer):
    reviewer_name = serializers.CharField(source="reviewer.full_name", read_only=True)

    class Meta:
        model = Review
        fields = [
            "id", "ride", "reviewer", "reviewer_name",
            "reviewed_user", "rating", "comment", "created_at",
        ]
        read_only_fields = ["id", "reviewer", "reviewer_name", "created_at"]


class CreateReviewSerializer(serializers.Serializer):
    ride_id = serializers.UUIDField()
    rating = serializers.IntegerField(min_value=1, max_value=5)
    comment = serializers.CharField(required=False, allow_blank=True, default="")
