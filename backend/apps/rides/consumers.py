import json
import logging
from datetime import datetime

from channels.db import database_sync_to_async
from channels.generic.websocket import AsyncWebsocketConsumer

logger = logging.getLogger(__name__)


class DriverConsumer(AsyncWebsocketConsumer):
    """WebSocket consumer for drivers to receive ride requests and send location."""

    async def connect(self):
        user = self.scope.get("user")
        if not user or user.is_anonymous:
            await self.close()
            return

        is_driver = await self._is_driver(user.id)
        if not is_driver:
            await self.close()
            return

        self.user = user
        self.driver_group = f"driver_{user.id}"
        self.broadcast_group = "available_drivers"

        await self.channel_layer.group_add(self.driver_group, self.channel_name)
        await self.channel_layer.group_add(self.broadcast_group, self.channel_name)
        await self.accept()
        logger.info("Driver WS connected: %s", user.id)

        # Check for pending rides that may need this driver
        await self._check_pending_rides()

    async def disconnect(self, close_code):
        if hasattr(self, "driver_group"):
            await self.channel_layer.group_discard(self.driver_group, self.channel_name)
        if hasattr(self, "broadcast_group"):
            await self.channel_layer.group_discard(self.broadcast_group, self.channel_name)

    async def receive(self, text_data):
        """Handle messages from driver: location updates, heartbeat."""
        try:
            data = json.loads(text_data)
        except json.JSONDecodeError:
            return

        msg_type = data.get("type")

        if msg_type == "location_update":
            # Update driver position in DB for matching
            await self._update_driver_location(
                data.get("latitude"),
                data.get("longitude"),
            )
        elif msg_type == "heartbeat":
            await self.send(text_data=json.dumps({"type": "heartbeat_ack"}))

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

    async def ride_reassigned(self, event):
        """Notify driver that ride was reassigned (timeout)."""
        await self.send(text_data=json.dumps({
            "type": "ride_reassigned",
            "ride_id": event["ride_id"],
        }))

    @database_sync_to_async
    def _is_driver(self, user_id):
        from apps.accounts.models import User
        return User.objects.filter(id=user_id, role="driver").exists()

    @database_sync_to_async
    def _update_driver_location(self, lat, lng):
        """Update driver's current position in DriverProfile."""
        if lat is None or lng is None:
            return
        from apps.accounts.models import DriverProfile
        from django.utils import timezone
        DriverProfile.objects.filter(user=self.user).update(
            current_latitude=lat,
            current_longitude=lng,
            last_location_update=timezone.now(),
        )

    @database_sync_to_async
    def _check_pending_rides(self):
        """When driver connects via WebSocket, check if there are REQUESTED rides
        nearby without an assigned driver and trigger assignment."""
        from apps.accounts.models import DriverProfile
        try:
            profile = DriverProfile.objects.get(user=self.user)
        except DriverProfile.DoesNotExist:
            return
        if not profile.is_online or profile.is_on_ride:
            return
        if not profile.current_latitude or not profile.current_longitude:
            return
        from .models import Ride
        from .views import _auto_assign_nearest_driver
        pending = Ride.objects.filter(
            status=Ride.Status.REQUESTED,
            assigned_driver__isnull=True,
        ).order_by("requested_at")[:5]
        for ride in pending:
            declined = ride.declined_driver_ids or []
            if self.user.id in declined:
                continue
            _auto_assign_nearest_driver(ride)
            ride.refresh_from_db()
            if ride.assigned_driver_id == self.user.id:
                break  # We got assigned — signal was already sent via channel


class RideTrackingConsumer(AsyncWebsocketConsumer):
    """WebSocket consumer for real-time ride tracking (both driver & passenger)."""

    async def connect(self):
        self.ride_id = self.scope["url_route"]["kwargs"]["ride_id"]
        self.room_group_name = f"ride_{self.ride_id}"

        user = self.scope.get("user")
        if not user or user.is_anonymous:
            await self.close()
            return

        self.user = user
        self.is_driver = await self._is_driver(user.id)

        # Verify user is part of this ride (as passenger, driver, or assigned driver)
        is_participant = await self._is_ride_participant(user.id, self.ride_id)
        if not is_participant:
            await self.close()
            return

        await self.channel_layer.group_add(self.room_group_name, self.channel_name)
        await self.accept()
        logger.info("Ride tracking WS connected: user=%s ride=%s", user.id, self.ride_id)

    async def disconnect(self, close_code):
        if hasattr(self, "room_group_name"):
            await self.channel_layer.group_discard(
                self.room_group_name, self.channel_name
            )

    async def receive(self, text_data):
        """Handle messages from participants: location updates from driver, heartbeat."""
        try:
            data = json.loads(text_data)
        except json.JSONDecodeError:
            return

        msg_type = data.get("type")

        if msg_type == "location_update" and self.is_driver:
            lat = data.get("latitude")
            lng = data.get("longitude")
            heading = data.get("heading")
            speed = data.get("speed")

            # Persist GPS breadcrumb to DB
            await self._save_location_log(lat, lng)

            # Broadcast to all participants (passenger sees driver move)
            await self.channel_layer.group_send(
                self.room_group_name,
                {
                    "type": "location.update",
                    "latitude": lat,
                    "longitude": lng,
                    "heading": heading,
                    "speed": speed,
                },
            )

        elif msg_type == "heartbeat":
            await self.send(text_data=json.dumps({"type": "heartbeat_ack"}))

    async def location_update(self, event):
        """Forward location to all group members."""
        await self.send(text_data=json.dumps({
            "type": "location_update",
            "latitude": event["latitude"],
            "longitude": event["longitude"],
            "heading": event.get("heading"),
            "speed": event.get("speed"),
        }))

    async def status_update(self, event):
        """Forward status change to all group members with full payload."""
        payload = {"type": "status_update"}
        forward_keys = (
            "status", "message", "assigned_driver", "expires_at",
            "timeout_seconds", "driver_name", "driver_id",
            "driver_phone", "driver_photo", "driver_rating",
            "vehicle", "vehicle_color", "license_plate",
            "final_price", "pickup_address", "destination_address",
            "estimated_price", "distance_km",
        )
        for key in forward_keys:
            if key in event:
                payload[key] = event[key]
        await self.send(text_data=json.dumps(payload))

    @database_sync_to_async
    def _is_ride_participant(self, user_id, ride_id):
        from django.db.models import Q
        from .models import Ride
        return Ride.objects.filter(id=ride_id).filter(
            Q(passenger_id=user_id) | Q(driver_id=user_id) | Q(assigned_driver_id=user_id)
        ).exists()

    @database_sync_to_async
    def _is_driver(self, user_id):
        from apps.accounts.models import User
        return User.objects.filter(id=user_id, role="driver").exists()

    @database_sync_to_async
    def _save_location_log(self, lat, lng):
        """Persist a GPS breadcrumb for the ride route."""
        if lat is None or lng is None:
            return
        from .models import RideLocationLog, Ride
        try:
            ride = Ride.objects.get(id=self.ride_id)
            if ride.status in ("in_progress", "accepted", "driver_arriving", "driver_arrived"):
                RideLocationLog.objects.create(
                    ride=ride,
                    latitude=lat,
                    longitude=lng,
                )
        except Ride.DoesNotExist:
            pass
