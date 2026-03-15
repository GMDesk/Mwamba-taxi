import logging

from django.conf import settings

from .models import Notification

logger = logging.getLogger(__name__)


def send_push_notification(user, title: str, body: str, data: dict = None):
    """Send push notification via Firebase Cloud Messaging & store in DB."""
    # Store in database
    Notification.objects.create(
        recipient=user,
        title=title,
        body=body,
        channel=Notification.Channel.PUSH,
        category=_get_category(data),
        data=data,
    )

    # Send via FCM
    if user.fcm_token and settings.FIREBASE_CREDENTIALS_PATH:
        try:
            import firebase_admin
            from firebase_admin import messaging

            if not firebase_admin._apps:
                cred = firebase_admin.credentials.Certificate(
                    settings.FIREBASE_CREDENTIALS_PATH
                )
                firebase_admin.initialize_app(cred)

            message = messaging.Message(
                notification=messaging.Notification(title=title, body=body),
                data={k: str(v) for k, v in (data or {}).items()},
                token=user.fcm_token,
            )
            messaging.send(message)
        except Exception:
            logger.exception("FCM send failed for user %s", user.id)


def send_sms(phone_number: str, message: str):
    """Send SMS via Twilio."""
    if not settings.TWILIO_ACCOUNT_SID:
        logger.info("SMS (dev mode) to %s: %s", phone_number, message)
        return

    try:
        from twilio.rest import Client

        client = Client(settings.TWILIO_ACCOUNT_SID, settings.TWILIO_AUTH_TOKEN)
        client.messages.create(
            body=message,
            from_=settings.TWILIO_PHONE_NUMBER,
            to=phone_number,
        )
    except Exception:
        logger.exception("SMS send failed to %s", phone_number)


def _get_category(data):
    if not data:
        return Notification.Category.SYSTEM
    msg_type = data.get("type", "")
    if "ride" in msg_type:
        return Notification.Category.RIDE
    if "payment" in msg_type:
        return Notification.Category.PAYMENT
    if "promo" in msg_type:
        return Notification.Category.PROMO
    if "sos" in msg_type:
        return Notification.Category.SOS
    return Notification.Category.SYSTEM
