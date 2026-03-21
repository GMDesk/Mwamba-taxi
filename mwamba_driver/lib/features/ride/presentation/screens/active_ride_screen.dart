import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:dio/dio.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/widgets/app_alert.dart';

class ActiveRideScreen extends StatefulWidget {
  final String rideId;

  const ActiveRideScreen({super.key, required this.rideId});

  @override
  State<ActiveRideScreen> createState() => _ActiveRideScreenState();
}

class _ActiveRideScreenState extends State<ActiveRideScreen> {
  final ApiClient _api = getIt<ApiClient>();
  GoogleMapController? _mapController;
  WebSocketChannel? _ws;
  StreamSubscription<Position>? _positionSub;

  Map<String, dynamic>? _rideData;
  LatLng? _pickupLatLng;
  LatLng? _dropoffLatLng;
  LatLng _currentPosition = const LatLng(-4.3250, 15.3222);
  bool _loading = true;
  String _status = 'accepted';

  @override
  void initState() {
    super.initState();
    _loadRide();
    _startTracking();
    _connectWebSocket();
  }

  Future<void> _loadRide() async {
    try {
      final resp = await _api.dio.get(ApiConstants.rideDetail(widget.rideId));
      final data = resp.data;
      setState(() {
        _rideData = data;
        _status = data['status'];
        _pickupLatLng = LatLng(
          double.parse(data['pickup_lat'].toString()),
          double.parse(data['pickup_lng'].toString()),
        );
        _dropoffLatLng = LatLng(
          double.parse(data['dropoff_lat'].toString()),
          double.parse(data['dropoff_lng'].toString()),
        );
        _loading = false;
      });

      _mapController?.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(
              _pickupLatLng!.latitude < _dropoffLatLng!.latitude
                  ? _pickupLatLng!.latitude
                  : _dropoffLatLng!.latitude,
              _pickupLatLng!.longitude < _dropoffLatLng!.longitude
                  ? _pickupLatLng!.longitude
                  : _dropoffLatLng!.longitude,
            ),
            northeast: LatLng(
              _pickupLatLng!.latitude > _dropoffLatLng!.latitude
                  ? _pickupLatLng!.latitude
                  : _dropoffLatLng!.latitude,
              _pickupLatLng!.longitude > _dropoffLatLng!.longitude
                  ? _pickupLatLng!.longitude
                  : _dropoffLatLng!.longitude,
            ),
          ),
          80,
        ),
      );
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

  void _startTracking() {
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15,
      ),
    ).listen((pos) {
      setState(() => _currentPosition = LatLng(pos.latitude, pos.longitude));

      // Send driver location to ride location log
      _api.dio.post(ApiConstants.rideLocation(widget.rideId), data: {
        'latitude': pos.latitude,
        'longitude': pos.longitude,
      }).ignore();
    });
  }

  void _connectWebSocket() async {
    final token = await _api.getAccessToken();
    if (token == null) return;

    _ws = WebSocketChannel.connect(
      Uri.parse('${ApiConstants.wsBaseUrl}/ride/${widget.rideId}/?token=$token'),
    );

    _ws!.stream.listen(
      (data) {
        final msg = jsonDecode(data);
        if (msg['type'] == 'status_update') {
          setState(() {
            _status = msg['data']['status'] ?? _status;
          });
        } else if (msg['type'] == 'location_update') {
          // Passenger location update — could be used for map display
        }
      },
      onDone: () {
        if (mounted && _status != 'completed' && _status != 'cancelled') {
          Future.delayed(const Duration(seconds: 3), _connectWebSocket);
        }
      },
    );
  }

  Future<void> _startRide() async {
    try {
      await _api.dio.post(ApiConstants.startRide(widget.rideId));
      setState(() => _status = 'in_progress');
    } on DioException catch (e) {
      if (mounted) {
        AppAlert.showDioError(context, e,
          fallback: 'Impossible de démarrer la course.',
          title: 'Démarrage échoué',
        );
      }
    } catch (e) {
      if (mounted) {
        AppAlert.showError(context, e, fallback: 'Impossible de démarrer la course.');
      }
    }
  }

  Future<void> _completeRide() async {
    try {
      await _api.dio.post(ApiConstants.completeRide(widget.rideId));
      setState(() => _status = 'completed');
      if (mounted) {
        await AppAlert.showSuccess(context,
          message: 'La course est terminée avec succès !',
          title: 'Course terminée',
        );
        if (mounted) context.go('/home');
      }
    } on DioException catch (e) {
      if (mounted) {
        AppAlert.showDioError(context, e,
          fallback: 'Impossible de terminer la course.',
          title: 'Erreur de finalisation',
        );
      }
    } catch (e) {
      if (mounted) {
        AppAlert.showError(context, e, fallback: 'Impossible de terminer la course.');
      }
    }
  }

  Future<void> _arrivedAtPickup() async {
    try {
      setState(() => _status = 'driver_arrived');
    } on DioException catch (e) {
      if (mounted) {
        AppAlert.showDioError(context, e,
          fallback: 'Impossible de notifier le passager de votre arrivée.',
        );
      }
    } catch (_) {}
  }

  Future<void> _cancelRide() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Annuler la course ?'),
        content: const Text('Êtes-vous sûr de vouloir annuler cette course ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Non')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Oui')),
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
          title: 'Annulation échouée',
        );
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _ws?.sink.close();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final markers = <Marker>{};
    if (_pickupLatLng != null) {
      markers.add(Marker(
        markerId: const MarkerId('pickup'),
        position: _pickupLatLng!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'Prise en charge'),
      ));
    }
    if (_dropoffLatLng != null) {
      markers.add(Marker(
        markerId: const MarkerId('dropoff'),
        position: _dropoffLatLng!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: 'Destination'),
      ));
    }

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _pickupLatLng ?? _currentPosition,
              zoom: 14,
            ),
            onMapCreated: (c) => _mapController = c,
            markers: markers,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
          ),

          // Back button
          Positioned(
            top: MediaQuery.of(context).padding.top + 12.h,
            left: 16.w,
            child: Material(
              elevation: 4,
              shape: const CircleBorder(),
              color: AppColors.surface,
              child: InkWell(
                onTap: () => context.go('/home'),
                customBorder: const CircleBorder(),
                child: Padding(
                  padding: EdgeInsets.all(12.w),
                  child: const Icon(Icons.arrow_back),
                ),
              ),
            ),
          ),

          // Bottom panel
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomPanel(),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPanel() {
    return Container(
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
        boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 20)],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Status indicator
            Container(
              width: 40.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2.r),
              ),
            ),
            SizedBox(height: 16.h),

            // Passenger info
            if (_rideData != null) ...[
              Row(
                children: [
                  CircleAvatar(
                    radius: 24.r,
                    backgroundColor: AppColors.primary.withOpacity(0.15),
                    child: Icon(Icons.person, color: AppColors.primary, size: 28.sp),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _rideData!['passenger_name'] ?? 'Passager',
                          style: TextStyle(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          _statusLabel(),
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${_rideData!['estimated_fare'] ?? '—'} CDF',
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12.h),

              // Addresses
              _AddressRow(
                icon: Icons.circle,
                color: AppColors.primary,
                text: _rideData!['pickup_address'] ?? 'Prise en charge',
              ),
              SizedBox(height: 6.h),
              _AddressRow(
                icon: Icons.location_on,
                color: AppColors.error,
                text: _rideData!['dropoff_address'] ?? 'Destination',
              ),
            ],

            SizedBox(height: 20.h),

            // Action Button
            _buildActionButton(),

            SizedBox(height: 8.h),

            // Cancel
            if (_status != 'completed' && _status != 'cancelled')
              TextButton(
                onPressed: _cancelRide,
                child: const Text(
                  'Annuler la course',
                  style: TextStyle(color: AppColors.error),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton() {
    switch (_status) {
      case 'accepted':
        return ElevatedButton.icon(
          onPressed: _arrivedAtPickup,
          icon: const Icon(Icons.flag),
          label: const Text('Je suis arrivé'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.info,
            minimumSize: Size(double.infinity, 52.h),
          ),
        );
      case 'driver_arrived':
        return ElevatedButton.icon(
          onPressed: _startRide,
          icon: const Icon(Icons.play_arrow),
          label: const Text(AppStrings.startRide),
          style: ElevatedButton.styleFrom(
            minimumSize: Size(double.infinity, 52.h),
          ),
        );
      case 'in_progress':
        return ElevatedButton.icon(
          onPressed: _completeRide,
          icon: const Icon(Icons.check_circle),
          label: const Text(AppStrings.completeRide),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.success,
            minimumSize: Size(double.infinity, 52.h),
          ),
        );
      case 'completed':
        return ElevatedButton(
          onPressed: () => context.go('/home'),
          child: const Text('Retour à l\'accueil'),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  String _statusLabel() {
    switch (_status) {
      case 'accepted': return 'En route vers le passager';
      case 'driver_arrived': return 'Arrivé au point de prise en charge';
      case 'in_progress': return 'Course en cours';
      case 'completed': return 'Course terminée';
      case 'cancelled': return 'Course annulée';
      default: return _status;
    }
  }
}

class _AddressRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _AddressRow({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 10.sp, color: color),
        SizedBox(width: 8.w),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13.sp),
          ),
        ),
      ],
    );
  }
}
