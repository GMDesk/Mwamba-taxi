import 'package:dio/dio.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../constants/api_constants.dart';

/// Provides driving route polylines via Google Directions API.
class RouteService {
  static const String _directionsUrl =
      'https://maps.googleapis.com/maps/api/directions/json';

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  /// Returns the driving route polyline + duration + distance between [origin] and [destination].
  Future<RouteResult?> getRoute(LatLng origin, LatLng destination) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        _directionsUrl,
        queryParameters: {
          'origin': '${origin.latitude},${origin.longitude}',
          'destination': '${destination.latitude},${destination.longitude}',
          'mode': 'driving',
          'language': 'fr',
          'key': ApiConstants.googleMapsApiKey,
        },
      );
      final data = response.data!;
      if (data['status'] != 'OK') return null;
      final routes = data['routes'] as List<dynamic>;
      if (routes.isEmpty) return null;

      final route = routes[0] as Map<String, dynamic>;
      final leg = (route['legs'] as List).first as Map<String, dynamic>;
      final encodedPolyline =
          route['overview_polyline']['points'] as String;

      // Parse turn-by-turn navigation steps
      final rawSteps = leg['steps'] as List<dynamic>? ?? [];
      final navSteps = <NavigationStep>[];
      for (final s in rawSteps) {
        final step = s as Map<String, dynamic>;
        final startLoc = step['start_location'] as Map<String, dynamic>;
        final endLoc = step['end_location'] as Map<String, dynamic>;
        final instruction = (step['html_instructions'] as String? ?? '')
            .replaceAll(RegExp(r'<[^>]+>'), ''); // strip HTML tags
        navSteps.add(NavigationStep(
          instruction: instruction,
          maneuver: step['maneuver'] as String? ?? '',
          distanceText: (step['distance'] as Map<String, dynamic>?)?['text'] as String? ?? '',
          distanceMeters: (step['distance'] as Map<String, dynamic>?)?['value'] as int? ?? 0,
          durationText: (step['duration'] as Map<String, dynamic>?)?['text'] as String? ?? '',
          startLocation: LatLng(
            (startLoc['lat'] as num).toDouble(),
            (startLoc['lng'] as num).toDouble(),
          ),
          endLocation: LatLng(
            (endLoc['lat'] as num).toDouble(),
            (endLoc['lng'] as num).toDouble(),
          ),
        ));
      }

      return RouteResult(
        points: _decodePolyline(encodedPolyline),
        durationText: leg['duration']['text'] as String,
        durationSeconds: leg['duration']['value'] as int,
        distanceText: leg['distance']['text'] as String,
        distanceMeters: leg['distance']['value'] as int,
        steps: navSteps,
      );
    } catch (_) {
      return null;
    }
  }

  List<LatLng> _decodePolyline(String encoded) {
    final List<LatLng> points = [];
    int index = 0;
    final int len = encoded.length;
    int lat = 0;
    int lng = 0;

    while (index < len) {
      int b;
      int shift = 0;
      int result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }
}

/// A single turn-by-turn navigation step.
class NavigationStep {
  final String instruction;
  final String maneuver;
  final String distanceText;
  final int distanceMeters;
  final String durationText;
  final LatLng startLocation;
  final LatLng endLocation;

  const NavigationStep({
    required this.instruction,
    required this.maneuver,
    required this.distanceText,
    required this.distanceMeters,
    required this.durationText,
    required this.startLocation,
    required this.endLocation,
  });
}

class RouteResult {
  final List<LatLng> points;
  final String durationText;
  final int durationSeconds;
  final String distanceText;
  final int distanceMeters;
  final List<NavigationStep> steps;

  const RouteResult({
    required this.points,
    required this.durationText,
    required this.durationSeconds,
    required this.distanceText,
    required this.distanceMeters,
    this.steps = const [],
  });
}
