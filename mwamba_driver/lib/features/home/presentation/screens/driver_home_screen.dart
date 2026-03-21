import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/widgets/app_alert.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  final ApiClient _api = getIt<ApiClient>();
  GoogleMapController? _mapController;
  LatLng _currentPosition = const LatLng(-4.3250, 15.3222);
  bool _isOnline = false;
  bool _toggling = false;
  StreamSubscription<Position>? _positionSub;
  WebSocketChannel? _ws;

  Map<String, dynamic>? _pendingRequest;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  Future<void> _initLocation() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      await Geolocator.requestPermission();
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() => _currentPosition = LatLng(pos.latitude, pos.longitude));
      _mapController?.animateCamera(CameraUpdate.newLatLng(_currentPosition));
    } catch (_) {}
  }

  Future<void> _toggleOnline() async {
    setState(() => _toggling = true);
    try {
      final goOnline = !_isOnline;
      await _api.dio.post(
        ApiConstants.updateStatus,
        data: {'is_online': goOnline},
      );
      setState(() => _isOnline = goOnline);

      if (_isOnline) {
        _startLocationUpdates();
        _connectWebSocket();
      } else {
        _stopLocationUpdates();
        _disconnectWebSocket();
      }
    } on DioException catch (e) {
      if (mounted) {
        AppAlert.showDioError(context, e,
          fallback: 'Impossible de changer votre statut.',
          title: 'Changement de statut',
        );
      }
    } catch (e) {
      if (mounted) {
        AppAlert.showError(context, e,
          fallback: 'Impossible de changer votre statut.',
        );
      }
    }
    setState(() => _toggling = false);
  }

  void _startLocationUpdates() {
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 20,
      ),
    ).listen((pos) {
      setState(() => _currentPosition = LatLng(pos.latitude, pos.longitude));
      _mapController?.animateCamera(CameraUpdate.newLatLng(_currentPosition));
      _api.dio.post(ApiConstants.updateLocation, data: {
        'latitude': pos.latitude,
        'longitude': pos.longitude,
      }).ignore();
    });
  }

  void _stopLocationUpdates() {
    _positionSub?.cancel();
    _positionSub = null;
  }

  void _connectWebSocket() async {
    final token = await _api.getAccessToken();
    if (token == null) return;

    _ws = WebSocketChannel.connect(
      Uri.parse('${ApiConstants.wsBaseUrl}/driver/?token=$token'),
    );

    _ws!.stream.listen(
      (data) {
        final msg = jsonDecode(data);
        if (msg['type'] == 'ride_request') {
          setState(() => _pendingRequest = msg['data']);
        }
      },
      onDone: () {
        if (_isOnline && mounted) {
          Future.delayed(const Duration(seconds: 3), _connectWebSocket);
        }
      },
    );
  }

  void _disconnectWebSocket() {
    _ws?.sink.close();
    _ws = null;
  }

  Future<void> _acceptRide(String rideId) async {
    try {
      await _api.dio.post(ApiConstants.acceptRide(rideId));
      setState(() => _pendingRequest = null);
      if (mounted) context.go('/ride/$rideId');
    } on DioException catch (e) {
      setState(() => _pendingRequest = null);
      if (mounted) {
        AppAlert.showDioError(context, e,
          fallback: 'Cette course a d\u00e9j\u00e0 \u00e9t\u00e9 accept\u00e9e par un autre chauffeur.',
          title: 'Course indisponible',
        );
      }
    } catch (e) {
      setState(() => _pendingRequest = null);
      if (mounted) {
        AppAlert.showError(context, e,
          fallback: 'Impossible d\'accepter la course.',
        );
      }
    }
  }

  void _declineRide() {
    setState(() => _pendingRequest = null);
  }

  @override
  void dispose() {
    _stopLocationUpdates();
    _disconnectWebSocket();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Full-screen map
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _currentPosition,
              zoom: 15,
            ),
            onMapCreated: (c) => _mapController = c,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
          ),

          // Top bar with status badge
          SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
              child: Row(
                children: [
                  const Spacer(),
                  // Online status badge
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20.r),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                        decoration: BoxDecoration(
                          color: (_isOnline ? AppColors.online : AppColors.offline).withOpacity(0.85),
                          borderRadius: BorderRadius.circular(20.r),
                          border: Border.all(color: Colors.white.withOpacity(0.2)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8.w,
                              height: 8.w,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.white.withOpacity(0.5),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(width: 8.w),
                            Text(
                              _isOnline ? AppStrings.online : AppStrings.offline,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13.sp,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Recenter button
          Positioned(
            bottom: 100.h,
            right: 16.w,
            child: GestureDetector(
              onTap: () {
                _mapController?.animateCamera(
                  CameraUpdate.newLatLng(_currentPosition),
                );
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
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(Icons.my_location_rounded, color: AppColors.primary, size: 22.sp),
              ),
            ),
          ),

          // Online/Offline toggle
          Positioned(
            bottom: 32.h,
            left: 24.w,
            right: 24.w,
            child: GestureDetector(
              onTap: _toggling ? null : _toggleOnline,
              child: Container(
                height: 56.h,
                decoration: BoxDecoration(
                  gradient: _isOnline
                      ? null
                      : const LinearGradient(
                          colors: [AppColors.primaryDark, AppColors.primary],
                        ),
                  color: _isOnline ? AppColors.offline : null,
                  borderRadius: BorderRadius.circular(18.r),
                  boxShadow: [
                    BoxShadow(
                      color: (_isOnline ? AppColors.offline : AppColors.primaryDark)
                          .withOpacity(0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _toggling
                        ? SizedBox(
                            width: 22.sp,
                            height: 22.sp,
                            child: const CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : Icon(Icons.power_settings_new,
                            color: Colors.white, size: 24.sp),
                    SizedBox(width: 10.w),
                    Text(
                      _isOnline ? AppStrings.goOffline : AppStrings.goOnline,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Pending Ride Request overlay
          if (_pendingRequest != null) _buildRideRequestOverlay(),
        ],
      ),
    );
  }

  Widget _buildRideRequestOverlay() {
    final ride = _pendingRequest!;
    return Positioned(
      bottom: 108.h,
      left: 16.w,
      right: 16.w,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24.r),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryDark.withOpacity(0.15),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 14.h),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primaryDark, AppColors.primary],
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40.w,
                    height: 40.w,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Icon(Icons.local_taxi_rounded, color: Colors.white, size: 22.sp),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppStrings.newRideRequest,
                          style: TextStyle(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        if (ride['estimated_fare'] != null)
                          Text(
                            '${ride['estimated_fare']} CDF',
                            style: TextStyle(
                              fontSize: 22.sp,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (ride['distance_km'] != null)
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                      child: Text(
                        '${ride['distance_km']} km',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Route
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 14.h, 20.w, 16.h),
              child: Column(
                children: [
                  _buildRouteRow(
                    icon: Icons.circle,
                    iconSize: 10,
                    color: AppColors.primary,
                    label: 'D\u00e9part',
                    address: ride['pickup_address'] ?? 'Point de d\u00e9part',
                  ),
                  Padding(
                    padding: EdgeInsets.only(left: 15.w),
                    child: Column(
                      children: List.generate(3, (_) => Container(
                        width: 2, height: 4.h,
                        margin: EdgeInsets.symmetric(vertical: 1.h),
                        color: Colors.grey.shade300,
                      )),
                    ),
                  ),
                  _buildRouteRow(
                    icon: Icons.location_on_rounded,
                    iconSize: 16,
                    color: AppColors.error,
                    label: 'Destination',
                    address: ride['dropoff_address'] ?? 'Destination',
                  ),
                  SizedBox(height: 16.h),
                  // Actions
                  Row(
                    children: [
                      GestureDetector(
                        onTap: _declineRide,
                        child: Container(
                          width: 52.w,
                          height: 52.w,
                          decoration: BoxDecoration(
                            color: AppColors.error.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(14.r),
                            border: Border.all(color: AppColors.error.withOpacity(0.2)),
                          ),
                          child: Icon(Icons.close_rounded, color: AppColors.error, size: 24.sp),
                        ),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _acceptRide(ride['id']),
                          child: Container(
                            height: 52.w,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [AppColors.primaryDark, AppColors.primary],
                              ),
                              borderRadius: BorderRadius.circular(14.r),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primaryDark.withOpacity(0.35),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.check_rounded, color: Colors.white, size: 22.sp),
                                SizedBox(width: 8.w),
                                Text(
                                  AppStrings.accept,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16.sp,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRouteRow({
    required IconData icon,
    required double iconSize,
    required Color color,
    required String label,
    required String address,
  }) {
    return Row(
      children: [
        Container(
          width: 32.w,
          height: 32.w,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10.r),
          ),
          child: Icon(icon, size: iconSize.sp, color: color),
        ),
        SizedBox(width: 12.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.sp,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                address,
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
