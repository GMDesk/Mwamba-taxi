import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/route_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/vehicle_asset_marker.dart';
import '../../../../core/utils/vehicle_animator.dart';
import '../../../../core/widgets/app_alert.dart';

// ─── Design tokens ───────────────────────────────────────────────────────────
const Color _kGoogleBlue = Color(0xFF4285F4);
const Color _kGoogleBlueBorder = Color(0xFF1A73E8);
const Color _kDarkBg = Color(0xFF0B0F19);
const Color _kCardBg = Colors.white;
const Color _kSecondaryBg = Color(0xFFF3F4F6);
const Color _kTextDark = Color(0xFF111827);
const Color _kTextMuted = Color(0xFF6B7280);
const double _kCardRadius = 16;

class ActiveRideScreen extends StatefulWidget {
  final String rideId;
  const ActiveRideScreen({super.key, required this.rideId});

  @override
  State<ActiveRideScreen> createState() => _ActiveRideScreenState();
}

class _ActiveRideScreenState extends State<ActiveRideScreen>
    with SingleTickerProviderStateMixin {
  // ── services ───────────────────────────────────────────────────────────────
  final ApiClient _api = getIt<ApiClient>();
  final RouteService _routeService = RouteService();

  // ── map ────────────────────────────────────────────────────────────────────
  GoogleMapController? _mapController;
  String? _mapStyle;
  BitmapDescriptor? _carIcon;
  double _heading = 0;

  // ── state ──────────────────────────────────────────────────────────────────
  Map<String, dynamic>? _rideData;
  LatLng? _pickupLatLng;
  LatLng? _dropoffLatLng;
  LatLng _currentPosition = const LatLng(-4.3250, 15.3222);
  bool _loading = true;
  String _status = 'accepted';

  // ── route ──────────────────────────────────────────────────────────────────
  List<LatLng> _routePoints = [];
  String _etaText = '';
  String _distanceText = '';

  // ── navigation steps ───────────────────────────────────────────────────────
  List<NavigationStep> _navSteps = [];
  int _currentStepIndex = 0;
  String _nextInstruction = '';
  String _nextStepDistance = '';
  String _nextManeuver = '';

  // ── driving mode ───────────────────────────────────────────────────────────
  bool _drivingMode = false;

  // ── zoom tracking ──────────────────────────────────────────────────────────
  double _currentZoom = 14;
  int _lastZoomBucket = 14;
  final Map<int, BitmapDescriptor> _carIconCache = {};
  Timer? _zoomDebounce;

  // ── route refresh & deviation ─────────────────────────────────────────────
  Timer? _routeRefreshTimer;
  DateTime _lastRouteRefresh = DateTime.fromMillisecondsSinceEpoch(0);
  static const double _deviationThreshold = 80; // metres before auto-reroute
  bool _hasTriggeredArriving = false;

  // ── connections ────────────────────────────────────────────────────────────
  WebSocketChannel? _ws;
  StreamSubscription<Position>? _positionSub;
  int _wsReconnectAttempts = 0;
  Timer? _wsReconnectTimer;
  Timer? _heartbeatTimer;
  bool _disposed = false;

  // ── animation ──────────────────────────────────────────────────────────────
  late AnimationController _panelController;
  late Animation<Offset> _panelSlide;

  // ── premium vehicle animator ──────────────────────────────────────────────
  VehicleAnimator? _vehicleAnimator;

  // ─────────────────────────────────────────────── Lifecycle ──────────────────
  @override
  void initState() {
    super.initState();
    _panelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _panelSlide = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _panelController, curve: Curves.easeOut));

    _loadMapStyle();
    _initCarIcon();
    _vehicleAnimator = VehicleAnimator(
      vsync: this,
      onFrame: _onVehicleFrame,
    );
    _initCurrentPosition(); // get real GPS first
    _loadRide();
    _startTracking();
    _connectWebSocket();

    // Refresh route every 30 seconds while en route
    _routeRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_status == 'accepted' || _status == 'driver_arriving' || _status == 'in_progress') {
        _fetchRoute();
      }
    });
  }

  Future<void> _loadMapStyle() async {
    _mapStyle = await rootBundle.loadString('assets/map_style_light.json');
    _mapController?.setMapStyle(_mapStyle!);
  }

  /// Get the real GPS position immediately so the car marker starts at the
  /// correct location instead of the hardcoded default.
  Future<void> _initCurrentPosition() async {
    try {
      // Try last known first (instant, no GPS warm-up)
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && mounted) {
        setState(() => _currentPosition = LatLng(last.latitude, last.longitude));
      }
      // Then get a fresh fix
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (mounted) {
        final newPos = LatLng(pos.latitude, pos.longitude);
        _currentPosition = newPos;
        _heading = pos.heading;
        _vehicleAnimator?.pushPosition(newPos, bearing: pos.heading);
        _fetchRoute();
      }
    } catch (_) {
      // Stream will take over when it fires
    }
  }

  Future<void> _initCarIcon() async {
    _carIcon = await getVehicleMarker(
      heading: _heading,
      zoom: _currentZoom,
      state: _vehicleStateFromStatus(),
      isDriverSelf: true,
    );
    if (mounted) setState(() {});
  }

  /// Map ride status → VehicleState for colour coding.
  VehicleState _vehicleStateFromStatus() {
    switch (_status) {
      case 'accepted':
      case 'driver_arriving':
        return VehicleState.enRoute;
      case 'driver_arrived':
        return VehicleState.arrived;
      case 'in_progress':
        return VehicleState.inProgress;
      default:
        return VehicleState.available;
    }
  }

  /// Called on every animation tick by the VehicleAnimator.
  void _onVehicleFrame(LatLng position, double bearing) async {
    _currentPosition = position;
    _heading = bearing;
    _carIcon = await getVehicleMarker(
      heading: bearing,
      zoom: _currentZoom,
      state: _vehicleStateFromStatus(),
      isDriverSelf: true,
    );
    if (mounted) setState(() {});
  }

  // ─────────────────────────────────────────────── Data ──────────────────────
  Future<void> _loadRide() async {
    try {
      final resp = await _api.dio.get(ApiConstants.rideDetail(widget.rideId));
      final data = resp.data;
      setState(() {
        _rideData = data;
        _status = data['status'];
        _pickupLatLng = LatLng(
          double.parse(data['pickup_latitude'].toString()),
          double.parse(data['pickup_longitude'].toString()),
        );
        _dropoffLatLng = LatLng(
          double.parse(data['destination_latitude'].toString()),
          double.parse(data['destination_longitude'].toString()),
        );
        _loading = false;
      });

      _panelController.forward();
      _fetchRoute();
      _fitBounds();
    } on DioException catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        AppAlert.showDioError(context, e,
          fallback: 'Impossible de charger les détails de la course.',
          title: 'Chargement échoué',
        );
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _fetchRoute() async {
    final origin = _currentPosition;
    final destination = _status == 'in_progress'
        ? _dropoffLatLng
        : (_status == 'accepted' || _status == 'driver_arriving'
            ? _pickupLatLng
            : _dropoffLatLng);
    if (destination == null) return;

    final result = await _routeService.getRoute(origin, destination);
    if (result != null && mounted) {
      setState(() {
        _routePoints = result.points;
        _etaText = result.durationText;
        _distanceText = result.distanceText;
        _navSteps = result.steps;
        _updateCurrentStep();
      });

      // Auto-trigger driver_arriving when first route is loaded
      if (_status == 'accepted' && !_hasTriggeredArriving) {
        _hasTriggeredArriving = true;
        _markDriverArriving();
      }
    }
  }

  /// Haversine distance in metres between two LatLng points.
  static double _haversine(LatLng a, LatLng b) {
    const R = 6371000.0; // Earth radius in metres
    final dLat = _toRad(b.latitude - a.latitude);
    final dLng = _toRad(b.longitude - a.longitude);
    final sinLat = math.sin(dLat / 2);
    final sinLng = math.sin(dLng / 2);
    final h = sinLat * sinLat +
        math.cos(_toRad(a.latitude)) * math.cos(_toRad(b.latitude)) * sinLng * sinLng;
    return 2 * R * math.asin(math.sqrt(h));
  }

  static double _toRad(double deg) => deg * math.pi / 180;

  /// Minimum distance (metres) from a point to any segment of a polyline.
  static double _minDistanceToPolyline(LatLng point, List<LatLng> polyline) {
    double minDist = double.infinity;
    for (int i = 0; i < polyline.length - 1; i++) {
      final d = _distToSegment(point, polyline[i], polyline[i + 1]);
      if (d < minDist) minDist = d;
      if (minDist < 10) break; // close enough, skip rest
    }
    return minDist;
  }

  /// Distance from point P to segment AB (approximate, works well for short segments).
  static double _distToSegment(LatLng p, LatLng a, LatLng b) {
    final dAB = _haversine(a, b);
    if (dAB < 1) return _haversine(p, a);
    // Project P onto AB using dot product ratio
    final t = (((p.latitude - a.latitude) * (b.latitude - a.latitude) +
                (p.longitude - a.longitude) * (b.longitude - a.longitude)) /
            ((b.latitude - a.latitude) * (b.latitude - a.latitude) +
                (b.longitude - a.longitude) * (b.longitude - a.longitude)))
        .clamp(0.0, 1.0);
    final projLat = a.latitude + t * (b.latitude - a.latitude);
    final projLng = a.longitude + t * (b.longitude - a.longitude);
    return _haversine(p, LatLng(projLat, projLng));
  }

  /// Advance step index when driver is within 40 m of the next step's start.
  void _updateCurrentStep() {
    if (_navSteps.isEmpty) return;
    // Skip past steps we've already passed
    while (_currentStepIndex < _navSteps.length - 1) {
      final nextStart = _navSteps[_currentStepIndex + 1].startLocation;
      if (_haversine(_currentPosition, nextStart) < 40) {
        _currentStepIndex++;
      } else {
        break;
      }
    }
    final step = _navSteps[_currentStepIndex];
    _nextInstruction = step.instruction;
    _nextStepDistance = step.distanceText;
    _nextManeuver = step.maneuver;
  }

  void _fitBounds() {
    if (_pickupLatLng == null || _dropoffLatLng == null) return;
    final sw = LatLng(
      _pickupLatLng!.latitude < _dropoffLatLng!.latitude
          ? _pickupLatLng!.latitude
          : _dropoffLatLng!.latitude,
      _pickupLatLng!.longitude < _dropoffLatLng!.longitude
          ? _pickupLatLng!.longitude
          : _dropoffLatLng!.longitude,
    );
    final ne = LatLng(
      _pickupLatLng!.latitude > _dropoffLatLng!.latitude
          ? _pickupLatLng!.latitude
          : _dropoffLatLng!.latitude,
      _pickupLatLng!.longitude > _dropoffLatLng!.longitude
          ? _pickupLatLng!.longitude
          : _dropoffLatLng!.longitude,
    );
    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(LatLngBounds(southwest: sw, northeast: ne), 80),
    );
  }

  // ─────────────────────────────────────────────── Tracking ──────────────────
  void _startTracking() {
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((pos) async {
      final newPos = LatLng(pos.latitude, pos.longitude);

      // Feed into the premium animator (handles smoothing + interpolation)
      _vehicleAnimator?.pushPosition(newPos, bearing: pos.heading);

      // Update navigation step tracking
      if (_navSteps.isNotEmpty && mounted) {
        setState(() => _updateCurrentStep());
      }

      // Route deviation detection — auto-reroute when off-track
      if (_routePoints.isNotEmpty) {
        final distFromRoute = _minDistanceToPolyline(newPos, _routePoints);
        if (distFromRoute > _deviationThreshold) {
          final now = DateTime.now();
          // Throttle: at most one reroute every 10 seconds
          if (now.difference(_lastRouteRefresh).inSeconds > 10) {
            _lastRouteRefresh = now;
            _fetchRoute();
          }
        }
      }

      // Follow driver in driving mode
      if (_drivingMode) {
        _mapController?.animateCamera(CameraUpdate.newCameraPosition(
          CameraPosition(
            target: newPos,
            zoom: 17,
            tilt: 55,
            bearing: pos.heading,
          ),
        ));
      }

      // Broadcast location via WebSocket (real-time to passenger)
      try {
        _ws?.sink.add(jsonEncode({
          'type': 'location_update',
          'latitude': pos.latitude,
          'longitude': pos.longitude,
          'heading': pos.heading,
          'speed': pos.speed,
        }));
      } catch (_) {}

      // Also report to REST API for GPS breadcrumb storage
      _api.dio.post(ApiConstants.rideLocation(widget.rideId), data: {
        'latitude': pos.latitude,
        'longitude': pos.longitude,
      }).ignore();
    });
  }

  // ─────────────────────────────────────────────── WebSocket ─────────────────
  void _connectWebSocket() async {
    if (_disposed) return;
    final token = await _api.getAccessToken();
    if (token == null) return;

    try { _ws?.sink.close(); } catch (_) {}

    _ws = WebSocketChannel.connect(
      Uri.parse('${ApiConstants.wsBaseUrl}/ride/${widget.rideId}/?token=$token'),
    );

    // Heartbeat to keep connection alive
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_disposed) { _heartbeatTimer?.cancel(); return; }
      try {
        _ws?.sink.add(jsonEncode({'type': 'heartbeat'}));
      } catch (_) {}
    });

    _ws!.stream.listen(
      (data) {
        _wsReconnectAttempts = 0;
        final msg = jsonDecode(data);
        if (msg['type'] == 'heartbeat_ack') return;
        if (msg['type'] == 'status_update') {
          final newStatus = msg['status'] ?? _status;
          if (mounted) {
            setState(() => _status = newStatus);
            if (newStatus == 'cancelled_by_passenger' || newStatus == 'cancelled') {
              _positionSub?.cancel();
              _showCancelledDialog();
            } else if (newStatus == 'completed') {
              _positionSub?.cancel();
            } else {
              _fetchRoute();
            }
          }
        }
      },
      onError: (_) => _scheduleReconnect(),
      onDone: () => _scheduleReconnect(),
    );
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _heartbeatTimer?.cancel();
    if (_status == 'completed' || _status == 'cancelled' ||
        _status == 'cancelled_by_passenger' || _status == 'cancelled_by_driver') return;

    _wsReconnectAttempts++;
    final delaySec = [1, 2, 4, 8, 15][_wsReconnectAttempts.clamp(0, 4)];
    _wsReconnectTimer?.cancel();
    _wsReconnectTimer = Timer(Duration(seconds: delaySec), () {
      if (mounted && !_disposed) _connectWebSocket();
    });
  }

  // ─────────────────────────────────────────────── Actions ───────────────────
  Future<void> _markDriverArriving() async {
    try {
      await _api.dio.post(ApiConstants.driverArriving(widget.rideId));
      if (mounted) setState(() => _status = 'driver_arriving');
    } catch (_) {
      // Non-critical — the ride still functions in 'accepted' status
    }
  }

  Future<void> _arrivedAtPickup() async {
    try {
      await _api.dio.post(ApiConstants.arrivedAtPickup(widget.rideId));
      setState(() {
        _status = 'driver_arrived';
        _currentStepIndex = 0;
        _navSteps = [];
        _nextInstruction = '';
        _nextStepDistance = '';
        _nextManeuver = '';
      });
      _fetchRoute(); // redraw route — now points to destination
    } on DioException catch (e) {
      if (mounted) {
        AppAlert.showDioError(context, e,
          fallback: 'Impossible de notifier votre arrivée.');
      }
    } catch (_) {}
  }

  Future<void> _startRide() async {
    try {
      await _api.dio.post(ApiConstants.startRide(widget.rideId));
      setState(() {
        _status = 'in_progress';
        _drivingMode = true;
        _currentStepIndex = 0;
        _navSteps = [];
        _nextInstruction = '';
        _nextStepDistance = '';
        _nextManeuver = '';
      });
      _fetchRoute();
    } on DioException catch (e) {
      if (mounted) {
        AppAlert.showDioError(context, e,
          fallback: 'Impossible de démarrer la course.',
          title: 'Démarrage échoué');
      }
    } catch (e) {
      if (mounted) {
        AppAlert.showError(context, e,
          fallback: 'Impossible de démarrer la course.');
      }
    }
  }

  Future<void> _completeRide() async {
    try {
      await _api.dio.post(ApiConstants.completeRide(widget.rideId));
      _positionSub?.cancel();
      setState(() => _status = 'completed');
      if (mounted) {
        _showCompletedSheet();
      }
    } on DioException catch (e) {
      if (mounted) {
        AppAlert.showDioError(context, e,
          fallback: 'Impossible de terminer la course.',
          title: 'Erreur de finalisation');
      }
    } catch (e) {
      if (mounted) {
        AppAlert.showError(context, e,
          fallback: 'Impossible de terminer la course.');
      }
    }
  }

  Future<void> _cancelRide() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_kCardRadius),
        ),
        title: const Text('Annuler la course ?'),
        content: const Text('Êtes-vous sûr de vouloir annuler cette course ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Non'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Oui', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _api.dio.post(ApiConstants.cancelRide(widget.rideId));
      if (mounted) context.go('/home');
    } on DioException catch (e) {
      if (mounted) {
        AppAlert.showDioError(context, e,
          fallback: 'Impossible d\'annuler la course.',
          title: 'Annulation échouée');
      }
    } catch (_) {}
  }

  void _callPassenger() {
    final phone = _rideData?['passenger']?['phone'];
    if (phone != null) {
      launchUrl(Uri.parse('tel:$phone'));
    }
  }

  /// Open external Google Maps navigation to current target.
  Future<void> _openExternalNav() async {
    final destination = _status == 'in_progress'
        ? _dropoffLatLng
        : (_status == 'accepted' || _status == 'driver_arriving'
            ? _pickupLatLng
            : _dropoffLatLng);
    if (destination == null) return;
    final url = Uri.parse(
      'google.navigation:q=${destination.latitude},${destination.longitude}&mode=d',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      // Fallback to web Google Maps
      final webUrl = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=${destination.latitude},${destination.longitude}&travelmode=driving',
      );
      await launchUrl(webUrl, mode: LaunchMode.externalApplication);
    }
  }

  void _showCancelledDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_kCardRadius),
        ),
        title: const Text('Course annulée'),
        content: const Text('Le passager a annulé cette course.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.go('/home');
            },
            child: Text('OK', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  void _recenterMap() {
    if (_drivingMode) {
      _mapController?.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _currentPosition,
          zoom: 17,
          tilt: 55,
          bearing: _heading,
        ),
      ));
    } else {
      _fitBounds();
    }
  }

  void _toggleDrivingMode() {
    setState(() => _drivingMode = !_drivingMode);
    if (_drivingMode) {
      _mapController?.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _currentPosition,
          zoom: 17,
          tilt: 55,
          bearing: _heading,
        ),
      ));
    } else {
      _fitBounds();
    }
  }

  void _showCompletedSheet() {
    final price = _rideData?['final_fare'] ?? _rideData?['estimated_price'] ?? '—';
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: EdgeInsets.all(24.w),
        decoration: BoxDecoration(
          color: _kCardBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(_kCardRadius.r)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_rounded, color: AppColors.success, size: 56.sp),
              SizedBox(height: 12.h),
              Text('Course terminée !',
                style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w700, color: _kTextDark)),
              SizedBox(height: 6.h),
              Text('$price CDF',
                style: TextStyle(fontSize: 28.sp, fontWeight: FontWeight.w800, color: AppColors.primary)),
              SizedBox(height: 24.h),
              SizedBox(
                width: double.infinity,
                height: 52.h,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    context.go('/home');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(_kCardRadius.r),
                    ),
                  ),
                  child: Text('Retour à l\'accueil',
                    style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _positionSub?.cancel();
    _vehicleAnimator?.dispose();
    _ws?.sink.close();
    _heartbeatTimer?.cancel();
    _wsReconnectTimer?.cancel();
    _zoomDebounce?.cancel();
    _routeRefreshTimer?.cancel();
    _mapController?.dispose();
    _panelController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════ BUILD ═════════════════════
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: _kDarkBg,
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: _kDarkBg,
        body: Stack(
          children: [
            // ── Map ──
            _buildMap(),

            // ── Navigation instruction bar (turn-by-turn) ──
            if (_nextInstruction.isNotEmpty &&
                (_status == 'accepted' || _status == 'driver_arriving' || _status == 'in_progress'))
              _buildNavInstructionBar(),

            // ── Top Info Card (only when no nav instruction or not driving) ──
            if (!_drivingMode && _nextInstruction.isEmpty) _buildTopInfoCard(),

            // ── Driving mode ETA strip ──
            if (_drivingMode && _nextInstruction.isEmpty) _buildDrivingEtaStrip(),

            // ── Right floating buttons ──
            _buildFloatingButtons(),

            // ── Bottom panel ──
            _buildBottomPanel(),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────── Map ───────────────────────
  Widget _buildMap() {
    final markers = <Marker>{};

    // Driver car marker
    if (_carIcon != null) {
      markers.add(Marker(
        markerId: const MarkerId('driver'),
        position: _currentPosition,
        icon: _carIcon!,
        anchor: const Offset(0.5, 0.5),
        flat: true,
        zIndex: 3,
      ));
    }

    // Pickup / Passenger marker
    if (_pickupLatLng != null) {
      markers.add(Marker(
        markerId: const MarkerId('pickup'),
        position: _pickupLatLng!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(title: _rideData?['passenger']?['full_name'] ?? 'Client'),
        zIndex: 2,
      ));
    }

    // Destination marker
    if (_dropoffLatLng != null) {
      markers.add(Marker(
        markerId: const MarkerId('dropoff'),
        position: _dropoffLatLng!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        zIndex: 2,
      ));
    }

    // Route polylines
    final polylines = <Polyline>{};
    if (_routePoints.isNotEmpty) {
      final pw = polylineWidthForZoom(_currentZoom);
      // Border polyline
      polylines.add(Polyline(
        polylineId: const PolylineId('route_border'),
        points: _routePoints,
        color: _kGoogleBlueBorder,
        width: pw + 2,
        zIndex: 0,
      ));
      // Main route
      polylines.add(Polyline(
        polylineId: const PolylineId('route_main'),
        points: _routePoints,
        color: _kGoogleBlue,
        width: pw,
        zIndex: 1,
      ));
    }

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: _pickupLatLng ?? _currentPosition,
        zoom: 14,
      ),
      onMapCreated: (c) {
        _mapController = c;
        if (_mapStyle != null) c.setMapStyle(_mapStyle!);
        _fitBounds();
      },
      onCameraMove: (pos) {
        _currentZoom = pos.zoom;
        final bucket = pos.zoom.round();
        if (bucket != _lastZoomBucket) {
          _lastZoomBucket = bucket;
          _zoomDebounce?.cancel();
          _zoomDebounce = Timer(const Duration(milliseconds: 200), () async {
            if (_carIconCache.containsKey(bucket)) {
              _carIcon = _carIconCache[bucket];
            } else {
              final icon = await getVehicleMarker(
                heading: _heading,
                zoom: _currentZoom,
                state: _vehicleStateFromStatus(),
                isDriverSelf: true,
              );
              _carIconCache[bucket] = icon;
              _carIcon = icon;
            }
            if (mounted) setState(() {});
          });
        }
      },
      markers: markers,
      polylines: polylines,
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: false,
      padding: EdgeInsets.only(bottom: 200.h, top: 100.h),
    );
  }

  // ─────────────────────────────────────────────── Top Info Card ─────────────
  Widget _buildTopInfoCard() {
    final destination = _rideData?['destination_address'] ?? 'Destination';
    return Positioned(
      top: MediaQuery.of(context).padding.top + 12.h,
      left: 16.w,
      right: 72.w, // leave space for floating buttons
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        decoration: BoxDecoration(
          color: _kCardBg,
          borderRadius: BorderRadius.circular(_kCardRadius.r),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 8.w,
                  height: 8.w,
                  decoration: BoxDecoration(
                    color: _status == 'in_progress' ? AppColors.error : AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: 8.w),
                Expanded(
                  child: Text(
                    _status == 'in_progress' ? destination : (_rideData?['pickup_address'] ?? 'Prise en charge'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                      color: _kTextDark,
                    ),
                  ),
                ),
              ],
            ),
            if (_etaText.isNotEmpty) ...[
              SizedBox(height: 8.h),
              Row(
                children: [
                  _InfoChip(icon: Icons.access_time_rounded, label: _etaText),
                  SizedBox(width: 12.w),
                  _InfoChip(icon: Icons.straighten_rounded, label: _distanceText),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────── Driving ETA Strip ─────────
  Widget _buildDrivingEtaStrip() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8.h,
      left: 16.w,
      right: 72.w,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(12.r),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 8),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.navigation_rounded, color: Colors.white, size: 20.sp),
            SizedBox(width: 8.w),
            Text(
              _etaText.isEmpty ? '—' : _etaText,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(width: 12.w),
            Container(width: 1, height: 18.h, color: Colors.white38),
            SizedBox(width: 12.w),
            Text(
              _distanceText.isEmpty ? '—' : _distanceText,
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────── Nav Instruction Bar ────────
  Widget _buildNavInstructionBar() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8.h,
      left: 16.w,
      right: 72.w,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
        decoration: BoxDecoration(
          color: const Color(0xFF1A73E8),
          borderRadius: BorderRadius.circular(14.r),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1A73E8).withOpacity(0.35),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Maneuver icon + instruction
            Row(
              children: [
                Container(
                  width: 42.w,
                  height: 42.w,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Icon(
                    _maneuverIcon(_nextManeuver),
                    color: Colors.white,
                    size: 24.sp,
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_nextStepDistance.isNotEmpty)
                        Text(
                          _nextStepDistance,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20.sp,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      Text(
                        _nextInstruction,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // ETA bar
            if (_etaText.isNotEmpty) ...[
              SizedBox(height: 8.h),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.access_time_rounded, color: Colors.white70, size: 14.sp),
                    SizedBox(width: 6.w),
                    Text(
                      _etaText,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Container(width: 1, height: 12.h, color: Colors.white30),
                    SizedBox(width: 12.w),
                    Icon(Icons.straighten_rounded, color: Colors.white70, size: 14.sp),
                    SizedBox(width: 6.w),
                    Text(
                      _distanceText,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Map Google Directions maneuver string → icon.
  IconData _maneuverIcon(String maneuver) {
    switch (maneuver) {
      case 'turn-left':
      case 'fork-left':
      case 'ramp-left':
        return Icons.turn_left_rounded;
      case 'turn-right':
      case 'fork-right':
      case 'ramp-right':
        return Icons.turn_right_rounded;
      case 'turn-slight-left':
        return Icons.turn_slight_left_rounded;
      case 'turn-slight-right':
        return Icons.turn_slight_right_rounded;
      case 'turn-sharp-left':
        return Icons.turn_sharp_left_rounded;
      case 'turn-sharp-right':
        return Icons.turn_sharp_right_rounded;
      case 'uturn-left':
        return Icons.u_turn_left_rounded;
      case 'uturn-right':
        return Icons.u_turn_right_rounded;
      case 'roundabout-left':
      case 'roundabout-right':
        return Icons.roundabout_left_rounded;
      case 'merge':
        return Icons.merge_rounded;
      case 'straight':
        return Icons.straight_rounded;
      default:
        return Icons.navigation_rounded;
    }
  }

  // ─────────────────────────────────────────────── Floating Buttons ──────────
  Widget _buildFloatingButtons() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 12.h,
      right: 12.w,
      child: Column(
        children: [
          // Call
          _FloatingBtn(
            icon: Icons.phone_rounded,
            onTap: _callPassenger,
            tooltip: 'Appeler',
          ),
          SizedBox(height: 10.h),
          // External navigation (Google Maps)
          _FloatingBtn(
            icon: Icons.map_rounded,
            onTap: _openExternalNav,
            tooltip: 'Google Maps',
          ),
          SizedBox(height: 10.h),
          // Driving mode toggle
          _FloatingBtn(
            icon: _drivingMode ? Icons.zoom_out_map_rounded : Icons.navigation_rounded,
            onTap: _toggleDrivingMode,
            tooltip: 'Mode conduite',
            highlighted: _drivingMode,
          ),
          SizedBox(height: 10.h),
          // Recenter
          _FloatingBtn(
            icon: Icons.my_location_rounded,
            onTap: _recenterMap,
            tooltip: 'Recentrer',
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────── Bottom Panel ──────────────
  Widget _buildBottomPanel() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: _panelSlide,
        child: Container(
          decoration: BoxDecoration(
            color: _kCardBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(_kCardRadius.r)),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 16, offset: const Offset(0, -4)),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 8.h),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag indicator
                  Container(
                    width: 36.w,
                    height: 4.h,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2.r),
                    ),
                  ),
                  SizedBox(height: 12.h),

                  // Passenger row (compact in driving mode)
                  if (_rideData != null) _buildPassengerRow(),

                  // Addresses (hidden in driving mode)
                  if (!_drivingMode && _rideData != null) ...[
                    SizedBox(height: 12.h),
                    _buildAddresses(),
                  ],

                  SizedBox(height: 16.h),

                  // Action button
                  _buildActionButton(),

                  // Cancel link
                  if (_status != 'completed' &&
                      _status != 'cancelled' &&
                      !_drivingMode)
                    Padding(
                      padding: EdgeInsets.only(top: 4.h),
                      child: TextButton(
                        onPressed: _cancelRide,
                        child: Text('Annuler',
                          style: TextStyle(color: AppColors.error, fontSize: 13.sp)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPassengerRow() {
    final name = _rideData!['passenger']?['full_name'] ?? 'Passager';
    final price = _rideData!['estimated_price'] ?? '—';

    return Row(
      children: [
        CircleAvatar(
          radius: _drivingMode ? 18.r : 22.r,
          backgroundColor: AppColors.primary.withOpacity(0.12),
          child: Icon(Icons.person_rounded, color: AppColors.primary, size: _drivingMode ? 20.sp : 24.sp),
        ),
        SizedBox(width: 10.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                style: TextStyle(
                  fontSize: _drivingMode ? 15.sp : 16.sp,
                  fontWeight: FontWeight.w600,
                  color: _kTextDark,
                ),
              ),
              if (!_drivingMode)
                Text(_statusLabel(),
                  style: TextStyle(fontSize: 12.sp, color: _kTextMuted)),
            ],
          ),
        ),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8.r),
          ),
          child: Text('$price CDF',
            style: TextStyle(
              fontSize: _drivingMode ? 15.sp : 16.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAddresses() {
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: _kSecondaryBg,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Column(
        children: [
          _AddressRow(
            dotColor: AppColors.primary,
            text: _rideData!['pickup_address'] ?? 'Prise en charge',
          ),
          Padding(
            padding: EdgeInsets.only(left: 4.w),
            child: Column(
              children: List.generate(3, (_) => Container(
                width: 1.5, height: 4.h,
                margin: EdgeInsets.symmetric(vertical: 1.5.h),
                color: Colors.grey[350],
              )),
            ),
          ),
          _AddressRow(
            dotColor: AppColors.error,
            text: _rideData!['destination_address'] ?? 'Destination',
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────── Action Button ─────────────
  Widget _buildActionButton() {
    String label;
    IconData icon;
    Color bg;

    switch (_status) {
      case 'accepted':
      case 'driver_arriving':
        label = 'JE SUIS ARRIVÉ';
        icon = Icons.flag_rounded;
        bg = AppColors.info;
        break;
      case 'driver_arrived':
        label = 'DÉMARRER LA COURSE';
        icon = Icons.play_arrow_rounded;
        bg = AppColors.primary;
        break;
      case 'in_progress':
        label = 'TERMINER LA COURSE';
        icon = Icons.check_circle_rounded;
        bg = AppColors.primary;
        break;
      case 'completed':
        label = 'RETOUR À L\'ACCUEIL';
        icon = Icons.home_rounded;
        bg = AppColors.primary;
        break;
      default:
        return const SizedBox.shrink();
    }

    return SizedBox(
      width: double.infinity,
      height: _drivingMode ? 58.h : 52.h,
      child: ElevatedButton.icon(
        onPressed: _onActionPressed,
        icon: Icon(icon, size: _drivingMode ? 24.sp : 20.sp),
        label: Text(label,
          style: TextStyle(
            fontSize: _drivingMode ? 17.sp : 15.sp,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_kCardRadius.r),
          ),
        ),
      ),
    );
  }

  void _onActionPressed() {
    switch (_status) {
      case 'accepted':
      case 'driver_arriving':
        _arrivedAtPickup();
        break;
      case 'driver_arrived':
        _startRide();
        break;
      case 'in_progress':
        _completeRide();
        break;
      case 'completed':
        context.go('/home');
        break;
    }
  }

  String _statusLabel() {
    switch (_status) {
      case 'accepted':
      case 'driver_arriving':
        return 'En route vers le passager';
      case 'driver_arrived':
        return 'Arrivé au point de prise en charge';
      case 'in_progress':
        return 'Course en cours';
      case 'completed':
        return 'Course terminée';
      case 'cancelled':
        return 'Course annulée';
      default:
        return _status;
    }
  }
}

// ═══════════════════════════════════════════════ Private widgets ══════════════

class _FloatingBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final bool highlighted;

  const _FloatingBtn({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        elevation: 3,
        shape: const CircleBorder(),
        color: highlighted ? AppColors.primary : _kCardBg,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Padding(
            padding: EdgeInsets.all(12.w),
            child: Icon(
              icon,
              size: 22.sp,
              color: highlighted ? Colors.white : _kTextDark,
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14.sp, color: _kTextMuted),
        SizedBox(width: 4.w),
        Text(label,
          style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500, color: _kTextMuted)),
      ],
    );
  }
}

class _AddressRow extends StatelessWidget {
  final Color dotColor;
  final String text;
  const _AddressRow({required this.dotColor, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10.w,
          height: 10.w,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        SizedBox(width: 10.w),
        Expanded(
          child: Text(text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13.sp, color: _kTextDark)),
        ),
      ],
    );
  }
}
