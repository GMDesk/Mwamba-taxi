import 'package:flutter/foundation.dart';

/// Shared notifier so all screens stay in sync with driver online status.
class DriverStatusNotifier extends ValueNotifier<bool> {
  DriverStatusNotifier() : super(false);
}
