import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  VEHICLE ANIMATOR  –  GPS smoothing, bearing interpolation, position
//  prediction, and fluid movement between coordinate updates.
// ═════════════════════════════════════════════════════════════════════════════

/// Callback invoked on every animation frame with the interpolated position
/// and bearing that should be applied to the map marker.
typedef VehicleFrame = void Function(LatLng position, double bearing);

class VehicleAnimator {
  VehicleAnimator({
    required TickerProvider vsync,
    required this.onFrame,
    Duration duration = const Duration(milliseconds: 1200),
  })  : _vsync = vsync,
        _duration = duration {
    _controller = AnimationController(vsync: _vsync, duration: _duration)
      ..addListener(_tick);
  }

  final TickerProvider _vsync;
  final Duration _duration;
  final VehicleFrame onFrame;

  late AnimationController _controller;

  // Position state
  LatLng? _fromPos;
  LatLng? _toPos;
  LatLng? _currentPos;

  // Bearing state
  double _fromBearing = 0;
  double _toBearing = 0;
  double _currentBearing = 0;

  // Speed estimation for prediction
  double _lastSpeed = 0;       // m/s
  double _lastBearingRad = 0;

  // Smoothing buffer (rolling average over last N points)
  final List<LatLng> _buffer = [];
  static const int _bufferSize = 3;

  /// The most recent interpolated position.
  LatLng? get currentPosition => _currentPos;

  /// The most recent interpolated bearing in degrees.
  double get currentBearing => _currentBearing;

  // ── Public API ───────────────────────────────────────────────────────────

  /// Push a new raw GPS position + optional server-provided bearing.
  /// The animator will smoothly move from the current location to this one.
  void pushPosition(LatLng raw, {double? bearing}) {
    final smoothed = _smooth(raw);

    // Estimate speed from last known position
    if (_currentPos != null) {
      final dist = _haversine(_currentPos!, smoothed);
      final dt = _duration.inMilliseconds / 1000.0;
      _lastSpeed = dist / dt;  // m/s approximation
    }

    _fromPos = _currentPos ?? smoothed;
    _toPos = smoothed;

    // Bearing
    final newBearing = bearing ?? _computeBearing(_fromPos!, _toPos!);
    _fromBearing = _currentBearing;
    _toBearing = _shortestAngle(_fromBearing, newBearing);
    _lastBearingRad = newBearing * math.pi / 180;

    _controller.forward(from: 0);
  }

  /// Predict the next position based on current speed + bearing.
  /// Useful to keep the car moving when GPS updates are delayed.
  void predictAhead(Duration elapsed) {
    if (_currentPos == null || _lastSpeed == 0) return;
    final dt = elapsed.inMilliseconds / 1000.0;
    final dist = _lastSpeed * dt;
    // Move along the last bearing
    final predicted = _offsetLatLng(_currentPos!, dist, _lastBearingRad);
    _fromPos = _currentPos;
    _toPos = predicted;
    _fromBearing = _currentBearing;
    _toBearing = _currentBearing;
    _controller.forward(from: 0);
  }

  void dispose() {
    _controller.dispose();
  }

  // ── Internal ─────────────────────────────────────────────────────────────

  void _tick() {
    if (_fromPos == null || _toPos == null) return;
    final t = Curves.easeInOut.transform(_controller.value);

    // Interpolate position
    final lat = _fromPos!.latitude  + (_toPos!.latitude  - _fromPos!.latitude)  * t;
    final lng = _fromPos!.longitude + (_toPos!.longitude - _fromPos!.longitude) * t;
    _currentPos = LatLng(lat, lng);

    // Interpolate bearing (shortest path)
    _currentBearing = _lerpAngle(_fromBearing, _toBearing, t);

    onFrame(_currentPos!, _currentBearing);

    // Snap when done
    if (_controller.isCompleted) {
      _fromPos = _toPos;
      _fromBearing = _toBearing;
    }
  }

  /// Rolling-average smoother to reduce GPS jitter.
  LatLng _smooth(LatLng raw) {
    _buffer.add(raw);
    if (_buffer.length > _bufferSize) _buffer.removeAt(0);
    double lat = 0, lng = 0;
    for (final p in _buffer) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return LatLng(lat / _buffer.length, lng / _buffer.length);
  }

  /// Compute bearing (degrees, 0=N) from A to B.
  static double _computeBearing(LatLng a, LatLng b) {
    final dLng = (b.longitude - a.longitude) * math.pi / 180;
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  /// Haversine distance in metres.
  static double _haversine(LatLng a, LatLng b) {
    const R = 6371000.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLng = (b.longitude - a.longitude) * math.pi / 180;
    final sLat = math.sin(dLat / 2);
    final sLng = math.sin(dLng / 2);
    final h = sLat * sLat +
        math.cos(a.latitude * math.pi / 180) *
            math.cos(b.latitude * math.pi / 180) *
            sLng * sLng;
    return 2 * R * math.asin(math.sqrt(h));
  }

  /// Offset a LatLng by [distMetres] along [bearingRad].
  static LatLng _offsetLatLng(LatLng origin, double distMetres, double bearingRad) {
    const R = 6371000.0;
    final lat1 = origin.latitude * math.pi / 180;
    final lng1 = origin.longitude * math.pi / 180;
    final lat2 = math.asin(
      math.sin(lat1) * math.cos(distMetres / R) +
          math.cos(lat1) * math.sin(distMetres / R) * math.cos(bearingRad),
    );
    final lng2 = lng1 +
        math.atan2(
          math.sin(bearingRad) * math.sin(distMetres / R) * math.cos(lat1),
          math.cos(distMetres / R) - math.sin(lat1) * math.sin(lat2),
        );
    return LatLng(lat2 * 180 / math.pi, lng2 * 180 / math.pi);
  }

  /// Adjust target bearing so we rotate via the shortest arc.
  static double _shortestAngle(double from, double to) {
    double diff = (to - from + 180) % 360 - 180;
    return from + diff;
  }

  /// Linear interpolation of two angles (already shortest-path adjusted).
  static double _lerpAngle(double from, double to, double t) {
    return from + (to - from) * t;
  }
}
