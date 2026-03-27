import 'dart:async';
import 'dart:convert';

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
import '../../../../core/utils/driver_car_icon.dart';
import '../../../../core/widgets/app_alert.dart';

// ─── Design tokens ───────────────────────────────────────────────────────────
const Color _kAmber = Color(0xFFD97706);
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

  // ── driving mode ───────────────────────────────────────────────────────────
  bool _drivingMode = false;

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
    _loadRide();
    _startTracking();
    _connectWebSocket();
  }

  Future<void> _loadMapStyle() async {
    _mapStyle = await rootBundle.loadString('assets/map_style_light.json');
    _mapController?.setMapStyle(_mapStyle!);
  }

  Future<void> _initCarIcon() async {
    _carIcon = await createDriverCarIcon(size: 100, heading: _heading);
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

      // Auto-transition to driver_arriving when first entering ride
      if (_status == 'accepted') {
        _markDriverArriving();
      }
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
      });
    }
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
      final newHeading = pos.heading;

      // Refresh car icon if heading changed significantly
      if ((_heading - newHeading).abs() > 10) {
        _heading = newHeading;
        _carIcon = await createDriverCarIcon(size: 100, heading: _heading);
      }

      setState(() => _currentPosition = newPos);

      // Follow driver in driving mode
      if (_drivingMode) {
        _mapController?.animateCamera(CameraUpdate.newCameraPosition(
          CameraPosition(
            target: newPos,
            zoom: 17,
            tilt: 55,
            bearing: newHeading,
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
            _fetchRoute();
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
    if (_status == 'completed' || _status == 'cancelled') return;

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
      setState(() => _status = 'driver_arrived');
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
    final price = _rideData?['estimated_price'] ?? '—';
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
                style: TextStyle(fontSize: 28.sp, fontWeight: FontWeight.w800, color: _kAmber)),
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
                    backgroundColor: _kAmber,
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
    _ws?.sink.close();
    _heartbeatTimer?.cancel();
    _wsReconnectTimer?.cancel();
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
          child: CircularProgressIndicator(color: _kAmber),
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

            // ── Top Info Card ──
            if (!_drivingMode) _buildTopInfoCard(),

            // ── Driving mode ETA strip ──
            if (_drivingMode) _buildDrivingEtaStrip(),

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

    // Pickup marker
    if (_pickupLatLng != null) {
      markers.add(Marker(
        markerId: const MarkerId('pickup'),
        position: _pickupLatLng!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
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
      // Shadow polyline
      polylines.add(Polyline(
        polylineId: const PolylineId('route_shadow'),
        points: _routePoints,
        color: Colors.black26,
        width: 8,
        zIndex: 0,
      ));
      // Main amber route
      polylines.add(Polyline(
        polylineId: const PolylineId('route_main'),
        points: _routePoints,
        color: _kAmber,
        width: 5,
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
                    color: _status == 'in_progress' ? AppColors.error : _kAmber,
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
          color: _kAmber,
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
          backgroundColor: _kAmber.withOpacity(0.12),
          child: Icon(Icons.person_rounded, color: _kAmber, size: _drivingMode ? 20.sp : 24.sp),
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
            color: _kAmber.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8.r),
          ),
          child: Text('$price CDF',
            style: TextStyle(
              fontSize: _drivingMode ? 15.sp : 16.sp,
              fontWeight: FontWeight.w700,
              color: _kAmber,
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
            dotColor: _kAmber,
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
        bg = _kAmber;
        break;
      case 'in_progress':
        label = 'TERMINER LA COURSE';
        icon = Icons.check_circle_rounded;
        bg = _kAmber;
        break;
      case 'completed':
        label = 'RETOUR À L\'ACCUEIL';
        icon = Icons.home_rounded;
        bg = _kAmber;
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
        color: highlighted ? _kAmber : _kCardBg,
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
