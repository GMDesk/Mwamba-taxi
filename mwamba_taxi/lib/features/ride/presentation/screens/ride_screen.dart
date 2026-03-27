import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/places_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/car_marker_icon.dart';

class RideScreen extends StatefulWidget {
  final String rideId;

  const RideScreen({super.key, required this.rideId});

  @override
  State<RideScreen> createState() => _RideScreenState();
}

class _RideScreenState extends State<RideScreen> with TickerProviderStateMixin {
  final ApiClient _api = getIt<ApiClient>();
  final PlacesService _placesService = PlacesService();
  final Completer<GoogleMapController> _mapController = Completer();

  Map<String, dynamic>? _ride;
  WebSocketChannel? _channel;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  LatLng? _driverPosition;
  LatLng? _driverTargetPosition; // smooth interpolation target
  double _driverHeading = 0;
  bool _isLoading = true;

  // Auto-assignment state
  Map<String, dynamic>? _assignedDriver;
  int _assignmentCountdown = 15;
  int _assignmentTotalTimeout = 15;
  Timer? _assignmentTimer;

  BitmapDescriptor _carIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);

  // Searching animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Search car rotation animation
  late AnimationController _searchCarController;
  late Animation<double> _searchCarAnimation;

  // Nearby drivers refresh
  Timer? _driverRefreshTimer;

  // Smooth driver movement animation
  late AnimationController _moveController;

  // Countdown for estimated wait
  int _estimatedWaitSeconds = 180; // 3 min default
  Timer? _waitTimer;

  // Driver ETA tracking
  double? _driverEtaMinutes;
  double? _driverDistanceKm;

  // WebSocket reconnection
  int _wsReconnectAttempts = 0;
  Timer? _wsReconnectTimer;
  bool _wsDisposed = false;

  // Heartbeat to keep WS alive
  Timer? _heartbeatTimer;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _searchCarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _searchCarAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _searchCarController, curve: Curves.linear),
    );

    _moveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..addListener(_interpolateDriverPosition);

    _initCarIcon();
    _loadRide();
    _connectWebSocket();
    _driverRefreshTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _loadNearbyDrivers(),
    );

    // Start wait countdown
    _waitTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_estimatedWaitSeconds > 0 && mounted) {
        setState(() => _estimatedWaitSeconds--);
      }
    });
  }

  Future<void> _initCarIcon() async {
    final icon = await createCarMarkerIcon();
    if (mounted) {
      setState(() => _carIcon = icon);
      // Reload markers with the new icon
      _loadNearbyDrivers();
    }
  }

  Future<void> _loadRide() async {
    try {
      final response = await _api.dio.get(
        ApiConstants.rideDetail(widget.rideId),
      );
      if (!mounted) return;
      final newStatus = response.data['status'] as String?;

      // Pick up assigned driver info from API (for page reload / first load)
      final assignedInfo = response.data['assigned_driver_info'];
      if (assignedInfo != null && newStatus == 'requested' && _assignedDriver == null) {
        _assignedDriver = assignedInfo is Map<String, dynamic> ? assignedInfo : null;
        if (_assignedDriver != null) _startAssignmentCountdown();
      }

      setState(() {
        _ride = response.data;
        _isLoading = false;
      });

      _updateMarkers();
      await _drawRoute();
      await _loadNearbyDrivers();
      await _fitCameraToRoute();
    } catch (e) {
      debugPrint('Error loading ride: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showDriverArrivedNotification() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.directions_car_rounded, color: Colors.white, size: 20.sp),
            SizedBox(width: 10.w),
            Expanded(
              child: Text(
                'Votre chauffeur est arrivé !',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
      ),
    );
  }

  void _showRideCompletedSheet() {
    final fare = _ride?['final_price'] ?? _ride?['estimated_price'] ?? '0';
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.fromLTRB(24.w, 20.h, 24.w, 32.h),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 70.w,
              height: 70.w,
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_circle_rounded, color: AppColors.success, size: 40.sp),
            ),
            SizedBox(height: 16.h),
            Text(
              'Course terminée !',
              style: GoogleFonts.poppins(
                fontSize: 20.sp,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              '$fare CDF',
              style: GoogleFonts.poppins(
                fontSize: 26.sp,
                fontWeight: FontWeight.w800,
                color: AppColors.primaryDark,
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              'Montant total',
              style: GoogleFonts.poppins(fontSize: 13.sp, color: AppColors.textSecondary),
            ),
            SizedBox(height: 24.h),
            SizedBox(
              width: double.infinity,
              height: 56.h,
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: AppColors.ctaGradient),
                  borderRadius: BorderRadius.circular(18.r),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18.r),
                    onTap: () {
                      Navigator.pop(ctx);
                      context.push('/ride/${widget.rideId}/rate');
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.star_rounded, color: Colors.white, size: 22.sp),
                        SizedBox(width: 8.w),
                        Text(
                          'Noter le chauffeur',
                          style: GoogleFonts.poppins(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: 12.h),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.go('/home');
              },
              child: Text(
                'Retour à l\'accueil',
                style: GoogleFonts.poppins(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _connectWebSocket() async {
    if (_wsDisposed) return;
    final token = await _api.getAccessToken();
    if (token == null) return;
    final wsUrl = '${ApiConstants.wsBaseUrl}/ride/${widget.rideId}/?token=$token';

    try {
      _channel?.sink.close();
    } catch (_) {}

    _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

    // Start heartbeat to keep connection alive
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      try {
        _channel?.sink.add(jsonEncode({"type": "heartbeat"}));
      } catch (_) {}
    });

    _channel!.stream.listen(
      (message) async {
        _wsReconnectAttempts = 0; // reset on successful message
        final data = jsonDecode(message);
        if (data['type'] == 'heartbeat_ack') return;
        if (data['type'] == 'location_update') {
          final newPos = LatLng(
            double.parse(data['latitude'].toString()),
            double.parse(data['longitude'].toString()),
          );
          // Calculate heading from consecutive positions
          if (_driverPosition != null) {
            final dLat = newPos.latitude - _driverPosition!.latitude;
            final dLng = newPos.longitude - _driverPosition!.longitude;
            if (dLat.abs() > 0.00001 || dLng.abs() > 0.00001) {
              _driverHeading = (math.atan2(dLng, dLat) * 180 / math.pi) % 360;
            }
          }
          // Use heading from server if provided
          if (data['heading'] != null) {
            _driverHeading = double.tryParse(data['heading'].toString()) ?? _driverHeading;
          }
          // Smooth interpolation: animate from current to new position
          _driverTargetPosition = newPos;
          _driverPosition ??= newPos;
          _moveController.forward(from: 0);
          // Recalculate ETA from driver to pickup
          _updateDriverEta(newPos);
          // Redraw driver-to-pickup route periodically
          _drawDriverToPickupRoute(newPos);
        } else if (data['type'] == 'status_update') {
          final wsStatus = data['status'];
          if (wsStatus == 'driver_requested' || wsStatus == 'driver_assigned') {
            // A driver has been assigned — show their info + countdown
            final assigned = data['assigned_driver'];
            final timeout = data['timeout_seconds'] ?? 15;
            if (mounted) {
              setState(() {
                _assignedDriver = assigned is Map<String, dynamic> ? assigned : null;
                _assignmentCountdown = timeout is int ? timeout : 15;
                _assignmentTotalTimeout = _assignmentCountdown;
              });
              _startAssignmentCountdown();
            }
          } else if (wsStatus == 'accepted') {
            // Driver accepted! Reload ride data
            _assignmentTimer?.cancel();
            setState(() => _assignedDriver = null);
            await _loadRide();
            // Start tracking driver location to pickup
            if (_driverPosition != null) {
              _updateDriverEta(_driverPosition!);
              _drawDriverToPickupRoute(_driverPosition!);
            }
          } else if (wsStatus == 'driver_arrived') {
            // Driver arrived at pickup — clear driver route + ETA
            if (mounted) {
              setState(() {
                _driverEtaMinutes = null;
                _driverDistanceKm = null;
                _polylines.removeWhere((p) =>
                    p.polylineId.value == 'driver_route_border' ||
                    p.polylineId.value == 'driver_route');
              });
              _showDriverArrivedNotification();
              _loadRide();
            }
          } else if (wsStatus == 'driver_arriving') {
            // Driver en route to pickup — reload ride data
            if (mounted) _loadRide();
          } else if (wsStatus == 'in_progress') {
            // Ride started — clear driver route if still present
            if (mounted) {
              setState(() {
                _polylines.removeWhere((p) =>
                    p.polylineId.value == 'driver_route_border' ||
                    p.polylineId.value == 'driver_route');
              });
              _loadRide();
            }
          } else if (wsStatus == 'completed') {
            // Ride completed — show feedback sheet
            if (mounted) {
              _loadRide().then((_) {
                if (mounted) _showRideCompletedSheet();
              });
            }
          } else if (wsStatus == 'no_driver') {
            // No drivers available — update ride data to reflect status
            _assignmentTimer?.cancel();
            if (mounted) {
              setState(() => _assignedDriver = null);
            }
            _loadRide();
          } else {
            _loadRide();
          }
        }
      },
      onError: (_) => _scheduleReconnect(),
      onDone: () => _scheduleReconnect(),
    );
  }

  void _scheduleReconnect() {
    if (_wsDisposed) return;
    _heartbeatTimer?.cancel();
    final status = _ride?['status'] ?? 'requested';
    // Don't reconnect if ride is in a terminal state
    if (status == 'completed' || status == 'cancelled_passenger' ||
        status == 'cancelled_driver' || status == 'no_driver') return;

    _wsReconnectAttempts++;
    // Exponential backoff: 1s, 2s, 4s, 8s, max 15s
    final delay = Duration(
      seconds: math.min(15, math.pow(2, _wsReconnectAttempts - 1).toInt()),
    );
    _wsReconnectTimer?.cancel();
    _wsReconnectTimer = Timer(delay, () {
      if (mounted && !_wsDisposed) _connectWebSocket();
    });
  }

  /// Start countdown for driver assignment timeout
  void _startAssignmentCountdown() {
    _assignmentTimer?.cancel();
    _assignmentTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      if (_assignmentCountdown <= 1) {
        timer.cancel();
        // Timeout — tell backend to reassign
        _triggerTimeout();
      } else {
        setState(() => _assignmentCountdown--);
      }
    });
  }

  Future<void> _triggerTimeout() async {
    try {
      await _api.dio.post(ApiConstants.timeoutRide(widget.rideId));
    } catch (_) {}
    // The backend will send a new WS event with next driver or no_driver
  }

  /// Spinner shown while waiting for first driver assignment
  Widget _buildSearchingSpinner() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _searchCarAnimation,
              builder: (context, child) {
                return Transform.rotate(
                  angle: _searchCarAnimation.value * 6.28,
                  child: Icon(Icons.local_taxi_rounded, size: 24.sp, color: AppColors.primary),
                );
              },
            ),
            SizedBox(width: 12.w),
            Text(
              'Recherche d\'un chauffeur...',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14.sp, color: AppColors.primaryDark),
            ),
          ],
        ),
        SizedBox(height: 10.h),
        ClipRRect(
          borderRadius: BorderRadius.circular(4.r),
          child: SizedBox(
            width: 200.w,
            height: 4.h,
            child: LinearProgressIndicator(
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
        ),
      ],
    );
  }

  /// Card shown when a specific driver is assigned and we're waiting for them to accept
  Widget _buildAssignedDriverCard() {
    final name = _assignedDriver?['name'] ?? 'Chauffeur';
    final vehicle = _assignedDriver?['vehicle'] ?? '';
    final plate = _assignedDriver?['license_plate'] ?? '';
    final vehicleColor = _assignedDriver?['vehicle_color'] ?? '';
    final rating = _assignedDriver?['rating'];
    final distKm = _assignedDriver?['distance_km'];
    final etaMin = _assignedDriver?['eta_minutes'];
    final photo = _assignedDriver?['photo'];
    final progress = _assignmentTotalTimeout > 0
        ? _assignmentCountdown / _assignmentTotalTimeout
        : 0.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 24.r,
              backgroundColor: AppColors.primary.withOpacity(0.15),
              backgroundImage: photo != null ? NetworkImage(photo) : null,
              child: photo == null
                  ? Icon(Icons.person, size: 26.sp, color: AppColors.primary)
                  : null,
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15.sp),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (vehicle.isNotEmpty)
                    Text(
                      '$vehicle${vehicleColor.isNotEmpty ? ' • $vehicleColor' : ''}',
                      style: GoogleFonts.poppins(fontSize: 12.sp, color: AppColors.textSecondary),
                    ),
                  if (plate.isNotEmpty)
                    Text(plate, style: GoogleFonts.poppins(
                      fontSize: 12.sp, fontWeight: FontWeight.w600, color: AppColors.primaryDark,
                    )),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (rating != null)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star_rounded, size: 14.sp, color: AppColors.primary),
                        SizedBox(width: 2.w),
                        Text('$rating', style: GoogleFonts.poppins(
                          fontSize: 12.sp, fontWeight: FontWeight.w600,
                        )),
                      ],
                    ),
                  ),
                SizedBox(height: 4.h),
                if (etaMin != null)
                  Text('~${etaMin.toStringAsFixed(0)} min',
                    style: GoogleFonts.poppins(
                      fontSize: 12.sp, fontWeight: FontWeight.w600,
                      color: AppColors.primaryDark,
                    ),
                  )
                else if (distKm != null)
                  Text('$distKm km', style: GoogleFonts.poppins(
                    fontSize: 11.sp, color: AppColors.textSecondary,
                  )),
              ],
            ),
          ],
        ),
        SizedBox(height: 10.h),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 18.w, height: 18.w,
              child: CircularProgressIndicator(
                value: progress.toDouble().clamp(0.0, 1.0),
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(
                  progress > 0.3 ? AppColors.primary : Colors.red,
                ),
                backgroundColor: AppColors.border,
              ),
            ),
            SizedBox(width: 8.w),
            Text(
              'En attente de confirmation... ${_assignmentCountdown}s',
              style: GoogleFonts.poppins(fontSize: 12.sp, color: AppColors.textSecondary),
            ),
          ],
        ),
        SizedBox(height: 6.h),
        ClipRRect(
          borderRadius: BorderRadius.circular(4.r),
          child: SizedBox(
            width: double.infinity,
            height: 4.h,
            child: LinearProgressIndicator(
              value: progress.toDouble().clamp(0.0, 1.0),
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation<Color>(
                progress > 0.3 ? AppColors.primary : Colors.red,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Draw route polyline between pickup and destination.
  Future<void> _drawRoute() async {
    if (_ride == null) return;
    final pickup = LatLng(
      double.parse(_ride!['pickup_latitude'].toString()),
      double.parse(_ride!['pickup_longitude'].toString()),
    );
    final dest = LatLng(
      double.parse(_ride!['destination_latitude'].toString()),
      double.parse(_ride!['destination_longitude'].toString()),
    );

    final points = await _placesService.getRoutePolyline(pickup, dest);
    if (!mounted || points.isEmpty) return;

    setState(() {
      _polylines.removeWhere((p) =>
          p.polylineId.value == 'route_border' ||
          p.polylineId.value == 'route');
      // Shadow border
      _polylines.add(Polyline(
        polylineId: const PolylineId('route_border'),
        points: points,
        color: Colors.black26,
        width: 9,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
        zIndex: 0,
      ));
      // Amber route
      _polylines.add(Polyline(
        polylineId: const PolylineId('route'),
        points: points,
        color: const Color(0xFFD97706),
        width: 6,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
        zIndex: 1,
      ));
    });
  }

  /// Draw the route from driver current position to the pickup point.
  DateTime _lastDriverRouteUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> _drawDriverToPickupRoute(LatLng driverPos) async {
    if (_ride == null) return;
    final status = _ride!['status'];
    if (status != 'accepted' && status != 'driver_arriving') return;

    // Throttle: only redraw every 10 seconds
    final now = DateTime.now();
    if (now.difference(_lastDriverRouteUpdate).inSeconds < 10) return;
    _lastDriverRouteUpdate = now;

    final pickup = LatLng(
      double.parse(_ride!['pickup_latitude'].toString()),
      double.parse(_ride!['pickup_longitude'].toString()),
    );

    final points = await _placesService.getRoutePolyline(driverPos, pickup);
    if (!mounted || points.isEmpty) return;

    setState(() {
      _polylines.removeWhere((p) =>
          p.polylineId.value == 'driver_route_border' ||
          p.polylineId.value == 'driver_route');
      // Amber dashed-style border
      _polylines.add(Polyline(
        polylineId: const PolylineId('driver_route_border'),
        points: points,
        color: const Color(0xFFD97706).withOpacity(0.25),
        width: 7,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
        zIndex: 2,
      ));
      // Amber route line
      _polylines.add(Polyline(
        polylineId: const PolylineId('driver_route'),
        points: points,
        color: const Color(0xFFD97706),
        width: 4,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
        zIndex: 3,
        patterns: [PatternItem.dash(20), PatternItem.gap(10)],
      ));
    });
  }

  /// Calculate ETA from driver position to pickup using Haversine distance.
  void _updateDriverEta(LatLng driverPos) {
    if (_ride == null) return;
    final status = _ride!['status'];
    if (status != 'accepted' && status != 'driver_arriving') {
      if (_driverEtaMinutes != null) {
        setState(() {
          _driverEtaMinutes = null;
          _driverDistanceKm = null;
        });
      }
      return;
    }

    final pickup = LatLng(
      double.parse(_ride!['pickup_latitude'].toString()),
      double.parse(_ride!['pickup_longitude'].toString()),
    );

    final distKm = _haversineDistance(driverPos, pickup);
    // Estimate: avg 20 km/h in city traffic
    final etaMin = (distKm / 20) * 60;

    setState(() {
      _driverDistanceKm = distKm;
      _driverEtaMinutes = etaMin < 1 ? 1 : etaMin;
    });
  }

  /// Haversine distance in kilometers.
  double _haversineDistance(LatLng a, LatLng b) {
    const R = 6371.0; // Earth radius in km
    final dLat = _degToRad(b.latitude - a.latitude);
    final dLng = _degToRad(b.longitude - a.longitude);
    final sinLat = math.sin(dLat / 2);
    final sinLng = math.sin(dLng / 2);
    final h = sinLat * sinLat +
        math.cos(_degToRad(a.latitude)) * math.cos(_degToRad(b.latitude)) * sinLng * sinLng;
    return 2 * R * math.asin(math.sqrt(h));
  }

  double _degToRad(double deg) => deg * math.pi / 180;

  /// Load nearby drivers and show them on the map.
  Future<void> _loadNearbyDrivers() async {
    if (_ride == null) return;
    try {
      final response = await _api.dio.get(
        ApiConstants.nearbyDrivers,
        queryParameters: {
          'latitude': _ride!['pickup_latitude'],
          'longitude': _ride!['pickup_longitude'],
          'radius': 15,
        },
      );
      final drivers = response.data as List;
      final driverMarkers = drivers.map((d) {
        final heading = double.tryParse(d['heading']?.toString() ?? '') ?? 0;
        return Marker(
          markerId: MarkerId('driver_${d['id']}'),
          position: LatLng(
            double.parse(d['latitude'].toString()),
            double.parse(d['longitude'].toString()),
          ),
          icon: _carIcon,
          rotation: heading,
          anchor: const Offset(0.5, 0.5),
          flat: true,
          infoWindow: InfoWindow(
            title: d['driver_name'],
            snippet: '${d['vehicle_make']} ${d['vehicle_model']} ⭐${d['rating']}',
          ),
        );
      }).toSet();

      if (!mounted) return;
      setState(() {
        _markers.removeWhere((m) => m.markerId.value.startsWith('driver_'));
        _markers.addAll(driverMarkers);
      });
    } catch (e) {
      debugPrint('Error loading nearby drivers: $e');
    }
  }

  /// Fit camera to show full route + some padding.
  Future<void> _fitCameraToRoute() async {
    if (_ride == null) return;
    final pickup = LatLng(
      double.parse(_ride!['pickup_latitude'].toString()),
      double.parse(_ride!['pickup_longitude'].toString()),
    );
    final dest = LatLng(
      double.parse(_ride!['destination_latitude'].toString()),
      double.parse(_ride!['destination_longitude'].toString()),
    );

    final lats = [pickup.latitude, dest.latitude];
    final lngs = [pickup.longitude, dest.longitude];
    if (_driverPosition != null) {
      lats.add(_driverPosition!.latitude);
      lngs.add(_driverPosition!.longitude);
    }

    final bounds = LatLngBounds(
      southwest: LatLng(
        lats.reduce((a, b) => a < b ? a : b) - 0.005,
        lngs.reduce((a, b) => a < b ? a : b) - 0.005,
      ),
      northeast: LatLng(
        lats.reduce((a, b) => a > b ? a : b) + 0.005,
        lngs.reduce((a, b) => a > b ? a : b) + 0.005,
      ),
    );

    final controller = await _mapController.future;
    controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
  }

  void _updateMarkers() {
    if (_ride == null) return;

    _markers.removeWhere(
      (m) => m.markerId.value == 'pickup' || m.markerId.value == 'destination',
    );

    // Pickup marker
    _markers.add(Marker(
      markerId: const MarkerId('pickup'),
      position: LatLng(
        double.parse(_ride!['pickup_latitude'].toString()),
        double.parse(_ride!['pickup_longitude'].toString()),
      ),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      infoWindow: InfoWindow(title: _ride!['pickup_address'] ?? 'Départ'),
    ));

    // Destination marker
    _markers.add(Marker(
      markerId: const MarkerId('destination'),
      position: LatLng(
        double.parse(_ride!['destination_latitude'].toString()),
        double.parse(_ride!['destination_longitude'].toString()),
      ),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      infoWindow: InfoWindow(title: _ride!['destination_address'] ?? 'Destination'),
    ));

    setState(() {});
  }

  /// Smoothly interpolates the driver position between old and target.
  void _interpolateDriverPosition() {
    if (_driverPosition == null || _driverTargetPosition == null) return;
    final t = Curves.easeInOut.transform(_moveController.value);
    final lat = _driverPosition!.latitude +
        (_driverTargetPosition!.latitude - _driverPosition!.latitude) * t;
    final lng = _driverPosition!.longitude +
        (_driverTargetPosition!.longitude - _driverPosition!.longitude) * t;

    // Update position for the marker at this interpolation step
    final interpolated = LatLng(lat, lng);
    _markers.removeWhere((m) => m.markerId.value == 'my_driver');
    _markers.add(Marker(
      markerId: const MarkerId('my_driver'),
      position: interpolated,
      icon: _carIcon,
      rotation: _driverHeading,
      anchor: const Offset(0.5, 0.5),
      flat: true,
      infoWindow: const InfoWindow(title: 'Votre chauffeur'),
    ));

    if (mounted) setState(() {});

    // When animation completes, snap to target
    if (_moveController.isCompleted) {
      _driverPosition = _driverTargetPosition;
    }
  }

  Future<void> _cancelRide() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Annuler la course'),
        content: const Text('Êtes-vous sûr de vouloir annuler cette course ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Non'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Oui, annuler'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _api.dio.post(
        ApiConstants.cancelRide(widget.rideId),
        data: {'reason': 'Annulé par le passager'},
      );
      if (mounted) context.go('/home');
    } catch (_) {}
  }

  Future<void> _triggerSOS() async {
    try {
      await _api.dio.post(
        ApiConstants.rideSos(widget.rideId),
        data: {
          'ride': widget.rideId,
          'latitude': _driverPosition?.latitude ?? 0,
          'longitude': _driverPosition?.longitude ?? 0,
          'message': 'Urgence!',
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Alerte SOS envoyée !'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (_) {}
  }

  String _getStatusText(String? status) {
    switch (status) {
      case 'requested':
        return 'Recherche d\'un chauffeur...';
      case 'accepted':
        return 'Chauffeur trouvé !';
      case 'driver_arriving':
        return 'Le chauffeur arrive...';
      case 'driver_arrived':
        return 'Votre chauffeur est arrivé !';
      case 'in_progress':
        return 'Course en cours';
      case 'completed':
        return 'Course terminée';
      case 'no_driver':
        return 'Aucun chauffeur disponible';
      case 'cancelled_passenger':
        return 'Course annulée';
      case 'cancelled_driver':
        return 'Course annulée par le chauffeur';
      default:
        return status ?? 'Chargement...';
    }
  }

  IconData _getStatusIcon(String? status) {
    switch (status) {
      case 'requested':
        return Icons.search_rounded;
      case 'accepted':
        return Icons.check_circle_rounded;
      case 'driver_arriving':
        return Icons.directions_car_rounded;
      case 'driver_arrived':
        return Icons.place_rounded;
      case 'in_progress':
        return Icons.route_rounded;
      case 'completed':
        return Icons.flag_rounded;
      case 'no_driver':
        return Icons.person_off_rounded;
      case 'cancelled_passenger':
      case 'cancelled_driver':
        return Icons.cancel_rounded;
      default:
        return Icons.hourglass_empty_rounded;
    }
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'requested':
        return AppColors.primary;
      case 'accepted':
        return AppColors.success;
      case 'driver_arriving':
        return AppColors.info;
      case 'driver_arrived':
        return AppColors.success;
      case 'in_progress':
        return AppColors.info;
      case 'completed':
        return AppColors.success;
      case 'no_driver':
        return const Color(0xFFEF6C00);
      case 'cancelled_passenger':
      case 'cancelled_driver':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  void dispose() {
    _wsDisposed = true;
    _channel?.sink.close();
    _heartbeatTimer?.cancel();
    _wsReconnectTimer?.cancel();
    _pulseController.dispose();
    _searchCarController.dispose();
    _moveController.dispose();
    _driverRefreshTimer?.cancel();
    _waitTimer?.cancel();
    _assignmentTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = _ride?['status'];
    final isCompleted = status == 'completed';
    final isSearching = status == 'requested';
    final isNoDriver = status == 'no_driver';
    final isCancellable = ['requested', 'accepted', 'driver_arriving', 'driver_arrived'].contains(status);

    return Scaffold(
      body: Stack(
        children: [
          // ── Google Map ──
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _ride != null
                  ? LatLng(
                      double.parse(_ride!['pickup_latitude'].toString()),
                      double.parse(_ride!['pickup_longitude'].toString()),
                    )
                  : const LatLng(-4.3250, 15.3222),
              zoom: 14,
            ),
            onMapCreated: (c) async {
              _mapController.complete(c);
              final style = await rootBundle.loadString('assets/map_style.json');
              c.setMapStyle(style);
              // Fit to route after map is created
              Future.delayed(const Duration(milliseconds: 500), _fitCameraToRoute);
            },
            markers: _markers,
            polylines: _polylines,
            trafficEnabled: true,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            padding: EdgeInsets.only(bottom: 280.h),
          ),

          // ── Top bar ──
          SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
              child: Row(
                children: [
                  _buildCircleButton(
                    icon: Icons.arrow_back_ios_new,
                    onTap: () => context.go('/home'),
                  ),
                  const Spacer(),
                  // SOS Button
                  if (status == 'in_progress')
                    _buildCircleButton(
                      icon: Icons.sos_rounded,
                      color: AppColors.error,
                      iconColor: Colors.white,
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Alerte SOS'),
                            content: const Text(
                              'Êtes-vous sûr de vouloir envoyer une alerte SOS ?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('Annuler'),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _triggerSOS();
                                },
                                child: const Text('Confirmer SOS'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),

          // ── Floating buttons (right side) ──
          Positioned(
            right: 16.w,
            top: MediaQuery.of(context).padding.top + 70.h,
            child: Column(
              children: [
                // Call driver
                if (_ride?['driver'] != null)
                  _buildCircleButton(
                    icon: Icons.phone_rounded,
                    onTap: () {
                      final phone = _ride?['driver']?['phone_number'];
                      if (phone != null) launchUrl(Uri(scheme: 'tel', path: phone));
                    },
                    size: 44,
                  ),
                if (_ride?['driver'] != null) SizedBox(height: 10.h),
                _buildCircleButton(
                  icon: Icons.my_location_rounded,
                  onTap: _fitCameraToRoute,
                  size: 44,
                ),
              ],
            ),
          ),

          // ── Searching animation overlay ──
          if (isSearching)
            Positioned(
              top: MediaQuery.of(context).padding.top + 70.h,
              left: 16.w,
              right: 16.w,
              child: Center(
                child: AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Container(
                      padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 14.h),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24.r),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.2 * _pulseAnimation.value),
                            blurRadius: 20 * _pulseAnimation.value,
                            spreadRadius: 2 * _pulseAnimation.value,
                          ),
                        ],
                      ),
                      child: _assignedDriver != null
                          ? _buildAssignedDriverCard()
                          : _buildSearchingSpinner(),
                    );
                  },
                ),
              ),
            ),

          // ── Driver en route banner (ETA) ──
          if ((status == 'accepted' || status == 'driver_arriving') && _ride?['driver'] != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 70.h,
              left: 16.w,
              right: 16.w,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16.r),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.15),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44.w,
                      height: 44.w,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      child: Icon(Icons.directions_car_rounded, color: AppColors.primary, size: 24.sp),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Chauffeur en route',
                            style: GoogleFonts.poppins(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          SizedBox(height: 2.h),
                          Text(
                            _ride!['driver']['full_name'] ?? '',
                            style: GoogleFonts.poppins(
                              fontSize: 12.sp,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_driverEtaMinutes != null) ...[                      
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '~${_driverEtaMinutes!.round()} min',
                            style: GoogleFonts.poppins(
                              fontSize: 16.sp,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                            ),
                          ),
                          if (_driverDistanceKm != null)
                            Text(
                              '${_driverDistanceKm!.toStringAsFixed(1)} km',
                              style: GoogleFonts.poppins(
                                fontSize: 11.sp,
                                color: AppColors.textHint,
                              ),
                            ),
                        ],
                      ),
                    ] else
                      SizedBox(
                        width: 20.w, height: 20.w,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      ),
                  ],
                ),
              ),
            ),

          // ── Driver arrived banner ──
          if (status == 'driver_arrived')
            Positioned(
              top: MediaQuery.of(context).padding.top + 70.h,
              left: 16.w,
              right: 16.w,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 14.h),
                decoration: BoxDecoration(
                  color: AppColors.success,
                  borderRadius: BorderRadius.circular(16.r),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.success.withOpacity(0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(Icons.directions_car_rounded, color: Colors.white, size: 24.sp),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Votre chauffeur est arrivé !',
                            style: GoogleFonts.poppins(
                              fontSize: 15.sp,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'Rejoignez le point de prise en charge',
                            style: GoogleFonts.poppins(
                              fontSize: 12.sp,
                              color: Colors.white.withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Bottom info panel ──
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 20.h),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.shadow.withOpacity(0.08),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: _isLoading
                  ? Padding(
                      padding: EdgeInsets.symmetric(vertical: 20.h),
                      child: const Center(child: CircularProgressIndicator()),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Handle bar
                        Container(
                          width: 36.w,
                          height: 3.5.h,
                          decoration: BoxDecoration(
                            color: AppColors.border,
                            borderRadius: BorderRadius.circular(2.r),
                          ),
                        ),
                        SizedBox(height: 10.h),

                        // Status chip
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
                          decoration: BoxDecoration(
                            color: _getStatusColor(status).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20.r),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _getStatusIcon(status),
                                size: 15.sp,
                                color: _getStatusColor(status),
                              ),
                              SizedBox(width: 6.w),
                              Text(
                                _getStatusText(status),
                                style: TextStyle(
                                  color: _getStatusColor(status),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.sp,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 10.h),

                        // Route summary (compact)
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
                          decoration: BoxDecoration(
                            color: AppColors.inputFill,
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                          child: Row(
                            children: [
                              Column(
                                children: [
                                  Icon(Icons.circle, color: AppColors.success, size: 8.sp),
                                  Container(width: 1.5, height: 16.h, color: AppColors.border),
                                  Icon(Icons.location_on, color: AppColors.error, size: 12.sp),
                                ],
                              ),
                              SizedBox(width: 8.w),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _ride?['pickup_address'] ?? '',
                                      style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w500),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    SizedBox(height: 10.h),
                                    Text(
                                      _ride?['destination_address'] ?? '',
                                      style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w500),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 8.h),

                        // Driver info (compact) + contact buttons
                        if (_ride?['driver'] != null) ...[
                          Container(
                            padding: EdgeInsets.all(10.w),
                            decoration: BoxDecoration(
                              color: AppColors.inputFill,
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                            child: Row(
                              children: [
                                // Driver avatar
                                Container(
                                  width: 42.w,
                                  height: 42.w,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(12.r),
                                  ),
                                  child: Icon(Icons.person_rounded, color: AppColors.primaryDark, size: 22.sp),
                                ),
                                SizedBox(width: 10.w),
                                // Name + vehicle + rating
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _ride!['driver']['full_name'] ?? '',
                                        style: GoogleFonts.poppins(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13.sp,
                                          color: AppColors.textPrimary,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (_ride!['driver_vehicle'] != null)
                                        Text(
                                          '${_ride!['driver_vehicle']['make']} ${_ride!['driver_vehicle']['model']} • ${_ride!['driver_vehicle']['license_plate']}',
                                          style: GoogleFonts.poppins(
                                            color: AppColors.textSecondary,
                                            fontSize: 10.sp,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      Row(
                                        children: [
                                          ...List.generate(5, (i) => Icon(
                                            Icons.star_rounded,
                                            size: 12.sp,
                                            color: i < ((num.tryParse(_ride!['driver']['rating']?.toString() ?? '') ?? 4).round())
                                                ? AppColors.primary
                                                : AppColors.border,
                                          )),
                                          SizedBox(width: 3.w),
                                          Text(
                                            '${_ride!['driver']['rating'] ?? '4.5'}',
                                            style: GoogleFonts.poppins(
                                              fontSize: 10.sp,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                // Call + WhatsApp buttons
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    GestureDetector(
                                      onTap: () async {
                                        final phone = _ride?['driver']?['phone_number'];
                                        if (phone == null) return;
                                        final waUri = Uri.parse('https://wa.me/${phone.replaceAll('+', '')}');
                                        await launchUrl(waUri, mode: LaunchMode.externalApplication);
                                      },
                                      child: Container(
                                        width: 36.w,
                                        height: 36.w,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF25D366).withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(10.r),
                                        ),
                                        child: Icon(Icons.chat_rounded, color: const Color(0xFF25D366), size: 18.sp),
                                      ),
                                    ),
                                    SizedBox(width: 6.w),
                                    GestureDetector(
                                      onTap: () async {
                                        final phone = _ride?['driver']?['phone_number'];
                                        if (phone == null) return;
                                        final uri = Uri(scheme: 'tel', path: phone);
                                        await launchUrl(uri);
                                      },
                                      child: Container(
                                        width: 36.w,
                                        height: 36.w,
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(colors: AppColors.ctaGradient),
                                          borderRadius: BorderRadius.circular(10.r),
                                        ),
                                        child: Icon(Icons.phone_rounded, color: Colors.white, size: 18.sp),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 8.h),
                        ],

                        // Price + distance + duration row (compact)
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(10.r),
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      '${_ride?['estimated_price'] ?? '0'} CDF',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14.sp,
                                        color: AppColors.primaryDark,
                                      ),
                                    ),
                                    Text(
                                      'Prix',
                                      style: TextStyle(color: AppColors.textSecondary, fontSize: 10.sp),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(width: 6.w),
                            Expanded(
                              child: Container(
                                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
                                decoration: BoxDecoration(
                                  color: AppColors.inputFill,
                                  borderRadius: BorderRadius.circular(10.r),
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      '${_ride?['distance_km'] ?? '-'} km',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14.sp,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    Text(
                                      'Distance',
                                      style: TextStyle(color: AppColors.textSecondary, fontSize: 10.sp),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(width: 6.w),
                            Expanded(
                              child: Container(
                                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
                                decoration: BoxDecoration(
                                  color: AppColors.inputFill,
                                  borderRadius: BorderRadius.circular(10.r),
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      '${_ride?['estimated_duration_minutes'] ?? '-'} min',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14.sp,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    Text(
                                      'Durée',
                                      style: TextStyle(color: AppColors.textSecondary, fontSize: 10.sp),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 10.h),

                        // No driver available — professional message
                        if (isNoDriver) ...[                          
                          Container(
                            padding: EdgeInsets.all(20.w),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF3E0),
                              borderRadius: BorderRadius.circular(16.r),
                              border: Border.all(color: const Color(0xFFEF6C00).withOpacity(0.2)),
                            ),
                            child: Column(
                              children: [
                                Container(
                                  width: 56.w,
                                  height: 56.w,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEF6C00).withOpacity(0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.person_search_rounded,
                                    color: const Color(0xFFEF6C00),
                                    size: 28.sp,
                                  ),
                                ),
                                SizedBox(height: 14.h),
                                Text(
                                  'Aucun chauffeur disponible',
                                  style: GoogleFonts.poppins(
                                    fontSize: 15.sp,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFFE65100),
                                  ),
                                ),
                                SizedBox(height: 6.h),
                                Text(
                                  'Tous nos chauffeurs sont actuellement occupés dans votre zone. Veuillez réessayer dans quelques instants.',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.poppins(
                                    fontSize: 12.sp,
                                    color: AppColors.textSecondary,
                                    height: 1.5,
                                  ),
                                ),
                                SizedBox(height: 18.h),
                                SizedBox(
                                  width: double.infinity,
                                  height: 48.h,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFEF6C00),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14.r),
                                      ),
                                      elevation: 0,
                                    ),
                                    icon: const Icon(Icons.refresh_rounded, size: 20),
                                    label: Text(
                                      'Réessayer',
                                      style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14.sp,
                                      ),
                                    ),
                                    onPressed: () => context.go('/home'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 12.h),
                        ],

                        // Actions
                        if (isCancellable)
                          SizedBox(
                            width: double.infinity,
                            height: 44.h,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.error,
                                side: BorderSide(color: AppColors.error.withOpacity(0.4)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12.r),
                                ),
                              ),
                              icon: const Icon(Icons.close_rounded, size: 18),
                              label: Text(
                                'Annuler la course',
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.sp),
                              ),
                              onPressed: _cancelRide,
                            ),
                          ),

                        if (isCompleted) ...[
                          // Payment info row
                          Container(
                            padding: EdgeInsets.all(14.w),
                            decoration: BoxDecoration(
                              color: AppColors.success.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(14.r),
                              border: Border.all(color: AppColors.success.withOpacity(0.2)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.check_circle_rounded, color: AppColors.success, size: 22.sp),
                                SizedBox(width: 10.w),
                                Text(
                                  'Course terminée',
                                  style: GoogleFonts.poppins(
                                    fontSize: 14.sp,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.success,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '${_ride?['final_fare'] ?? _ride?['estimated_price'] ?? '0'} CDF',
                                  style: GoogleFonts.poppins(
                                    fontSize: 16.sp,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primaryDark,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 12.h),
                          SizedBox(
                            width: double.infinity,
                            height: 56.h,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: AppColors.ctaGradient,
                                ),
                                borderRadius: BorderRadius.circular(18.r),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primaryDark.withOpacity(0.3),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(18.r),
                                  onTap: () => context.push('/ride/${widget.rideId}/rate'),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.star_rounded, color: Colors.white, size: 22.sp),
                                      SizedBox(width: 8.w),
                                      Text(
                                        'Noter le chauffeur',
                                        style: GoogleFonts.poppins(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16.sp,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required VoidCallback onTap,
    Color color = Colors.white,
    Color iconColor = AppColors.textPrimary,
    double size = 44,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size.w,
        height: size.w,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Icon(icon, size: 20.sp, color: iconColor),
      ),
    );
  }
}
