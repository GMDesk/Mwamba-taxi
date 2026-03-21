import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
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
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 12.h),
              child: Text(
                AppStrings.tabActivity,
                style: GoogleFonts.poppins(
                  fontSize: 26.sp,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ),

            // Subtitle
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              child: Text(
                'Vos courses récentes',
                style: GoogleFonts.poppins(
                  fontSize: 14.sp,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            SizedBox(height: 16.h),

            // Body
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _buildError()
                      : _rides.isEmpty
                          ? _buildEmpty()
                          : RefreshIndicator(
                              onRefresh: _loadHistory,
                              color: AppColors.primary,
                              child: ListView.separated(
                                padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 24.h),
                                itemCount: _rides.length,
                                separatorBuilder: (_, __) => SizedBox(height: 12.h),
                                itemBuilder: (context, index) {
                                  final ride = _rides[index];
                                  return _ActivityCard(ride: ride);
                                },
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_rounded, size: 48.sp, color: AppColors.textHint),
          SizedBox(height: 12.h),
          Text(_error!, style: GoogleFonts.poppins(fontSize: 15.sp, color: AppColors.textSecondary)),
          SizedBox(height: 16.h),
          OutlinedButton(onPressed: _loadHistory, child: const Text('Réessayer')),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
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
            child: Icon(Icons.receipt_long_rounded, size: 40.sp, color: AppColors.primary),
          ),
          SizedBox(height: 20.h),
          Text(
            'Aucune activité',
            style: GoogleFonts.poppins(fontSize: 18.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          ),
          SizedBox(height: 6.h),
          Text(
            'Vos courses apparaîtront ici',
            style: GoogleFonts.poppins(fontSize: 14.sp, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  final Map<String, dynamic> ride;
  const _ActivityCard({required this.ride});

  @override
  Widget build(BuildContext context) {
    final status = ride['status'] ?? '';
    final fare = ride['final_fare'] ?? ride['estimated_fare'];
    final createdAt = ride['created_at'] != null
        ? DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(ride['created_at']).toLocal())
        : '';
    final pickup = ride['pickup_address'] ?? '';
    final destination = ride['destination_address'] ?? '';

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18.r),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
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
                style: GoogleFonts.poppins(fontSize: 12.sp, color: AppColors.textHint, fontWeight: FontWeight.w500),
              ),
              _StatusBadge(status: status),
            ],
          ),
          SizedBox(height: 12.h),

          // Route info
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Icon(Icons.circle, color: AppColors.primary, size: 10.sp),
                  Container(width: 2, height: 24.h, color: AppColors.border),
                  Icon(Icons.location_on, color: AppColors.error, size: 14.sp),
                ],
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pickup,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(fontSize: 13.sp, fontWeight: FontWeight.w500),
                    ),
                    SizedBox(height: 14.h),
                    Text(
                      destination,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(fontSize: 13.sp, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),

          // Fare
          if (fare != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  '$fare CDF',
                  style: GoogleFonts.poppins(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    String label;

    switch (status) {
      case 'completed':
        bg = AppColors.success.withOpacity(0.1);
        fg = AppColors.success;
        label = 'Terminée';
        break;
      case 'cancelled':
        bg = AppColors.error.withOpacity(0.1);
        fg = AppColors.error;
        label = 'Annulée';
        break;
      case 'in_progress':
        bg = AppColors.info.withOpacity(0.1);
        fg = AppColors.info;
        label = 'En cours';
        break;
      default:
        bg = AppColors.warning.withOpacity(0.1);
        fg = AppColors.warning;
        label = status.isNotEmpty ? status : 'En attente';
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(fontSize: 11.sp, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}
