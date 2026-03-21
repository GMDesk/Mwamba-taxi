import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
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
import '../widgets/destination_search_sheet.dart';
import '../widgets/ride_request_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _isLoading = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        setState(() => _isLoading = false);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
        _pickupLocation = _currentPosition;
        _pickupAddress = AppStrings.myLocation;
        _isLoading = false;
      });

      _animateToPosition(_currentPosition);
      _loadNearbyDrivers();
    } catch (e) {
      setState(() => _isLoading = false);
    }
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
      _polylines.clear();
      if (points.isNotEmpty) {
        // White border line (underneath)
        _polylines.add(Polyline(
          polylineId: const PolylineId('route_border'),
          points: points,
          color: Colors.white.withOpacity(0.8),
          width: 9,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
          zIndex: 0,
        ));
        // Green route line (on top)
        _polylines.add(Polyline(
          polylineId: const PolylineId('route'),
          points: points,
          color: const Color(0xFF22C55E), // vert vif
          width: 6,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
          zIndex: 1,
        ));
      }
    });

    // Fit camera to show full route
    final controller = await _mapController.future;
    final latitudes = [origin.latitude, destination.latitude];
    final longitudes = [origin.longitude, destination.longitude];
    final bounds = LatLngBounds(
      southwest: LatLng(
        latitudes.reduce((a, b) => a < b ? a : b) - 0.005,
        longitudes.reduce((a, b) => a < b ? a : b) - 0.005,
      ),
      northeast: LatLng(
        latitudes.reduce((a, b) => a > b ? a : b) + 0.005,
        longitudes.reduce((a, b) => a > b ? a : b) + 0.005,
      ),
    );
    controller.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 80),
    );
  }

  Future<void> _loadNearbyDrivers() async {
    try {
      final response = await _api.dio.get(
        ApiConstants.nearbyDrivers,
        queryParameters: {
          'latitude': _currentPosition.latitude,
          'longitude': _currentPosition.longitude,
          'radius': 5,
        },
      );

      final drivers = response.data as List;
      final driverMarkers = drivers.map((d) {
        return Marker(
          markerId: MarkerId(d['id']),
          position: LatLng(
            double.parse(d['latitude']),
            double.parse(d['longitude']),
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
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
    } catch (_) {}
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
        },
      );

      final rideId = response.data['id'];
      if (mounted) {
        context.push('/ride/$rideId');
      }
    } on DioException catch (e) {
      if (mounted) {
        final msg = _extractErrorMessage(e) ?? 'Erreur lors de la commande';
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
          // Draw route then estimate price
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
              onMapCreated: (controller) => _mapController.complete(controller),
              markers: _markers,
              polylines: _polylines,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
            ),
          ),

          // ── Dark header ──
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
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(24.r),
                  bottomRight: Radius.circular(24.r),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 16.h),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Logo + profile row
                      Row(
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
                      SizedBox(height: 14.h),

                      // Search bar
                      GestureDetector(
                        onTap: _showDestinationSearch,
                        child: Container(
                          width: double.infinity,
                          padding: EdgeInsets.symmetric(
                            horizontal: 16.w,
                            vertical: 14.h,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.darkLight,
                            borderRadius: BorderRadius.circular(16.r),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.08),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36.w,
                                height: 36.w,
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(12.r),
                                ),
                                child: Icon(
                                  Icons.search_rounded,
                                  color: AppColors.primary,
                                  size: 20.sp,
                                ),
                              ),
                              SizedBox(width: 12.w),
                              Text(
                                AppStrings.whereToGo,
                                style: GoogleFonts.poppins(
                                  fontSize: 15.sp,
                                  color: Colors.white.withOpacity(0.5),
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
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
            minChildSize: 0.15,
            maxChildSize: 0.55,
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(24.r),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 24,
                      offset: const Offset(0, -6),
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
                        margin: EdgeInsets.only(top: 12.h, bottom: 16.h),
                        width: 40.w,
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
                    SizedBox(height: 18.h),

                    // Vehicle type cards
                    Padding(
                      padding: EdgeInsets.only(left: 20.w),
                      child: Text(
                        'Type de véhicule',
                        style: GoogleFonts.poppins(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    SizedBox(height: 10.h),
                    SizedBox(
                      height: 100.h,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: EdgeInsets.symmetric(horizontal: 20.w),
                        children: [
                          _VehicleCard(
                            icon: Icons.directions_car_rounded,
                            title: AppStrings.vehicleEconomy,
                            subtitle: AppStrings.vehicleEconomyDesc,
                            isSelected: _selectedVehicle == 0,
                            onTap: () => setState(() => _selectedVehicle = 0),
                          ),
                          SizedBox(width: 10.w),
                          _VehicleCard(
                            icon: Icons.airline_seat_recline_extra_rounded,
                            title: AppStrings.vehicleComfort,
                            subtitle: AppStrings.vehicleComfortDesc,
                            isSelected: _selectedVehicle == 1,
                            onTap: () => setState(() => _selectedVehicle = 1),
                          ),
                          SizedBox(width: 10.w),
                          _VehicleCard(
                            icon: Icons.airport_shuttle_rounded,
                            title: AppStrings.vehicleVan,
                            subtitle: AppStrings.vehicleVanDesc,
                            isSelected: _selectedVehicle == 2,
                            onTap: () => setState(() => _selectedVehicle = 2),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 20.h),

                    // CTA button
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20.w),
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: AppColors.ctaGradient,
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(18.r),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primaryDark.withOpacity(0.35),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _showDestinationSearch,
                            borderRadius: BorderRadius.circular(18.r),
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                vertical: 16.h,
                                horizontal: 8.w,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.local_taxi_rounded,
                                    size: 22.sp,
                                    color: Colors.white,
                                  ),
                                  SizedBox(width: 10.w),
                                  Text(
                                    AppStrings.orderRide,
                                    style: GoogleFonts.poppins(
                                      fontSize: 16.sp,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.2,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(width: 8.w),
                                  Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 18.sp,
                                    color: Colors.white.withOpacity(0.8),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 16.h),
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
          borderRadius: BorderRadius.circular(14.r),
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
        width: 130.w,
        padding: EdgeInsets.all(14.w),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withOpacity(0.08) : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(18.r),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36.w,
              height: 36.w,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary.withOpacity(0.15)
                    : Colors.white,
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Icon(
                icon,
                size: 20.sp,
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
                color: isSelected ? AppColors.primary : AppColors.textPrimary,
              ),
            ),
            Text(
              subtitle,
              style: GoogleFonts.poppins(
                fontSize: 11.sp,
                color: AppColors.textHint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
