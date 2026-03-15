from rest_framework import generics, permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import Notification
from .serializers import NotificationSerializer


class NotificationListView(generics.ListAPIView):
    """Get all notifications for current user."""

    serializer_class = NotificationSerializer

    def get_queryset(self):
        return Notification.objects.filter(recipient=self.request.user)


class MarkNotificationReadView(APIView):
    """Mark a notification as read."""

    def post(self, request, notification_id):
        try:
            notif = Notification.objects.get(
                id=notification_id, recipient=request.user
            )
        except Notification.DoesNotExist:
            return Response(status=status.HTTP_404_NOT_FOUND)

        notif.is_read = True
        notif.save(update_fields=["is_read"])
        return Response({"message": "Notification lue."})


class MarkAllReadView(APIView):
    """Mark all notifications as read."""

    def post(self, request):
        Notification.objects.filter(
            recipient=request.user, is_read=False
        ).update(is_read=True)
        return Response({"message": "Toutes les notifications marquées comme lues."})


class UnreadCountView(APIView):
    """Get unread notification count."""

    def get(self, request):
        count = Notification.objects.filter(
            recipient=request.user, is_read=False
        ).count()
        return Response({"unread_count": count})


class UpdateFCMTokenView(APIView):
    """Update FCM push token."""

    def post(self, request):
        token = request.data.get("fcm_token")
        if not token:
            return Response(
                {"detail": "fcm_token requis."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        request.user.fcm_token = token
        request.user.save(update_fields=["fcm_token"])
        return Response({"message": "Token FCM mis à jour."})
