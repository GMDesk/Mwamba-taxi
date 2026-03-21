import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:dio/dio.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/widgets/app_alert.dart';

class DriverHistoryScreen extends StatefulWidget {
  const DriverHistoryScreen({super.key});

  @override
  State<DriverHistoryScreen> createState() => _DriverHistoryScreenState();
}

class _DriverHistoryScreenState extends State<DriverHistoryScreen> {
  final ApiClient _api = getIt<ApiClient>();
  List<dynamic> _rides = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp = await _api.dio.get(ApiConstants.driverHistory);
      setState(() {
        _rides = resp.data['results'] ?? resp.data;
        _loading = false;
      });
    } on DioException catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        AppAlert.showDioError(context, e,
          fallback: 'Impossible de charger l\'historique des courses.',
          title: 'Historique',
        );
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.rideHistory),
        leading: IconButton(
          onPressed: () => context.go('/home'),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rides.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history, size: 80.sp, color: AppColors.textHint),
                      SizedBox(height: 16.h),
                      Text(
                        'Aucune course effectuée',
                        style: TextStyle(fontSize: 18.sp, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: EdgeInsets.all(16.w),
                    itemCount: _rides.length,
                    separatorBuilder: (_, __) => SizedBox(height: 12.h),
                    itemBuilder: (context, index) {
                      final ride = _rides[index];
                      return _DriverRideCard(ride: ride);
                    },
                  ),
                ),
    );
  }
}

class _DriverRideCard extends StatelessWidget {
  final Map<String, dynamic> ride;

  const _DriverRideCard({required this.ride});

  @override
  Widget build(BuildContext context) {
    final fare = ride['final_fare'] ?? ride['estimated_fare'];
    final commission = ride['commission_amount'];
    final createdAt = ride['created_at'] != null
        ? DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(ride['created_at']).toLocal())
        : '';

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(createdAt, style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
                _StatusBadge(status: ride['status'] ?? ''),
              ],
            ),
            SizedBox(height: 12.h),

            Row(
              children: [
                Icon(Icons.circle, size: 10.sp, color: AppColors.primary),
                SizedBox(width: 8.w),
                Expanded(
                  child: Text(
                    ride['pickup_address'] ?? 'Départ',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.sp),
                  ),
                ),
              ],
            ),
            SizedBox(height: 6.h),
            Row(
              children: [
                Icon(Icons.location_on, size: 10.sp, color: AppColors.error),
                SizedBox(width: 8.w),
                Expanded(
                  child: Text(
                    ride['dropoff_address'] ?? 'Arrivée',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.sp),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12.h),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (commission != null)
                  Text(
                    'Commission: ${NumberFormat('#,###').format(double.tryParse(commission.toString()) ?? 0)} CDF',
                    style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
                  ),
                if (fare != null)
                  Text(
                    '${NumberFormat('#,###').format(double.tryParse(fare.toString()) ?? 0)} CDF',
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  Color _color() {
    switch (status) {
      case 'completed': return AppColors.success;
      case 'cancelled': return AppColors.error;
      case 'in_progress': return AppColors.secondary;
      default: return AppColors.textHint;
    }
  }

  String _label() {
    switch (status) {
      case 'accepted': return 'Acceptée';
      case 'driver_arrived': return 'Arrivé';
      case 'in_progress': return 'En cours';
      case 'completed': return 'Terminée';
      case 'cancelled': return 'Annulée';
      default: return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: _color().withOpacity(0.15),
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: Text(
        _label(),
        style: TextStyle(
          fontSize: 11.sp,
          fontWeight: FontWeight.w600,
          color: _color(),
        ),
      ),
    );
  }
}
