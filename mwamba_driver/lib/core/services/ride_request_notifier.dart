import 'package:flutter/foundation.dart';

/// Shared notifier so all screens stay in sync with incoming ride requests.
/// Only DriverHomeScreen manages the WebSocket — other screens just listen.
class RideRequestNotifier extends ValueNotifier<Map<String, dynamic>?> {
  RideRequestNotifier() : super(null);
}
