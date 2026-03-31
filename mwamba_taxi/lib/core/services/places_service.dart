import 'package:dio/dio.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../constants/api_constants.dart';

/// Result of a route query containing polyline points and duration.
class RouteResult {
  final List<LatLng> points;
  final int durationSeconds;
  final String durationText;
  final int distanceMeters;

  const RouteResult({
    required this.points,
    required this.durationSeconds,
    required this.durationText,
    required this.distanceMeters,
  });

  static const empty = RouteResult(points: [], durationSeconds: 0, durationText: '', distanceMeters: 0);
}

/// A prediction returned by the Places Autocomplete API.
class PlacePrediction {
  final String placeId;
  final String description;
  final String mainText;
  final String secondaryText;

  const PlacePrediction({
    required this.placeId,
    required this.description,
    required this.mainText,
    required this.secondaryText,
  });

  factory PlacePrediction.fromJson(Map<String, dynamic> json) {
    final structured = json['structured_formatting'] as Map<String, dynamic>? ?? {};
    return PlacePrediction(
      placeId: json['place_id'] as String,
      description: json['description'] as String,
      mainText: structured['main_text'] as String? ?? json['description'] as String,
      secondaryText: structured['secondary_text'] as String? ?? '',
    );
  }
}

/// Wraps the Google Places Autocomplete + Place Details + Directions REST APIs.
/// All calls are biased to the Kinshasa region (DRC).
class PlacesService {
  static const String _autocompleteUrl =
      'https://maps.googleapis.com/maps/api/place/autocomplete/json';
  static const String _detailsUrl =
      'https://maps.googleapis.com/maps/api/place/details/json';
  static const String _directionsUrl =
      'https://maps.googleapis.com/maps/api/directions/json';

  // Kinshasa bounding center + 50 km radius bias
  static const String _locationBias = '-4.3317,15.3262';
  static const int _radiusMeters = 50000;

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  /// Returns up to 5 autocomplete predictions for [query] in Kinshasa / DRC.
  Future<List<PlacePrediction>> autocomplete(String query) async {
    if (query.trim().isEmpty) return [];
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        _autocompleteUrl,
        queryParameters: {
          'input': query,
          'components': 'country:cd',       // restrict to DR Congo
          'location': _locationBias,
          'radius': _radiusMeters,
          'language': 'fr',
          'key': ApiConstants.googleMapsApiKey,
        },
      );
      final data = response.data!;
      if (data['status'] != 'OK' && data['status'] != 'ZERO_RESULTS') {
        return [];
      }
      final predictions = (data['predictions'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .map(PlacePrediction.fromJson)
          .take(5)
          .toList();
      return predictions;
    } catch (_) {
      return [];
    }
  }

  /// Fetches the [LatLng] coordinates for a given [placeId].
  /// Returns null on failure.
  Future<LatLng?> getPlaceLatLng(String placeId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        _detailsUrl,
        queryParameters: {
          'place_id': placeId,
          'fields': 'geometry',
          'key': ApiConstants.googleMapsApiKey,
        },
      );
      final data = response.data!;
      if (data['status'] != 'OK') return null;
      final location =
          (data['result'] as Map<String, dynamic>)['geometry']['location']
              as Map<String, dynamic>;
      return LatLng(
        (location['lat'] as num).toDouble(),
        (location['lng'] as num).toDouble(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Returns the driving route between [origin] and [destination] with
  /// polyline points, duration and distance info.
  Future<RouteResult> getRoutePolyline(LatLng origin, LatLng destination) async {
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
      if (data['status'] != 'OK') return RouteResult.empty;
      final routes = data['routes'] as List<dynamic>;
      if (routes.isEmpty) return RouteResult.empty;
      final route = routes[0] as Map<String, dynamic>;
      final encodedPolyline = route['overview_polyline']['points'] as String;
      final leg = (route['legs'] as List<dynamic>)[0] as Map<String, dynamic>;
      final duration = leg['duration'] as Map<String, dynamic>;
      final distance = leg['distance'] as Map<String, dynamic>;
      return RouteResult(
        points: _decodePolyline(encodedPolyline),
        durationSeconds: (duration['value'] as num).toInt(),
        durationText: duration['text'] as String,
        distanceMeters: (distance['value'] as num).toInt(),
      );
    } catch (_) {
      return RouteResult.empty;
    }
  }

  /// Reverse-geocodes a [LatLng] to a human-readable address string.
  /// Returns null on failure.
  Future<String?> reverseGeocode(LatLng position) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'https://maps.googleapis.com/maps/api/geocode/json',
        queryParameters: {
          'latlng': '${position.latitude},${position.longitude}',
          'language': 'fr',
          'key': ApiConstants.googleMapsApiKey,
        },
      );
      final data = response.data!;
      if (data['status'] != 'OK') return null;
      final results = data['results'] as List<dynamic>;
      if (results.isEmpty) return null;
      return results[0]['formatted_address'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Decodes a Google Maps encoded polyline string into a list of [LatLng].
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
      final int dLat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dLat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final int dLng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dLng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }
}
