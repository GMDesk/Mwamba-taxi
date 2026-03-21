import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';

class RideHistoryScreen extends StatefulWidget {
  const RideHistoryScreen({super.key});

  @override
  State<RideHistoryScreen> createState() => _RideHistoryScreenState();
}

class _RideHistoryScreenState extends State<RideHistoryScreen> {
  final ApiClient _api = getIt<ApiClient>();
  List<dynamic> _rides = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() { _loading = true; _error = null; });
    try {
      final resp = await _api.dio.get(ApiConstants.passengerHistory);
      setState(() {
        _rides = resp.data['results'] ?? resp.data;
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = 'Erreur de chargement'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Custom header
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 16.h),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => context.go('/home'),
                    child: Container(
                      width: 44.w,
                      height: 44.w,
                      decoration: BoxDecoration(
                        color: AppColors.inputFill,
                        borderRadius: BorderRadius.circular(14.r),
                      ),
                      child: const Icon(Icons.arrow_back_ios_new, size: 18),
                    ),
                  ),
                  SizedBox(width: 16.w),
                  Text(
                    'Historique',
                    style: TextStyle(
                      fontSize: 22.sp,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),

            // Body
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.wifi_off_rounded, size: 48.sp, color: AppColors.textHint),
                              SizedBox(height: 12.h),
                              Text(
                                _error!,
                                style: TextStyle(fontSize: 15.sp, color: AppColors.textSecondary),
                              ),
                              SizedBox(height: 16.h),
                              OutlinedButton(
                                onPressed: _loadHistory,
                                child: const Text('Réessayer'),
                              ),
                            ],
                          ),
                        )
                      : _rides.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 80.w,
                                    height: 80.w,
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(24.r),
                                    ),
                                    child: Icon(Icons.history_rounded, size: 40.sp, color: AppColors.primaryDark),
                                  ),
                                  SizedBox(height: 20.h),
                                  Text(
                                    'Aucune course',
                                    style: TextStyle(
                                      fontSize: 18.sp,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  SizedBox(height: 6.h),
                                  Text(
                                    'Vos courses apparaîtront ici',
                                    style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _loadHistory,
                              color: AppColors.primary,
                              child: ListView.separated(
                                padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 24.h),
                                itemCount: _rides.length,
                                separatorBuilder: (_, __) => SizedBox(height: 12.h),
                                itemBuilder: (context, index) {
                                  final ride = _rides[index];
                                  return _RideCard(ride: ride);
                                },
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RideCard extends StatelessWidget {
  final Map<String, dynamic> ride;

  const _RideCard({required this.ride});

  @override
  Widget build(BuildContext context) {
    final status = ride['status'] ?? '';
    final fare = ride['final_fare'] ?? ride['estimated_fare'];
    final createdAt = ride['created_at'] != null
        ? DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(ride['created_at']).toLocal())
        : '';

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18.r),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date & status row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                createdAt,
                style: TextStyle(
                  fontSize: 12.sp,
                  color: AppColors.textHint,
                  fontWeight: FontWeight.w500,
                ),
              ),
              _StatusChip(status: status),
            ],
          ),
          SizedBox(height: 14.h),

          // Route line
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(
                    width: 10.w,
                    height: 10.w,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Container(
                    width: 1.5,
                    height: 28.h,
                    color: AppColors.border,
                  ),
                  Icon(Icons.location_on_rounded, size: 14.sp, color: AppColors.error),
                ],
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ride['pickup_address'] ?? 'Départ',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 18.h),
                    Text(
                      ride['dropoff_address'] ?? 'Arrivée',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Fare
          if (fare != null) ...[
            SizedBox(height: 14.h),
            Divider(color: AppColors.divider, height: 1),
            SizedBox(height: 12.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  '${NumberFormat('#,###').format(double.tryParse(fare.toString()) ?? 0)} CDF',
                  style: TextStyle(
                    fontSize: 17.sp,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDark,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  Color _color() {
    switch (status) {
      case 'completed': return AppColors.success;
      case 'cancelled': return AppColors.error;
      case 'in_progress': return AppColors.primaryDark;
      default: return AppColors.textHint;
    }
  }

  String _label() {
    switch (status) {
      case 'requested': return 'En attente';
      case 'accepted': return 'Acceptée';
      case 'driver_arrived': return 'Chauffeur arrivé';
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
