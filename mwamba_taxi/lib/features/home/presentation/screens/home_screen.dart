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
import '../../../../core/utils/car_marker_icon.dart';
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

  BitmapDescriptor _carIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
  Timer? _driverRefreshTimer;

  // Zoom-aware scaling
  double _currentZoom = 14;
  int _lastZoomBucket = 14;
  final Map<int, BitmapDescriptor> _carIconCache = {};
  Timer? _zoomDebounce;
  List<LatLng> _routePoints = [];

  // CTA animation
  late AnimationController _ctaAnimController;
  late Animation<double> _ctaScaleAnim;

  // Active ride
  Map<String, dynamic>? _activeRide;

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
    final size = carSizeForZoom(_currentZoom);
    final bucket = _currentZoom.round();
    if (_carIconCache.containsKey(bucket)) {
      _carIcon = _carIconCache[bucket]!;
      _loadNearbyDrivers();
      return;
    }
    final icon = await createCarMarkerIcon(size: size);
    _carIconCache[bucket] = icon;
    if (mounted) {
      setState(() => _carIcon = icon);
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
          color: const Color(0xFF1A73E8),
          width: w + 3,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
          zIndex: 0,
        ));
        _polylines.add(Polyline(
          polylineId: const PolylineId('route'),
          points: _routePoints,
          color: const Color(0xFF4285F4),
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
    final points = await _placesService.getRoutePolyline(origin, destination);
    if (!mounted) return;

    setState(() {
      _isRouteLoading = false;
      _routePoints = points;
      _polylines.clear();
      if (points.isNotEmpty) {
        final w = polylineWidthForZoom(_currentZoom);
        // Darker blue border (underneath)
        _polylines.add(Polyline(
          polylineId: const PolylineId('route_border'),
          points: points,
          color: const Color(0xFF1A73E8),
          width: w + 3,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
          zIndex: 0,
        ));
        // Google blue route line (on top)
        _polylines.add(Polyline(
          polylineId: const PolylineId('route'),
          points: points,
          color: const Color(0xFF4285F4),
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

      final drivers = response.data as List;
      final driverMarkers = drivers.map((d) {
        final heading = double.tryParse(d['heading']?.toString() ?? '') ?? 0;
        return Marker(
          markerId: MarkerId('driver_${d['id']}'),
          position: LatLng(
            double.parse(d['latitude']),
            double.parse(d['longitude']),
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
            initialChildSize: 0.38,
            minChildSize: 0.12,
            maxChildSize: 0.65,
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
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
                        margin: EdgeInsets.only(top: 10.h, bottom: 14.h),
                        width: 36.w,
                        height: 4.h,
                        decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(2.r),
                        ),
                      ),
                    ),

                    // Ride type pills
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20.w),
                      child: Row(
                        children: [
                          _RideTypePill(
                            label: AppStrings.immediateRide,
                            icon: Icons.bolt_rounded,
                            isActive: _selectedRideType == 0,
                            onTap: () => setState(() => _selectedRideType = 0),
                          ),
                          SizedBox(width: 10.w),
                          _RideTypePill(
                            label: AppStrings.scheduleRide,
                            icon: Icons.schedule_rounded,
                            isActive: _selectedRideType == 1,
                            onTap: () => setState(() => _selectedRideType = 1),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 20.h),

                    // Vehicle type cards
                    SizedBox(
                      height: 110.h,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: EdgeInsets.symmetric(horizontal: 20.w),
                        children: [
                          _VehicleCard(
                            icon: Icons.directions_car_rounded,
                            title: AppStrings.vehicleStandard,
                            subtitle: AppStrings.vehicleStandardDesc,
                            isSelected: _selectedVehicle == 0,
                            onTap: () { setState(() => _selectedVehicle = 0); _loadNearbyDrivers(); },
                          ),
                          SizedBox(width: 10.w),
                          _VehicleCard(
                            icon: Icons.airline_seat_recline_extra_rounded,
                            title: AppStrings.vehicleComfort,
                            subtitle: AppStrings.vehicleComfortDesc,
                            isSelected: _selectedVehicle == 1,
                            onTap: () { setState(() => _selectedVehicle = 1); _loadNearbyDrivers(); },
                          ),
                          SizedBox(width: 10.w),
                          _VehicleCard(
                            icon: Icons.two_wheeler_rounded,
                            title: AppStrings.vehicleMoto,
                            subtitle: AppStrings.vehicleMotoDesc,
                            isSelected: _selectedVehicle == 2,
                            onTap: () { setState(() => _selectedVehicle = 2); _loadNearbyDrivers(); },
                          ),
                          SizedBox(width: 10.w),
                          _VehicleCard(
                            icon: Icons.airport_shuttle_rounded,
                            title: AppStrings.vehicleGroup,
                            subtitle: AppStrings.vehicleGroupDesc,
                            isSelected: _selectedVehicle == 3,
                            onTap: () { setState(() => _selectedVehicle = 3); _loadNearbyDrivers(); },
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 20.h),

                    // Divider
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20.w),
                      child: Divider(height: 1, color: AppColors.border.withOpacity(0.5)),
                    ),
                    SizedBox(height: 16.h),

                    // Payment method selector
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20.w),
                      child: Row(
                        children: [
                          Icon(Icons.payment_rounded, size: 16.sp, color: AppColors.textHint),
                          SizedBox(width: 8.w),
                          Text(
                            AppStrings.paymentMethod,
                            style: GoogleFonts.poppins(
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 10.h),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20.w),
                      child: Row(
                        children: [
                          _PaymentPill(
                            label: AppStrings.cash,
                            icon: Icons.money_rounded,
                            isActive: _selectedPayment == 0,
                            onTap: () => setState(() => _selectedPayment = 0),
                          ),
                          SizedBox(width: 8.w),
                          _PaymentPill(
                            label: 'M-Pesa',
                            icon: Icons.phone_android_rounded,
                            isActive: _selectedPayment == 1,
                            onTap: () => setState(() => _selectedPayment = 1),
                          ),
                          SizedBox(width: 8.w),
                          _PaymentPill(
                            label: 'Airtel',
                            icon: Icons.phone_android_rounded,
                            isActive: _selectedPayment == 2,
                            onTap: () => setState(() => _selectedPayment = 2),
                          ),
                          SizedBox(width: 8.w),
                          _PaymentPill(
                            label: 'Orange',
                            icon: Icons.phone_android_rounded,
                            isActive: _selectedPayment == 3,
                            onTap: () => setState(() => _selectedPayment = 3),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 16.h),

                    // Destination summary (when selected)
                    if (_destinationLocation != null) ...[
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20.w),
                        child: Divider(height: 1, color: AppColors.border.withOpacity(0.5)),
                      ),
                      SizedBox(height: 14.h),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20.w),
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                          decoration: BoxDecoration(
                            color: AppColors.success.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.location_on_rounded, color: AppColors.success, size: 18.sp),
                              SizedBox(width: 10.w),
                              Expanded(
                                child: Text(
                                  _destinationAddress,
                                  style: GoogleFonts.poppins(
                                    fontSize: 12.sp,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.textPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _destinationLocation = null;
                                    _destinationAddress = '';
                                    _priceEstimate = null;
                                    _polylines.clear();
                                    _markers.removeWhere((m) =>
                                        m.markerId.value == 'pickup' ||
                                        m.markerId.value == 'destination');
                                  });
                                  _ctaAnimController.reverse();
                                },
                                child: Icon(Icons.close_rounded, color: AppColors.textHint, size: 16.sp),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 12.h),
                    ],

                    // Price estimate display
                    if (_priceEstimate != null) ...[
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20.w),
                        child: Row(
                          children: [
                            Expanded(
                              child: _InfoChip(
                                icon: Icons.payments_rounded,
                                label: '${_priceEstimate!['estimated_price']} CDF',
                                color: AppColors.primary,
                              ),
                            ),
                            SizedBox(width: 8.w),
                            Expanded(
                              child: _InfoChip(
                                icon: Icons.route_rounded,
                                label: '${_priceEstimate!['distance_km']} km',
                                color: AppColors.info,
                              ),
                            ),
                            SizedBox(width: 8.w),
                            Expanded(
                              child: _InfoChip(
                                icon: Icons.schedule_rounded,
                                label: '${(_priceEstimate!['estimated_duration_minutes'] as num).toInt()} min',
                                color: AppColors.success,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 16.h),
                    ],

                    // CTA button – only visible when destination is chosen
                    if (_destinationLocation != null)
                      AnimatedBuilder(
                        animation: _ctaScaleAnim,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _ctaScaleAnim.value,
                            child: child,
                          );
                        },
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 20.w),
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: AppColors.ctaGradient,
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ),
                              borderRadius: BorderRadius.circular(16.r),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primaryDark.withOpacity(0.3),
                                  blurRadius: 14,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () {
                                  if (_priceEstimate != null) {
                                    _showRideRequestSheet();
                                  } else {
                                    _estimatePrice();
                                  }
                                },
                                borderRadius: BorderRadius.circular(16.r),
                                child: Padding(
                                  padding: EdgeInsets.symmetric(vertical: 14.h),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.local_taxi_rounded,
                                        size: 20.sp,
                                        color: Colors.white,
                                      ),
                                      SizedBox(width: 10.w),
                                      Text(
                                        AppStrings.orderRide,
                                        style: GoogleFonts.poppins(
                                          fontSize: 15.sp,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.2,
                                          color: Colors.white,
                                        ),
                                      ),
                                      SizedBox(width: 8.w),
                                      Icon(
                                        Icons.arrow_forward_rounded,
                                        size: 16.sp,
                                        color: Colors.white.withOpacity(0.8),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
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

class _RideTypePill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _RideTypePill({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(30.r),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16.sp,
              color: isActive ? Colors.white : AppColors.textSecondary,
            ),
            SizedBox(width: 6.w),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
                color: isActive ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VehicleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  const _VehicleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 120.w,
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withOpacity(0.08) : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32.w,
              height: 32.w,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary.withOpacity(0.15)
                    : Colors.white,
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Icon(
                icon,
                size: 18.sp,
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
            const Spacer(),
            Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 12.sp,
                fontWeight: FontWeight.w600,
                color: isSelected ? AppColors.primary : AppColors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              subtitle,
              style: GoogleFonts.poppins(
                fontSize: 10.sp,
                color: AppColors.textHint,
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

class _PaymentPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _PaymentPill({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(vertical: 10.h),
          decoration: BoxDecoration(
            color: isActive ? AppColors.primary.withOpacity(0.1) : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(
              color: isActive ? AppColors.primary : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16.sp,
                color: isActive ? AppColors.primary : AppColors.textSecondary,
              ),
              SizedBox(height: 4.h),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 10.sp,
                  fontWeight: FontWeight.w600,
                  color: isActive ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14.sp, color: color),
          SizedBox(width: 6.w),
          Flexible(
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 12.sp,
                fontWeight: FontWeight.w700,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
