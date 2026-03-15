from django.urls import re_path

from . import consumers

websocket_urlpatterns = [
    re_path(r"ws/driver/$", consumers.DriverConsumer.as_asgi()),
    re_path(r"ws/ride/(?P<ride_id>[0-9a-f-]+)/$", consumers.RideTrackingConsumer.as_asgi()),
]
