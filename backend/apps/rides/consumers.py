import json
import logging

from channels.db import database_sync_to_async
from channels.generic.websocket import AsyncWebsocketConsumer
from urllib.parse import parse_qs

logger = logging.getLogger(__name__)


class DriverConsumer(AsyncWebsocketConsumer):
    """WebSocket consumer for drivers to receive ride requests."""

    async def connect(self):
        user = self.scope.get("user")
        if not user or user.is_anonymous:
            await self.close()
            return

        is_driver = await self._is_driver(user.id)
        if not is_driver:
            await self.close()
            return

        self.driver_group = f"driver_{user.id}"
        self.broadcast_group = "available_drivers"

        await self.channel_layer.group_add(self.driver_group, self.channel_name)
        await self.channel_layer.group_add(self.broadcast_group, self.channel_name)
        await self.accept()

    async def disconnect(self, close_code):
        if hasattr(self, "driver_group"):
            await self.channel_layer.group_discard(self.driver_group, self.channel_name)
        if hasattr(self, "broadcast_group"):
            await self.channel_layer.group_discard(self.broadcast_group, self.channel_name)

    async def receive(self, text_data):
        pass

    async def ride_request(self, event):
        """Send ride request to driver."""
        await self.send(text_data=json.dumps({
            "type": "ride_request",
            "data": event["data"],
        }))

    async def ride_cancelled(self, event):
        """Notify driver that a ride was cancelled."""
        await self.send(text_data=json.dumps({
            "type": "ride_cancelled",
            "ride_id": event["ride_id"],
        }))

    @database_sync_to_async
    def _is_driver(self, user_id):
        from apps.accounts.models import User
        return User.objects.filter(id=user_id, role="driver").exists()


class RideTrackingConsumer(AsyncWebsocketConsumer):
    """WebSocket consumer for real-time ride tracking."""

    async def connect(self):
        self.ride_id = self.scope["url_route"]["kwargs"]["ride_id"]
        self.room_group_name = f"ride_{self.ride_id}"

        user = self.scope.get("user")
        if not user or user.is_anonymous:
            await self.close()
            return

        # Verify user is part of this ride
        is_participant = await self._is_ride_participant(user.id, self.ride_id)
        if not is_participant:
            await self.close()
            return

        await self.channel_layer.group_add(self.room_group_name, self.channel_name)
        await self.accept()

    async def disconnect(self, close_code):
        await self.channel_layer.group_discard(self.room_group_name, self.channel_name)

    async def receive(self, text_data):
        """Receive location update from driver."""
        try:
            data = json.loads(text_data)
        except json.JSONDecodeError:
            return

        msg_type = data.get("type")

        if msg_type == "location_update":
            await self.channel_layer.group_send(
                self.room_group_name,
                {
                    "type": "location.update",
                    "latitude": data.get("latitude"),
                    "longitude": data.get("longitude"),
                    "heading": data.get("heading"),
                    "speed": data.get("speed"),
                },
            )
        elif msg_type == "status_update":
            await self.channel_layer.group_send(
                self.room_group_name,
                {
                    "type": "status.update",
                    "status": data.get("status"),
                    "message": data.get("message", ""),
                },
            )

    async def location_update(self, event):
        await self.send(text_data=json.dumps({
            "type": "location_update",
            "latitude": event["latitude"],
            "longitude": event["longitude"],
            "heading": event.get("heading"),
            "speed": event.get("speed"),
        }))

    async def status_update(self, event):
        # Forward all fields from the event (status, message, driver info, etc.)
        payload = {"type": "status_update"}
        forward_keys = (
            "status", "message", "assigned_driver", "expires_at",
            "timeout_seconds", "driver_name", "driver_id",
            "driver_phone", "driver_photo", "driver_rating",
            "vehicle", "vehicle_color", "license_plate",
        )
        for key in forward_keys:
            if key in event:
                payload[key] = event[key]
        await self.send(text_data=json.dumps(payload))

    @database_sync_to_async
    def _is_ride_participant(self, user_id, ride_id):
        from django.db.models import Q
        from .models import Ride
        return Ride.objects.filter(
            id=ride_id
        ).filter(
            Q(passenger_id=user_id) | Q(driver_id=user_id)
        ).exists()
