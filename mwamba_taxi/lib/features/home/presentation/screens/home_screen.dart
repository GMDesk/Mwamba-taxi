import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/places_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/vehicle_asset_marker.dart';
import '../widgets/destination_search_sheet.dart';
import '../widgets/ride_request_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final Completer<GoogleMapController> _mapController = Completer();
  final ApiClient _api = getIt<ApiClient>();
  final PlacesService _placesService = PlacesService();

  LatLng _currentPosition = const LatLng(-4.3250, 15.3222); // Kinshasa default
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  bool _isLoading = true;
  bool _isRouteLoading = false;

  // Ride state
  LatLng? _pickupLocation;
  LatLng? _destinationLocation;
  String _pickupAddress = '';
  String _destinationAddress = '';
  Map<String, dynamic>? _priceEstimate;

  int _selectedVehicle = 0;
  int _selectedRideType = 0;

  // Payment method: 0=cash, 1=mpesa, 2=airtel, 3=orange
  int _selectedPayment = 0;

  // Vehicle categories mapping to backend
  static const _vehicleCategories = ['economy', 'comfort', 'moto', 'van'];

  Timer? _driverRefreshTimer;

  // Zoom-aware scaling
  double _currentZoom = 14;
  int _lastZoomBucket = 14;
  Timer? _zoomDebounce;
  List<LatLng> _routePoints = [];

  // CTA animation
  late AnimationController _ctaAnimController;
  late Animation<double> _ctaScaleAnim;

  // Active ride
  Map<String, dynamic>? _activeRide;

  // Route ETA from Directions API
  int _routeDurationMinutes = 0;

  // Driver comment (Yango-style)
  String _driverComment = '';

  @override
  void initState() {
    super.initState();
    _ctaAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _ctaScaleAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctaAnimController, curve: Curves.easeOutBack),
    );
    _createCarIcon();
    _getCurrentLocation();
    _checkActiveRide();
    WidgetsBinding.instance.addObserver(this);
    _driverRefreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _loadNearbyDrivers(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _driverRefreshTimer?.cancel();
    _zoomDebounce?.cancel();
    _ctaAnimController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkActiveRide();
    }
  }

  /// Loads the car marker icon at the appropriate size for the current zoom.
  Future<void> _createCarIcon() async {
    // Pre-warm the sprite cache for the current zoom
    await getVehicleMarker(
      heading: 0,
      zoom: _currentZoom,
      state: VehicleState.available,
    );
    if (mounted) {
      _loadNearbyDrivers();
    }
  }

  /// Called on every camera move — debounces zoom-based updates.
  void _onCameraMove(CameraPosition pos) {
    final bucket = pos.zoom.round();
    _currentZoom = pos.zoom;
    if (bucket != _lastZoomBucket) {
      _lastZoomBucket = bucket;
      _zoomDebounce?.cancel();
      _zoomDebounce = Timer(const Duration(milliseconds: 250), () {
        _createCarIcon();
        if (_routePoints.isNotEmpty) _rebuildPolylines();
      });
    }
  }

  /// Rebuilds polylines at the width matching the current zoom level.
  void _rebuildPolylines() {
    final w = polylineWidthForZoom(_currentZoom);
    setState(() {
      _polylines.clear();
      if (_routePoints.isNotEmpty) {
        _polylines.add(Polyline(
          polylineId: const PolylineId('route_border'),
          points: _routePoints,
          color: const Color(0xFF0D904F),
          width: w + 3,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
          zIndex: 0,
        ));
        _polylines.add(Polyline(
          polylineId: const PolylineId('route'),
          points: _routePoints,
          color: const Color(0xFF00C853),
          width: w,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
          zIndex: 1,
        ));
      }
    });
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }

        if (permission == LocationPermission.always ||
            permission == LocationPermission.whileInUse) {
          final position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          );
          setState(() {
            _currentPosition = LatLng(position.latitude, position.longitude);
            _pickupLocation = _currentPosition;
            _pickupAddress = AppStrings.myLocation;
          });
          _animateToPosition(_currentPosition);
          // Resolve real address in background
          _placesService.reverseGeocode(_currentPosition).then((addr) {
            if (addr != null && mounted) {
              setState(() => _pickupAddress = addr);
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error getting location: $e');
    } finally {
      setState(() => _isLoading = false);
      _loadNearbyDrivers();
    }
  }

  Future<void> _checkActiveRide() async {
    try {
      final resp = await _api.dio.get(ApiConstants.activeRide);
      final data = resp.data as Map<String, dynamic>;
      if (!mounted) return;
      if (data['active'] == true) {
        setState(() => _activeRide = data);
      } else {
        setState(() => _activeRide = null);
      }
    } catch (_) {}
  }

  Future<void> _animateToPosition(LatLng position) async {
    final controller = await _mapController.future;
    controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: position, zoom: 15),
      ),
    );
  }

  /// Fetches the driving route and draws it as a polyline on the map.
  /// Also fits the camera to show both endpoints.
  Future<void> _drawRoute(LatLng origin, LatLng destination) async {
    setState(() => _isRouteLoading = true);
    final result = await _placesService.getRoutePolyline(origin, destination);
    if (!mounted) return;

    setState(() {
      _isRouteLoading = false;
      _routePoints = result.points;
      _routeDurationMinutes = (result.durationSeconds / 60).ceil();
      _polylines.clear();
      if (result.points.isNotEmpty) {
        final w = polylineWidthForZoom(_currentZoom);
        // Darker green border (underneath) — Yango style
        _polylines.add(Polyline(
          polylineId: const PolylineId('route_border'),
          points: result.points,
          color: const Color(0xFF0D904F),
          width: w + 3,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
          zIndex: 0,
        ));
        // Bright green route line (on top) — Yango style
        _polylines.add(Polyline(
          polylineId: const PolylineId('route'),
          points: result.points,
          color: const Color(0xFF00C853),
          width: w,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
          zIndex: 1,
        ));
      }
    });

    // Fit camera to show full route + nearby drivers
    final controller = await _mapController.future;
    final latitudes = [origin.latitude, destination.latitude];
    final longitudes = [origin.longitude, destination.longitude];
    // Include nearby driver markers in bounds
    for (final m in _markers) {
      if (m.markerId.value.startsWith('driver_')) {
        latitudes.add(m.position.latitude);
        longitudes.add(m.position.longitude);
      }
    }
    final bounds = LatLngBounds(
      southwest: LatLng(
        latitudes.reduce((a, b) => a < b ? a : b) - 0.003,
        longitudes.reduce((a, b) => a < b ? a : b) - 0.003,
      ),
      northeast: LatLng(
        latitudes.reduce((a, b) => a > b ? a : b) + 0.003,
        longitudes.reduce((a, b) => a > b ? a : b) + 0.003,
      ),
    );
    controller.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 100),
    );
  }

  Future<void> _loadNearbyDrivers() async {
    if (!mounted) return;
    try {
      final response = await _api.dio.get(
        ApiConstants.nearbyDrivers,
        queryParameters: {
          'latitude': _currentPosition.latitude,
          'longitude': _currentPosition.longitude,
          'radius': 15,
          'vehicle_category': _vehicleCategories[_selectedVehicle],
        },
      );
      if (!mounted) return;

      final drivers = response.data as List;
      final Set<Marker> driverMarkers = {};
      for (final d in drivers) {
        final heading = double.tryParse(d['heading']?.toString() ?? '') ?? 0;
        final icon = await getVehicleMarker(
          heading: heading,
          zoom: _currentZoom,
          state: VehicleState.available,
        );
        if (!mounted) return;
        driverMarkers.add(Marker(
          markerId: MarkerId('driver_${d['id']}'),
          position: LatLng(
            double.parse(d['latitude']),
            double.parse(d['longitude']),
          ),
          icon: icon,
          anchor: const Offset(0.5, 0.5),
          flat: true,
          infoWindow: InfoWindow(
            title: d['driver_name'],
            snippet: '${d['vehicle_make']} ${d['vehicle_model']} ⭐${d['rating']}',
          ),
        ));
      }

      if (!mounted) return;
      setState(() {
        _markers.removeWhere((m) => m.markerId.value.startsWith('driver_'));
        _markers.addAll(driverMarkers);
      });
    } catch (e) {
      debugPrint('Error loading nearby drivers: $e');
    }
  }

  Future<void> _estimatePrice() async {
    if (_pickupLocation == null || _destinationLocation == null) return;

    try {
      final response = await _api.dio.post(
        ApiConstants.estimatePrice,
        data: {
          'pickup_latitude': _pickupLocation!.latitude,
          'pickup_longitude': _pickupLocation!.longitude,
          'destination_latitude': _destinationLocation!.latitude,
          'destination_longitude': _destinationLocation!.longitude,
        },
      );
      if (!mounted) return;

      setState(() => _priceEstimate = response.data);

      if (mounted) {
        _showRideRequestSheet();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(
            e is DioException
                ? (_extractErrorMessage(e) ?? 'Erreur lors de l\'estimation du prix')
                : 'Erreur lors de l\'estimation du prix',
          )),
        );
      }
    }
  }

  Future<void> _requestRide() async {
    if (_priceEstimate == null) return;

    try {
      final response = await _api.dio.post(
        ApiConstants.requestRide,
        data: {
          'pickup_address': _pickupAddress,
          'pickup_latitude': _pickupLocation!.latitude,
          'pickup_longitude': _pickupLocation!.longitude,
          'destination_address': _destinationAddress,
          'destination_latitude': _destinationLocation!.latitude,
          'destination_longitude': _destinationLocation!.longitude,
          'estimated_price': _priceEstimate!['estimated_price'],
          'distance_km': _priceEstimate!['distance_km'],
          'estimated_duration_minutes': (_priceEstimate!['estimated_duration_minutes'] as num).toInt(),
          'vehicle_category': _vehicleCategories[_selectedVehicle],
          'payment_method': ['cash', 'mpesa', 'airtel', 'orange'][_selectedPayment],
        },
      );

      final rideId = response.data['id'];
      if (mounted) {
        context.push('/ride/$rideId');
      }
    } on DioException catch (e) {
      if (!mounted) return;
      final msg = _extractErrorMessage(e) ?? 'Erreur lors de la commande';
      // On any 400 error, check if there's an active ride and navigate to it
      if (e.response?.statusCode == 400) {
        try {
          final resp = await _api.dio.get(ApiConstants.activeRide);
          final data = resp.data as Map<String, dynamic>;
          if (data['active'] == true) {
            final rideId = data['id']?.toString() ?? '';
            if (rideId.isNotEmpty && mounted) {
              setState(() => _activeRide = data);
              context.push('/ride/$rideId');
              return;
            }
          }
        } catch (_) {}
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e')),
        );
      }
    }
  }

  String? _extractErrorMessage(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      if (data.containsKey('detail')) return data['detail'].toString();
      for (final v in data.values) {
        if (v is List && v.isNotEmpty) return v.first.toString();
        if (v is String) return v;
      }
    }
    if (e.response?.statusCode == 401) return 'Session expirée. Reconnectez-vous.';
    if (e.response?.statusCode == 403) return 'Accès non autorisé.';
    return null;
  }

  void _showDestinationSearch() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DestinationSearchSheet(
        onDestinationSelected: (address, latLng) async {
          setState(() {
            _destinationAddress = address;
            _destinationLocation = latLng;
            // Pickup marker – green
            _markers.removeWhere(
                (m) => m.markerId.value == 'pickup' ||
                        m.markerId.value == 'destination');
            if (_pickupLocation != null) {
              _markers.add(Marker(
                markerId: const MarkerId('pickup'),
                position: _pickupLocation!,
                icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueGreen),
                infoWindow: InfoWindow(title: _pickupAddress.isNotEmpty
                    ? _pickupAddress
                    : 'Ma position'),
              ));
            }
            // Destination marker – red
            _markers.add(Marker(
              markerId: const MarkerId('destination'),
              position: latLng,
              icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueRed),
              infoWindow: InfoWindow(title: address),
            ));
          });
          Navigator.pop(context);
          // Animate CTA button in
          _ctaAnimController.forward();
          // Draw route
          if (_pickupLocation != null) {
            await _drawRoute(_pickupLocation!, latLng);
          }
          _estimatePrice();
        },
      ),
    );
  }

  void _showRideRequestSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => RideRequestSheet(
        pickupAddress: _pickupAddress,
        destinationAddress: _destinationAddress,
        priceEstimate: _priceEstimate!,
        vehicleType: _vehicleCategories[_selectedVehicle],
        paymentMethod: ['cash', 'mpesa', 'airtel', 'orange'][_selectedPayment],
        onConfirm: () {
          Navigator.pop(context);
          _requestRide();
        },
      ),
    );
  }

  String _categoryPrice(double multiplier) {
    if (_priceEstimate == null) return '';
    final base = (_priceEstimate!['estimated_price'] as num).toDouble();
    final price = (base * multiplier).round();
    return '$price CDF';
  }

  String _arrivalTimeString() {
    final arrival = DateTime.now().add(Duration(minutes: _routeDurationMinutes));
    return '${arrival.hour.toString().padLeft(2, '0')}:${arrival.minute.toString().padLeft(2, '0')}';
  }

  void _showDriverCommentSheet() {
    final controller = TextEditingController(text: _driverComment);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.dark,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
          ),
          padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36.w, height: 4.h,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2.r),
                  ),
                ),
              ),
              SizedBox(height: 16.h),
              Text(
                'Commentaires pour le conducteur',
                style: GoogleFonts.poppins(
                  fontSize: 16.sp, fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 12.h),
              TextField(
                controller: controller,
                maxLines: 3,
                style: GoogleFonts.poppins(fontSize: 14.sp, color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Ex: Je suis devant le portail bleu...',
                  hintStyle: GoogleFonts.poppins(fontSize: 14.sp, color: Colors.white.withOpacity(0.4)),
                  filled: true,
                  fillColor: AppColors.darkLight,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              SizedBox(height: 16.h),
              SizedBox(
                width: double.infinity,
                height: 48.h,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() => _driverComment = controller.text.trim());
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                  ),
                  child: Text('Enregistrer', style: GoogleFonts.poppins(
                    fontSize: 15.sp, fontWeight: FontWeight.w600, color: Colors.white,
                  )),
                ),
              ),
              SizedBox(height: 10.h),
            ],
          ),
        ),
      ),
    );
  }

  void _showPaymentSheet() {
    final paymentOptions = [
      {'label': AppStrings.cash, 'icon': Icons.payments_rounded, 'index': 0},
      {'label': 'M-Pesa', 'icon': Icons.phone_android_rounded, 'index': 1},
      {'label': 'Airtel Money', 'icon': Icons.phone_android_rounded, 'index': 2},
      {'label': 'Orange Money', 'icon': Icons.phone_android_rounded, 'index': 3},
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
        ),
        padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36.w, height: 4.h,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),
            ),
            SizedBox(height: 16.h),
            Text(
              AppStrings.paymentMethod,
              style: GoogleFonts.poppins(
                fontSize: 16.sp, fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 14.h),
            ...paymentOptions.map((opt) {
              final idx = opt['index'] as int;
              final isActive = _selectedPayment == idx;
              return GestureDetector(
                onTap: () {
                  setState(() => _selectedPayment = idx);
                  Navigator.pop(ctx);
                },
                child: Container(
                  margin: EdgeInsets.only(bottom: 8.h),
                  padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
                  decoration: BoxDecoration(
                    color: isActive ? AppColors.primary.withOpacity(0.08) : AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(
                      color: isActive ? AppColors.primary : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(opt['icon'] as IconData, size: 22.sp,
                        color: isActive ? AppColors.primary : AppColors.textSecondary),
                      SizedBox(width: 14.w),
                      Text(
                        opt['label'] as String,
                        style: GoogleFonts.poppins(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w500,
                          color: isActive ? AppColors.primary : AppColors.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      if (isActive)
                        Icon(Icons.check_circle_rounded, size: 20.sp, color: AppColors.primary),
                    ],
                  ),
                ),
              );
            }),
            SizedBox(height: 10.h),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // ── Google Map ──
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _currentPosition,
                zoom: 14,
              ),
              onMapCreated: (controller) async {
                _mapController.complete(controller);
                final style = await rootBundle.loadString('assets/map_style.json');
                controller.setMapStyle(style);
              },
              onCameraMove: _onCameraMove,
              markers: _markers,
              polylines: _polylines,
              trafficEnabled: true,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
            ),
          ),

          // ── Floating ETA badge (Yango-style red pill on map) ──
          if (_destinationLocation != null && _routeDurationMinutes > 0)
            Positioned(
              top: MediaQuery.of(context).padding.top + 60.h,
              right: 16.w,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Red ETA badge
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(12.r),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFEF4444).withOpacity(0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Text(
                      '$_routeDurationMinutes min',
                      style: GoogleFonts.poppins(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  SizedBox(height: 4.h),
                  // Arrival time label
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8.r),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      'arrivée à ${_arrivalTimeString()}',
                      style: GoogleFonts.poppins(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ── Dark header (hidden when destination selected) ──
          if (_destinationLocation == null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: AppColors.darkGradient,
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 12.h),
                    child: Row(
                      children: [
                        Image.asset(
                          'assets/images/logo.png',
                          height: 32.h,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.local_taxi_rounded,
                            color: AppColors.primary,
                            size: 28.sp,
                          ),
                        ),
                        SizedBox(width: 10.w),
                        Text(
                          AppStrings.appName,
                          style: GoogleFonts.poppins(
                            fontSize: 18.sp,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => context.push('/profile'),
                          child: Container(
                            width: 40.w,
                            height: 40.w,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.person_rounded,
                              color: Colors.white,
                              size: 20.sp,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // ── Search bar (hidden when destination selected) ──
          if (_destinationLocation == null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 72.h,
              left: 20.w,
              right: 20.w,
              child: GestureDetector(
                onTap: _showDestinationSearch,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 14.w,
                    vertical: 12.h,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14.r),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32.w,
                        height: 32.w,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10.r),
                        ),
                        child: Icon(
                          Icons.search_rounded,
                          color: AppColors.primary,
                          size: 18.sp,
                        ),
                      ),
                      SizedBox(width: 12.w),
                      Text(
                        AppStrings.whereToGo,
                        style: GoogleFonts.poppins(
                          fontSize: 14.sp,
                          color: AppColors.textHint,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── Back button (visible when destination selected) ──
          if (_destinationLocation != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8.h,
              left: 16.w,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _destinationLocation = null;
                    _destinationAddress = '';
                    _priceEstimate = null;
                    _routeDurationMinutes = 0;
                    _polylines.clear();
                    _markers.removeWhere((m) =>
                        m.markerId.value == 'pickup' ||
                        m.markerId.value == 'destination');
                  });
                  _ctaAnimController.reverse();
                },
                child: Container(
                  width: 44.w,
                  height: 44.w,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14.r),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(Icons.arrow_back_rounded, color: AppColors.dark, size: 22.sp),
                ),
              ),
            ),

          // ── Active ride banner ──
          if (_activeRide != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + (_destinationLocation == null ? 130.h : 8.h),
              left: 20.w,
              right: 20.w,
              child: GestureDetector(
                onTap: () {
                  final rideId = _activeRide!['id']?.toString() ?? '';
                  if (rideId.isNotEmpty) {
                    context.push('/ride/$rideId');
                  }
                },
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18.r),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryDark.withOpacity(0.15),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44.w,
                        height: 44.w,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(14.r),
                        ),
                        child: Icon(
                          Icons.local_taxi_rounded,
                          color: AppColors.primary,
                          size: 22.sp,
                        ),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Course en cours',
                              style: GoogleFonts.poppins(
                                fontSize: 14.sp,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            SizedBox(height: 2.h),
                            Text(
                              _activeRide!['destination_address'] ?? 'Voir les détails',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: 12.sp,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.primaryDark, AppColors.primary],
                          ),
                          borderRadius: BorderRadius.circular(10.r),
                        ),
                        child: Text(
                          'Voir',
                          style: GoogleFonts.poppins(
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── My location FABs ──
          Positioned(
            right: 16.w,
            bottom: 340.h,
            child: Column(
              children: [
                _MapFab(
                  icon: Icons.my_location_rounded,
                  onTap: () => _getCurrentLocation(),
                ),
                SizedBox(height: 10.h),
                _MapFab(
                  icon: Icons.layers_rounded,
                  onTap: () {},
                ),
              ],
            ),
          ),

          // ── Scrollable bottom sheet ──
          DraggableScrollableSheet(
            initialChildSize: _destinationLocation != null ? 0.48 : 0.42,
            minChildSize: 0.12,
            maxChildSize: _destinationLocation != null ? 0.75 : 0.55,
            builder: (context, scrollController) {
              final bool hasRoute = _destinationLocation != null;
              final bool hasPrice = _priceEstimate != null;
              return Container(
                decoration: BoxDecoration(
                  color: hasRoute ? AppColors.dark : Colors.white,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(24.r),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 20,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.zero,
                  children: [
                    // Drag handle
                    Center(
                      child: Container(
                        margin: EdgeInsets.only(top: 10.h, bottom: 10.h),
                        width: 36.w,
                        height: 4.h,
                        decoration: BoxDecoration(
                          color: hasRoute ? Colors.white.withOpacity(0.3) : AppColors.border,
                          borderRadius: BorderRadius.circular(2.r),
                        ),
                      ),
                    ),

                    // ── Pickup address row ──
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20.w),
                      child: Row(
                        children: [
                          Icon(Icons.directions_walk_rounded, size: 22.sp,
                            color: hasRoute ? Colors.white.withOpacity(0.6) : AppColors.textSecondary),
                          SizedBox(width: 14.w),
                          Expanded(
                            child: Text(
                              _pickupAddress.isNotEmpty ? _pickupAddress : 'Ma position',
                              style: GoogleFonts.poppins(
                                fontSize: 15.sp,
                                fontWeight: FontWeight.w500,
                                color: hasRoute ? Colors.white : AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.only(left: 56.w, right: 20.w, top: 10.h, bottom: 10.h),
                      child: Divider(height: 1, color: hasRoute ? Colors.white.withOpacity(0.12) : AppColors.border),
                    ),

                    // ── Destination address row ──
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20.w),
                      child: GestureDetector(
                        onTap: _destinationLocation == null ? _showDestinationSearch : null,
                        child: Row(
                          children: [
                            Icon(
                              hasRoute ? Icons.flag_rounded : Icons.location_searching_rounded,
                              size: 22.sp,
                              color: hasRoute ? AppColors.primary : AppColors.primary,
                            ),
                            SizedBox(width: 14.w),
                            Expanded(
                              child: _destinationLocation != null
                                  ? Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            _destinationAddress,
                                            style: GoogleFonts.poppins(
                                              fontSize: 15.sp,
                                              fontWeight: FontWeight.w500,
                                              color: Colors.white,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (_routeDurationMinutes > 0) ...[
                                          SizedBox(width: 6.w),
                                          Text(
                                            '• $_routeDurationMinutes min.',
                                            style: GoogleFonts.poppins(
                                              fontSize: 13.sp,
                                              color: Colors.white.withOpacity(0.5),
                                            ),
                                          ),
                                        ],
                                      ],
                                    )
                                  : Text(
                                      'Où allez-vous ?',
                                      style: GoogleFonts.poppins(
                                        fontSize: 15.sp,
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.textHint,
                                      ),
                                    ),
                            ),
                            if (_destinationLocation != null)
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _destinationLocation = null;
                                    _destinationAddress = '';
                                    _priceEstimate = null;
                                    _routeDurationMinutes = 0;
                                    _polylines.clear();
                                    _markers.removeWhere((m) =>
                                        m.markerId.value == 'pickup' ||
                                        m.markerId.value == 'destination');
                                  });
                                  _ctaAnimController.reverse();
                                },
                                child: Padding(
                                  padding: EdgeInsets.only(left: 8.w),
                                  child: Icon(Icons.close_rounded,
                                    color: hasRoute ? Colors.white.withOpacity(0.5) : AppColors.textHint, size: 18.sp),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 10.h),

                    // ── Divider ──
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20.w),
                      child: Divider(height: 1, color: hasRoute ? Colors.white.withOpacity(0.12) : AppColors.border),
                    ),

                    // ── Large car banner + huge price (Yango expanded dark panel) ──
                    if (hasRoute && hasPrice) ...[
                      SizedBox(height: 16.h),
                      Container(
                        margin: EdgeInsets.symmetric(horizontal: 16.w),
                        padding: EdgeInsets.all(16.w),
                        decoration: BoxDecoration(
                          color: AppColors.darkLight,
                          borderRadius: BorderRadius.circular(16.r),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _selectedVehicle == 2 ? Icons.two_wheeler_rounded
                                  : _selectedVehicle == 3 ? Icons.airport_shuttle_rounded
                                  : Icons.directions_car_filled_rounded,
                              size: 56.sp,
                              color: AppColors.primary,
                            ),
                            SizedBox(width: 16.w),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Courses',
                                    style: GoogleFonts.poppins(
                                      fontSize: 13.sp,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white.withOpacity(0.6),
                                    ),
                                  ),
                                  SizedBox(height: 2.h),
                                  Text(
                                    _categoryPrice([1.0, 1.2, 0.65, 1.5][_selectedVehicle]),
                                    style: GoogleFonts.poppins(
                                      fontSize: 26.sp,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    SizedBox(height: 12.h),

                    // ── Vehicle type cards (Yango-style) ──
                    SizedBox(
                      height: 138.h,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: EdgeInsets.symmetric(horizontal: 16.w),
                        children: [
                          _YangoVehicleCard(
                            icon: Icons.directions_car_filled_rounded,
                            iconColor: const Color(0xFFD97706),
                            title: AppStrings.vehicleStandard,
                            eta: _routeDurationMinutes > 0 ? '$_routeDurationMinutes min.' : null,
                            price: hasPrice ? _categoryPrice(1.0) : null,
                            isSelected: _selectedVehicle == 0,
                            isDark: hasRoute,
                            onTap: () { setState(() => _selectedVehicle = 0); _loadNearbyDrivers(); },
                          ),
                          SizedBox(width: 8.w),
                          _YangoVehicleCard(
                            icon: Icons.directions_car_filled_rounded,
                            iconColor: const Color(0xFF3B82F6),
                            title: AppStrings.vehicleComfort,
                            eta: _routeDurationMinutes > 0 ? '${_routeDurationMinutes + 5} min.' : null,
                            price: hasPrice ? _categoryPrice(1.2) : null,
                            isSelected: _selectedVehicle == 1,
                            isDark: hasRoute,
                            onTap: () { setState(() => _selectedVehicle = 1); _loadNearbyDrivers(); },
                          ),
                          SizedBox(width: 8.w),
                          _YangoVehicleCard(
                            icon: Icons.two_wheeler_rounded,
                            iconColor: const Color(0xFF10B981),
                            title: AppStrings.vehicleMoto,
                            eta: _routeDurationMinutes > 0 ? '${(_routeDurationMinutes - 3).clamp(1, 999)} min.' : null,
                            price: hasPrice ? _categoryPrice(0.65) : null,
                            isSelected: _selectedVehicle == 2,
                            isDark: hasRoute,
                            onTap: () { setState(() => _selectedVehicle = 2); _loadNearbyDrivers(); },
                          ),
                          SizedBox(width: 8.w),
                          _YangoVehicleCard(
                            icon: Icons.airport_shuttle_rounded,
                            iconColor: const Color(0xFF8B5CF6),
                            title: AppStrings.vehicleGroup,
                            eta: _routeDurationMinutes > 0 ? '${_routeDurationMinutes + 10} min.' : null,
                            price: hasPrice ? _categoryPrice(1.5) : null,
                            isSelected: _selectedVehicle == 3,
                            isDark: hasRoute,
                            onTap: () { setState(() => _selectedVehicle = 3); _loadNearbyDrivers(); },
                          ),
                        ],
                      ),
                    ),

                    // ── Yango extra options (only when route selected) ──
                    if (hasRoute) ...[
                      SizedBox(height: 8.h),
                      // "Non aux négociations de prix!" warning
                      Container(
                        margin: EdgeInsets.symmetric(horizontal: 16.w),
                        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
                        decoration: BoxDecoration(
                          color: AppColors.darkLight,
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_rounded, size: 18.sp, color: AppColors.error),
                            SizedBox(width: 10.w),
                            Expanded(
                              child: Text(
                                'Non aux négociations de prix !',
                                style: GoogleFonts.poppins(
                                  fontSize: 13.sp,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white.withOpacity(0.85),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 8.h),
                      // Payment modification row
                      GestureDetector(
                        onTap: _showPaymentSheet,
                        child: Container(
                          margin: EdgeInsets.symmetric(horizontal: 16.w),
                          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
                          decoration: BoxDecoration(
                            color: AppColors.darkLight,
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _selectedPayment == 0 ? Icons.payments_rounded : Icons.phone_android_rounded,
                                size: 20.sp, color: AppColors.primary,
                              ),
                              SizedBox(width: 10.w),
                              Expanded(
                                child: Text(
                                  'Modification de la modalité de paiement — ${['Espèces', 'M-Pesa', 'Airtel Money', 'Orange Money'][_selectedPayment]}',
                                  style: GoogleFonts.poppins(
                                    fontSize: 13.sp,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white.withOpacity(0.85),
                                  ),
                                ),
                              ),
                              Icon(Icons.chevron_right_rounded, size: 18.sp, color: Colors.white.withOpacity(0.4)),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 8.h),
                      // Comments for driver
                      GestureDetector(
                        onTap: () => _showDriverCommentSheet(),
                        child: Container(
                          margin: EdgeInsets.symmetric(horizontal: 16.w),
                          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
                          decoration: BoxDecoration(
                            color: AppColors.darkLight,
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.chat_bubble_outline_rounded, size: 20.sp, color: Colors.white.withOpacity(0.6)),
                              SizedBox(width: 10.w),
                              Expanded(
                                child: Text(
                                  _driverComment.isNotEmpty ? _driverComment : 'Commentaires pour le conducteur',
                                  style: GoogleFonts.poppins(
                                    fontSize: 13.sp,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white.withOpacity(0.85),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Icon(Icons.chevron_right_rounded, size: 18.sp, color: Colors.white.withOpacity(0.4)),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 8.h),
                      // Order for someone else
                      GestureDetector(
                        onTap: () {},
                        child: Container(
                          margin: EdgeInsets.symmetric(horizontal: 16.w),
                          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
                          decoration: BoxDecoration(
                            color: AppColors.darkLight,
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.person_add_alt_1_rounded, size: 20.sp, color: Colors.white.withOpacity(0.6)),
                              SizedBox(width: 10.w),
                              Expanded(
                                child: Text(
                                  'Commande à une autre personne',
                                  style: GoogleFonts.poppins(
                                    fontSize: 13.sp,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white.withOpacity(0.85),
                                  ),
                                ),
                              ),
                              Icon(Icons.chevron_right_rounded, size: 18.sp, color: Colors.white.withOpacity(0.4)),
                            ],
                          ),
                        ),
                      ),
                    ],

                    SizedBox(height: 12.h),

                    // ── Bottom bar: Payment + Commander + Settings ──
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.w),
                      child: Row(
                        children: [
                          // Payment method icon
                          if (!hasRoute)
                            GestureDetector(
                              onTap: _showPaymentSheet,
                              child: Container(
                                width: 46.w,
                                height: 46.w,
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceVariant,
                                  borderRadius: BorderRadius.circular(12.r),
                                ),
                                child: Icon(
                                  _selectedPayment == 0
                                      ? Icons.payments_rounded
                                      : Icons.phone_android_rounded,
                                  size: 22.sp,
                                  color: AppColors.success,
                                ),
                              ),
                            ),
                          if (!hasRoute) SizedBox(width: 10.w),
                          // Commander button
                          Expanded(
                            child: GestureDetector(
                              onTap: _destinationLocation != null
                                  ? () {
                                      if (_priceEstimate != null) {
                                        _showRideRequestSheet();
                                      } else {
                                        _estimatePrice();
                                      }
                                    }
                                  : _showDestinationSearch,
                              child: Container(
                                height: 50.h,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: AppColors.ctaGradient,
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                  ),
                                  borderRadius: BorderRadius.circular(14.r),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primaryDark.withOpacity(0.25),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Text(
                                    _destinationLocation != null
                                        ? AppStrings.orderRide
                                        : 'Où allez-vous ?',
                                    style: GoogleFonts.poppins(
                                      fontSize: 16.sp,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (!hasRoute) SizedBox(width: 10.w),
                          // Ride type / settings icon
                          if (!hasRoute)
                            GestureDetector(
                              onTap: () => setState(() => _selectedRideType = _selectedRideType == 0 ? 1 : 0),
                              child: Container(
                                width: 46.w,
                                height: 46.w,
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceVariant,
                                  borderRadius: BorderRadius.circular(12.r),
                                ),
                                child: Icon(
                                  _selectedRideType == 0 ? Icons.tune_rounded : Icons.schedule_rounded,
                                  size: 22.sp,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(height: 14.h),
                  ],
                ),
              );
            },
          ),

          // Loading overlay
          if (_isLoading)
            Container(
              color: Colors.white.withOpacity(0.7),
              child: const Center(child: CircularProgressIndicator()),
            ),

          // Route loading indicator
          if (_isRouteLoading)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Center(
                  child: Container(
                    margin: EdgeInsets.only(top: 120.h),
                    padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20.r),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.shadow.withOpacity(0.12),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16.w,
                          height: 16.w,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        ),
                        SizedBox(width: 10.w),
                        Text(
                          'Calcul de l\'itinéraire...',
                          style: GoogleFonts.poppins(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Helper Widgets ─────────────────────────────────────────────────

class _MapFab extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _MapFab({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48.w,
        height: 48.w,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Icon(icon, color: AppColors.dark, size: 22.sp),
      ),
    );
  }
}

class _YangoVehicleCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? eta;
  final String? price;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _YangoVehicleCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.eta,
    this.price,
    required this.isSelected,
    this.isDark = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isDark
        ? (isSelected ? AppColors.darkLight : AppColors.dark.withOpacity(0.6))
        : (isSelected ? Colors.white : AppColors.surfaceVariant);
    final textColor = isDark ? Colors.white : AppColors.textPrimary;
    final hintColor = isDark ? Colors.white.withOpacity(0.5) : AppColors.textHint;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 150.w,
        padding: EdgeInsets.all(10.w),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.transparent,
            width: 1.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Vehicle icon + ETA row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eta != null)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                    decoration: BoxDecoration(
                      color: textColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6.r),
                    ),
                    child: Text(
                      eta!,
                      style: GoogleFonts.poppins(
                        fontSize: 10.sp,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                  ),
                const Spacer(),
                Icon(icon, size: 36.sp, color: iconColor),
              ],
            ),
            const Spacer(),
            // Category name
            Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 13.sp,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: 2.h),
            // Price
            Text(
              price != null ? 'à partir de $price' : '—',
              style: GoogleFonts.poppins(
                fontSize: 11.sp,
                fontWeight: price != null ? FontWeight.w600 : FontWeight.w400,
                color: price != null ? textColor : hintColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
