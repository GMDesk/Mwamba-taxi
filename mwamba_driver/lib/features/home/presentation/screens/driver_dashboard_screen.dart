import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_alert.dart';

class DriverDashboardScreen extends StatefulWidget {
  const DriverDashboardScreen({super.key});

  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen>
    with SingleTickerProviderStateMixin {
  final ApiClient _api = getIt<ApiClient>();
  bool _isOnline = false;
  bool _toggling = false;
  WebSocketChannel? _ws;
  Map<String, dynamic>? _pendingRequest;

  // Map
  GoogleMapController? _mapController;
  LatLng _currentPosition = const LatLng(-4.3250, 15.3222);
  StreamSubscription<Position>? _positionSub;

  // Profile & stats
  String _driverName = '';
  double _rating = 5.0;
  int _todayRides = 0;
  String _todayEarnings = '0';
  String _accountStatus = 'pending';
  bool _loadingStats = true;

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _loadDashboardData();
    _initLocation();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _positionSub?.cancel();
    _disconnectWebSocket();
    _mapController?.dispose();
    super.dispose();
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

  Future<void> _loadDashboardData() async {
    try {
      final profileFuture = _api.dio.get(ApiConstants.profile);
      final driverProfileFuture = _api.dio.get(ApiConstants.driverProfile);
      final earningsFuture = _api.dio.get(ApiConstants.earnings).catchError((e) {
        return Response(requestOptions: RequestOptions(), data: null);
      });

      final results = await Future.wait([profileFuture, driverProfileFuture, earningsFuture]);

      final profile = results[0].data;
      final driverProfile = results[1].data;
      final earnings = results[2].data;

      if (mounted) {
        setState(() {
          _driverName = profile?['full_name'] ?? 'Chauffeur';
          _rating = double.tryParse(
                  driverProfile?['rating_average']?.toString() ?? '5.0') ??
              5.0;
          _todayRides = driverProfile?['total_rides'] ?? 0;
          _accountStatus = driverProfile?['status'] ?? 'pending';
          _isOnline = driverProfile?['is_online'] ?? false;
          if (earnings != null) {
            _todayEarnings =
                earnings['today']?.toString() ?? earnings['total']?.toString() ?? '0';
          }
          _loadingStats = false;
        });
        if (_isOnline) {
          _connectWebSocket();
          _startLocationUpdates();
        }
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(() => _loadingStats = false);
        AppAlert.showDioError(context, e,
          fallback: 'Impossible de charger vos donn\u00e9es.',
          title: 'Chargement',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _loadingStats = false);
    }
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
        _connectWebSocket();
        _startLocationUpdates();
      } else {
        _disconnectWebSocket();
        _stopLocationUpdates();
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
    } catch (_) {
      setState(() => _pendingRequest = null);
    }
  }

  void _declineRide() => setState(() => _pendingRequest = null);

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          children: [
            Column(
              children: [
                _buildDarkHeader(),
                if (_accountStatus != 'approved') _buildStatusBanner(),
                Expanded(
                  child: GoogleMap(
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
                ),
              ],
            ),
            _buildBottomPanel(),
            if (_pendingRequest != null) _buildRideRequestOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildDarkHeader() {
    final firstName = _driverName.split(' ').first;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: AppColors.darkGradient,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 12.h),
          child: Row(
            children: [
              Container(
                width: 40.w,
                height: 40.w,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12.r),
                  child: Image.asset(
                    'assets/images/logo.png',
                    width: 40.w,
                    height: 40.w,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.local_taxi_rounded,
                      color: AppColors.primary,
                      size: 22.sp,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Mwamba Driver',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      firstName,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 12.sp,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: _toggling ? null : _toggleOnline,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
                  decoration: BoxDecoration(
                    color: _isOnline
                        ? AppColors.primary.withOpacity(0.15)
                        : Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(24.r),
                    border: Border.all(
                      color: _isOnline
                          ? AppColors.primary.withOpacity(0.4)
                          : Colors.white.withOpacity(0.15),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_toggling)
                        SizedBox(
                          width: 14.sp,
                          height: 14.sp,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _isOnline ? AppColors.primary : Colors.white70,
                          ),
                        )
                      else
                        Container(
                          width: 10.w,
                          height: 10.w,
                          decoration: BoxDecoration(
                            color: _isOnline ? AppColors.online : AppColors.offline,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: (_isOnline ? AppColors.online : AppColors.offline)
                                    .withOpacity(0.5),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                      SizedBox(width: 8.w),
                      Text(
                        _isOnline ? 'EN LIGNE' : 'HORS LIGNE',
                        style: TextStyle(
                          color: _isOnline ? AppColors.primary : Colors.white70,
                          fontSize: 11.sp,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: 8.w),
              Container(
                width: 38.w,
                height: 38.w,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: AppColors.ctaGradient),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Center(
                  child: Text(
                    firstName.isNotEmpty ? firstName[0].toUpperCase() : 'M',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBanner() {
    IconData icon;
    Color color;
    String text;

    switch (_accountStatus) {
      case 'pending':
        icon = Icons.hourglass_top_rounded;
        color = AppColors.warning;
        text = 'Compte en cours de v\u00e9rification';
        break;
      case 'rejected':
        icon = Icons.cancel_outlined;
        color = AppColors.error;
        text = 'Votre compte a \u00e9t\u00e9 rejet\u00e9';
        break;
      case 'suspended':
        icon = Icons.block_rounded;
        color = AppColors.error;
        text = 'Votre compte est suspendu';
        break;
      default:
        return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
      color: color.withOpacity(0.1),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18.sp),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontSize: 12.sp, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPanel() {
    return DraggableScrollableSheet(
      initialChildSize: 0.38,
      minChildSize: 0.18,
      maxChildSize: 0.55,
      snap: true,
      snapSizes: const [0.18, 0.38, 0.55],
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.zero,
            children: [
              Center(
                child: Container(
                  margin: EdgeInsets.only(top: 10.h, bottom: 12.h),
                  width: 40.w,
                  height: 4.h,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2.r),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: Row(
                  children: [
                    _buildMiniStat(
                      icon: Icons.account_balance_wallet_rounded,
                      value: _loadingStats ? '\u2014' : '$_todayEarnings CDF',
                      label: 'Recettes',
                      color: AppColors.primary,
                    ),
                    SizedBox(width: 12.w),
                    _buildMiniStat(
                      icon: Icons.local_taxi_rounded,
                      value: _loadingStats ? '\u2014' : '$_todayRides',
                      label: 'Courses',
                      color: AppColors.info,
                    ),
                    SizedBox(width: 12.w),
                    _buildMiniStat(
                      icon: Icons.star_rounded,
                      value: _loadingStats ? '\u2014' : _rating.toStringAsFixed(1),
                      label: 'Note',
                      color: AppColors.starFilled,
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16.h),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: _pendingRequest != null
                    ? _buildNextRideCard()
                    : _buildWaitingCard(),
              ),
              SizedBox(height: 16.h),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: GestureDetector(
                  onTap: () => context.push('/history'),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(14.r),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.history_rounded, color: AppColors.textSecondary, size: 20.sp),
                        SizedBox(width: 10.w),
                        Text(
                          'Voir l\'historique des courses',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Spacer(),
                        Icon(Icons.chevron_right_rounded, color: AppColors.textHint, size: 20.sp),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(height: 20.h),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMiniStat({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 14.h, horizontal: 10.w),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14.r),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20.sp),
            SizedBox(height: 6.h),
            Text(
              value,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14.sp,
                fontWeight: FontWeight.w800,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: 2.h),
            Text(
              label,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10.sp,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaitingCard() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final opacity = _isOnline ? 0.6 + (_pulseController.value * 0.4) : 1.0;
        return Opacity(
          opacity: opacity,
          child: Container(
            padding: EdgeInsets.all(20.w),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _isOnline
                    ? AppColors.darkGradient
                    : [Colors.grey.shade100, Colors.grey.shade200],
              ),
              borderRadius: BorderRadius.circular(20.r),
            ),
            child: Row(
              children: [
                Container(
                  width: 52.w,
                  height: 52.w,
                  decoration: BoxDecoration(
                    color: _isOnline
                        ? AppColors.primary.withOpacity(0.15)
                        : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(16.r),
                  ),
                  child: Icon(
                    _isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                    color: _isOnline ? AppColors.primary : Colors.grey.shade500,
                    size: 26.sp,
                  ),
                ),
                SizedBox(width: 14.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isOnline
                            ? 'En attente de courses...'
                            : 'Vous \u00eates hors ligne',
                        style: TextStyle(
                          color: _isOnline ? Colors.white : AppColors.textPrimary,
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        _isOnline
                            ? 'Restez disponible pour recevoir des demandes'
                            : 'Passez en ligne pour recevoir des courses',
                        style: TextStyle(
                          color: _isOnline
                              ? Colors.white.withOpacity(0.6)
                              : AppColors.textSecondary,
                          fontSize: 12.sp,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNextRideCard() {
    final ride = _pendingRequest!;
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8.r),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Icon(Icons.local_taxi_rounded, color: AppColors.primary, size: 20.sp),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Text(
                  AppStrings.newRideRequest,
                  style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700),
                ),
              ),
              if (ride['estimated_fare'] != null)
                Text(
                  '${ride['estimated_fare']} CDF',
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
            ],
          ),
          SizedBox(height: 12.h),
          _routePoint(
            icon: Icons.circle,
            iconSize: 8,
            iconColor: AppColors.primary,
            bgColor: AppColors.primary.withOpacity(0.1),
            label: 'D\u00e9part',
            address: ride['pickup_address'] ?? 'Point de d\u00e9part',
          ),
          Padding(
            padding: EdgeInsets.only(left: 15.w),
            child: Column(
              children: List.generate(
                3,
                (_) => Container(
                  width: 2, height: 3.h,
                  margin: EdgeInsets.symmetric(vertical: 1.h),
                  color: Colors.grey.shade300,
                ),
              ),
            ),
          ),
          _routePoint(
            icon: Icons.location_on_rounded,
            iconSize: 14,
            iconColor: AppColors.error,
            bgColor: AppColors.error.withOpacity(0.1),
            label: 'Destination',
            address: ride['dropoff_address'] ?? 'Destination',
          ),
          SizedBox(height: 14.h),
          Row(
            children: [
              GestureDetector(
                onTap: _declineRide,
                child: Container(
                  width: 48.w,
                  height: 48.w,
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14.r),
                    border: Border.all(color: AppColors.error.withOpacity(0.2)),
                  ),
                  child: Icon(Icons.close_rounded, color: AppColors.error, size: 22.sp),
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: GestureDetector(
                  onTap: () => _acceptRide(ride['id']),
                  child: Container(
                    height: 48.w,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: AppColors.ctaGradient),
                      borderRadius: BorderRadius.circular(14.r),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryDark.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_rounded, color: Colors.white, size: 20.sp),
                        SizedBox(width: 8.w),
                        Text(
                          'ACCEPTER LA COURSE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
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
    );
  }

  Widget _buildRideRequestOverlay() {
    final ride = _pendingRequest!;
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.6),
        child: Center(
          child: Container(
            margin: EdgeInsets.symmetric(horizontal: 20.w),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24.r),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryDark.withOpacity(0.2),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: AppColors.ctaGradient),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44.w,
                        height: 44.w,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(14.r),
                        ),
                        child: Icon(Icons.local_taxi_rounded,
                            color: Colors.white, size: 24.sp),
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
                                  fontSize: 24.sp,
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
                Padding(
                  padding: EdgeInsets.fromLTRB(20.w, 18.h, 20.w, 20.h),
                  child: Column(
                    children: [
                      _routePoint(
                        icon: Icons.circle,
                        iconSize: 10,
                        iconColor: AppColors.primary,
                        bgColor: AppColors.primary.withOpacity(0.12),
                        label: 'D\u00e9part',
                        address: ride['pickup_address'] ?? 'Point de d\u00e9part',
                      ),
                      Padding(
                        padding: EdgeInsets.only(left: 15.w),
                        child: Column(
                          children: List.generate(
                            3,
                            (_) => Container(
                              width: 2,
                              height: 4.h,
                              margin: EdgeInsets.symmetric(vertical: 1.h),
                              color: Colors.grey.shade300,
                            ),
                          ),
                        ),
                      ),
                      _routePoint(
                        icon: Icons.location_on_rounded,
                        iconSize: 16,
                        iconColor: AppColors.error,
                        bgColor: AppColors.error.withOpacity(0.12),
                        label: 'Destination',
                        address: ride['dropoff_address'] ?? 'Destination',
                      ),
                      SizedBox(height: 20.h),
                      Row(
                        children: [
                          GestureDetector(
                            onTap: _declineRide,
                            child: Container(
                              width: 54.w,
                              height: 54.w,
                              decoration: BoxDecoration(
                                color: AppColors.error.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(16.r),
                                border: Border.all(color: AppColors.error.withOpacity(0.2)),
                              ),
                              child: Icon(Icons.close_rounded,
                                  color: AppColors.error, size: 24.sp),
                            ),
                          ),
                          SizedBox(width: 12.w),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => _acceptRide(ride['id']),
                              child: Container(
                                height: 54.w,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: AppColors.ctaGradient,
                                  ),
                                  borderRadius: BorderRadius.circular(16.r),
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
                                    Icon(Icons.check_rounded,
                                        color: Colors.white, size: 22.sp),
                                    SizedBox(width: 8.w),
                                    Text(
                                      'ACCEPTER LA COURSE',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15.sp,
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
        ),
      ),
    );
  }

  Widget _routePoint({
    required IconData icon,
    required double iconSize,
    required Color iconColor,
    required Color bgColor,
    required String label,
    required String address,
  }) {
    return Row(
      children: [
        Container(
          width: 32.w,
          height: 32.w,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(10.r),
          ),
          child: Icon(icon, size: iconSize.sp, color: iconColor),
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
