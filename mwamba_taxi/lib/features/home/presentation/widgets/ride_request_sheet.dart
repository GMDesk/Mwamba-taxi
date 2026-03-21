import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/constants/app_strings.dart';

class RideRequestSheet extends StatelessWidget {
  final String pickupAddress;
  final String destinationAddress;
  final Map<String, dynamic> priceEstimate;
  final VoidCallback onConfirm;

  const RideRequestSheet({
    super.key,
    required this.pickupAddress,
    required this.destinationAddress,
    required this.priceEstimate,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final price = priceEstimate['estimated_price'];
    final distance = priceEstimate['distance_km'];
    final duration = priceEstimate['estimated_duration_minutes'];

    return Container(
      padding: EdgeInsets.fromLTRB(24.w, 16.h, 24.w, 28.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2.r),
              ),
            ),
          ),
          SizedBox(height: 20.h),

          // Route info
          Row(
            children: [
              Column(
                children: [
                  Icon(Icons.circle, color: AppColors.primary, size: 12.sp),
                  Container(
                    width: 2,
                    height: 30.h,
                    color: AppColors.border,
                  ),
                  Icon(Icons.location_on, color: AppColors.error, size: 16.sp),
                ],
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pickupAddress,
                      style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 20.h),
                    Text(
                      destinationAddress,
                      style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 20.h),

          // Divider
          const Divider(),
          SizedBox(height: 12.h),

          // Price & details
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _InfoChip(
                icon: Icons.attach_money,
                label: '$price CDF',
                subtitle: AppStrings.estimatedPrice,
              ),
              _InfoChip(
                icon: Icons.straighten,
                label: '$distance km',
                subtitle: 'Distance',
              ),
              _InfoChip(
                icon: Icons.access_time,
                label: '$duration min',
                subtitle: 'Durée',
              ),
            ],
          ),
          SizedBox(height: 24.h),

          // Confirm button — ambre accrocheur
          SizedBox(
            width: double.infinity,
            height: 56.h,
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: AppColors.ctaGradient,
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(18.r),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryDark.withOpacity(0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onConfirm,
                  borderRadius: BorderRadius.circular(18.r),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.local_taxi_rounded,
                        color: AppColors.textOnSecondary,
                        size: 22.sp,
                      ),
                      SizedBox(width: 10.w),
                      Text(
                        AppStrings.requestRide,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16.sp,
                          letterSpacing: 0.2,
                          color: AppColors.textOnSecondary,
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

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(10.w),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12.r),
          ),
          child: Icon(icon, color: AppColors.primaryDark, size: 22.sp),
        ),
        SizedBox(height: 4.h),
        Text(
          label,
          style: TextStyle(
            fontSize: 16.sp,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 11.sp,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
