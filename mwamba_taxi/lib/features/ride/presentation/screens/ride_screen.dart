import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';

class RideScreen extends StatefulWidget {
  final String rideId;

  const RideScreen({super.key, required this.rideId});

  @override
  State<RideScreen> createState() => _RideScreenState();
}

class _RideScreenState extends State<RideScreen> {
  final ApiClient _api = getIt<ApiClient>();
  final Completer<GoogleMapController> _mapController = Completer();

  Map<String, dynamic>? _ride;
  WebSocketChannel? _channel;
  final Set<Marker> _markers = {};
  LatLng? _driverPosition;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRide();
    _connectWebSocket();
  }

  Future<void> _loadRide() async {
    try {
      final response = await _api.dio.get(
        ApiConstants.rideDetail(widget.rideId),
      );
      setState(() {
        _ride = response.data;
        _isLoading = false;
      });
      _updateMarkers();
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _connectWebSocket() async {
    final token = await _api.getAccessToken();
    final wsUrl = '${ApiConstants.wsBaseUrl}/ride/${widget.rideId}/?token=$token';

    _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
    _channel!.stream.listen(
      (message) {
        final data = jsonDecode(message);
        if (data['type'] == 'location_update') {
          setState(() {
            _driverPosition = LatLng(
              double.parse(data['latitude'].toString()),
              double.parse(data['longitude'].toString()),
            );
          });
          _updateDriverMarker();
        } else if (data['type'] == 'status_update') {
          _loadRide(); // Reload ride data
        }
      },
      onError: (_) {},
      onDone: () {},
    );
  }

  void _updateMarkers() {
    if (_ride == null) return;

    _markers.clear();

    // Pickup marker
    _markers.add(Marker(
      markerId: const MarkerId('pickup'),
      position: LatLng(
        double.parse(_ride!['pickup_latitude'].toString()),
        double.parse(_ride!['pickup_longitude'].toString()),
      ),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      infoWindow: InfoWindow(title: _ride!['pickup_address']),
    ));

    // Destination marker
    _markers.add(Marker(
      markerId: const MarkerId('destination'),
      position: LatLng(
        double.parse(_ride!['destination_latitude'].toString()),
        double.parse(_ride!['destination_longitude'].toString()),
      ),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      infoWindow: InfoWindow(title: _ride!['destination_address']),
    ));

    setState(() {});
  }

  void _updateDriverMarker() {
    if (_driverPosition == null) return;

    _markers.removeWhere((m) => m.markerId.value == 'driver');
    _markers.add(Marker(
      markerId: const MarkerId('driver'),
      position: _driverPosition!,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
      infoWindow: const InfoWindow(title: 'Votre chauffeur'),
    ));

    setState(() {});
  }

  Future<void> _cancelRide() async {
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
      case 'in_progress':
        return 'Course en cours';
      case 'completed':
        return 'Course terminée';
      default:
        return status ?? 'Chargement...';
    }
  }

  @override
  void dispose() {
    _channel?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = _ride?['status'];
    final isCompleted = status == 'completed';
    final isCancellable = ['requested', 'accepted', 'driver_arriving'].contains(status);

    return Scaffold(
      body: Stack(
        children: [
          // Map
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
            onMapCreated: (c) => _mapController.complete(c),
            markers: _markers,
            myLocationEnabled: true,
            zoomControlsEnabled: false,
          ),

          // Top bar
          SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => context.go('/home'),
                    child: Container(
                      width: 44.w,
                      height: 44.w,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14.r),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.shadow,
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.arrow_back_ios_new, size: 18),
                    ),
                  ),
                  const Spacer(),
                  // SOS Button
                  if (status == 'in_progress')
                    GestureDetector(
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
                      child: Container(
                        width: 44.w,
                        height: 44.w,
                        decoration: BoxDecoration(
                          color: AppColors.error,
                          borderRadius: BorderRadius.circular(14.r),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.error.withOpacity(0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.sos_rounded, color: Colors.white, size: 20),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Bottom info panel
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(24.w, 16.h, 24.w, 28.h),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.shadow.withOpacity(0.08),
                    blurRadius: 24,
                    offset: const Offset(0, -6),
                  ),
                ],
              ),
              child: _isLoading
                  ? Padding(
                      padding: EdgeInsets.symmetric(vertical: 24.h),
                      child: const Center(child: CircularProgressIndicator()),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Handle bar
                        Container(
                          width: 40.w,
                          height: 4.h,
                          decoration: BoxDecoration(
                            color: AppColors.border,
                            borderRadius: BorderRadius.circular(2.r),
                          ),
                        ),
                        SizedBox(height: 16.h),

                        // Status chip
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 18.w,
                            vertical: 8.h,
                          ),
                          decoration: BoxDecoration(
                            color: isCompleted
                                ? AppColors.success.withOpacity(0.1)
                                : AppColors.primary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(24.r),
                          ),
                          child: Text(
                            _getStatusText(status),
                            style: TextStyle(
                              color: isCompleted
                                  ? AppColors.success
                                  : AppColors.primaryDark,
                              fontWeight: FontWeight.w700,
                              fontSize: 14.sp,
                            ),
                          ),
                        ),
                        SizedBox(height: 16.h),

                        // Driver info
                        if (_ride?['driver'] != null) ...[
                          Row(
                            children: [
                              Container(
                                width: 52.w,
                                height: 52.w,
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(16.r),
                                ),
                                child: Icon(Icons.person_rounded, color: AppColors.primaryDark, size: 26.sp),
                              ),
                              SizedBox(width: 14.w),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _ride!['driver']['full_name'] ?? '',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16.sp,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    if (_ride!['driver_vehicle'] != null)
                                      Text(
                                        '${_ride!['driver_vehicle']['make']} ${_ride!['driver_vehicle']['model']} - ${_ride!['driver_vehicle']['license_plate']}',
                                        style: TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 13.sp,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              // Call button
                              Container(
                                width: 46.w,
                                height: 46.w,
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(14.r),
                                ),
                                child: Icon(Icons.phone_rounded, color: AppColors.textOnPrimary, size: 22.sp),
                              ),
                            ],
                          ),
                          SizedBox(height: 16.h),
                        ],

                        // Price row
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 14.h),
                          decoration: BoxDecoration(
                            color: AppColors.inputFill,
                            borderRadius: BorderRadius.circular(16.r),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Prix estimé',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                '${_ride?['estimated_price'] ?? '0'} CDF',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18.sp,
                                  color: AppColors.primaryDark,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 16.h),

                        // Actions
                        if (isCancellable)
                          SizedBox(
                            width: double.infinity,
                            height: 52.h,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.error,
                                side: BorderSide(color: AppColors.error.withOpacity(0.4)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16.r),
                                ),
                              ),
                              onPressed: _cancelRide,
                              child: Text(
                                'Annuler la course',
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15.sp),
                              ),
                            ),
                          ),

                        if (isCompleted)
                          SizedBox(
                            width: double.infinity,
                            height: 56.h,
                            child: ElevatedButton(
                              onPressed: () => context.push(
                                '/ride/${widget.rideId}/rate',
                              ),
                              child: Text(
                                'Noter le chauffeur',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16.sp),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
