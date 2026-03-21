import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_alert.dart';

class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  final ApiClient _api = getIt<ApiClient>();
  Map<String, dynamic>? _earnings;
  bool _loading = true;
  int _selectedFilter = 0; // 0=Jour, 1=Semaine, 2=Mois

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp = await _api.dio.get(ApiConstants.earnings);
      setState(() { _earnings = resp.data; _loading = false; });
    } on DioException catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        AppAlert.showDioError(context, e,
          fallback: 'Impossible de charger vos revenus.',
          title: 'Revenus',
        );
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  String get _currentAmount {
    if (_earnings == null) return '0';
    final fmt = NumberFormat('#,###');
    switch (_selectedFilter) {
      case 0:
        return fmt.format(_earnings!['today'] ?? 0);
      case 1:
        return fmt.format(_earnings!['this_week'] ?? 0);
      case 2:
        return fmt.format(_earnings!['this_month'] ?? 0);
      default:
        return fmt.format(_earnings!['today'] ?? 0);
    }
  }

  String get _filterLabel {
    switch (_selectedFilter) {
      case 0: return 'Aujourd\'hui';
      case 1: return 'Cette semaine';
      case 2: return 'Ce mois';
      default: return 'Aujourd\'hui';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _earnings == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, color: AppColors.textHint, size: 48.sp),
                      SizedBox(height: 12.h),
                      const Text('Erreur de chargement'),
                      SizedBox(height: 12.h),
                      TextButton(
                        onPressed: _load,
                        child: const Text('R\u00e9essayer'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.primary,
                  child: CustomScrollView(
                    slivers: [
                      // Header
                      SliverToBoxAdapter(
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: AppColors.darkGradient,
                            ),
                            borderRadius: BorderRadius.only(
                              bottomLeft: Radius.circular(28),
                              bottomRight: Radius.circular(28),
                            ),
                          ),
                          child: SafeArea(
                            bottom: false,
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 28.h),
                              child: Column(
                                children: [
                                  Text(
                                    'Mes Revenus',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18.sp,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  SizedBox(height: 20.h),
                                  // Filter tabs
                                  Container(
                                    padding: EdgeInsets.all(4.w),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(14.r),
                                    ),
                                    child: Row(
                                      children: [
                                        _buildFilterTab(0, 'Jour'),
                                        _buildFilterTab(1, 'Semaine'),
                                        _buildFilterTab(2, 'Mois'),
                                      ],
                                    ),
                                  ),
                                  SizedBox(height: 24.h),
                                  // Amount
                                  Text(
                                    _filterLabel,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.6),
                                      fontSize: 13.sp,
                                    ),
                                  ),
                                  SizedBox(height: 6.h),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        _currentAmount,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 40.sp,
                                          fontWeight: FontWeight.w800,
                                          height: 1,
                                        ),
                                      ),
                                      Padding(
                                        padding: EdgeInsets.only(bottom: 4.h, left: 6.w),
                                        child: Text(
                                          'CDF',
                                          style: TextStyle(
                                            color: AppColors.primary,
                                            fontSize: 16.sp,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 20.h),
                                  // Mini bar chart
                                  _buildMiniChart(),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Stats grid
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 0),
                        sliver: SliverToBoxAdapter(
                          child: Row(
                            children: [
                              _buildStatTile(
                                icon: Icons.local_taxi_rounded,
                                value: '${_earnings!['total_rides'] ?? 0}',
                                label: 'Courses totales',
                                color: AppColors.info,
                              ),
                              SizedBox(width: 12.w),
                              _buildStatTile(
                                icon: Icons.star_rounded,
                                value: '${(_earnings!['avg_rating'] ?? 0).toStringAsFixed(1)}',
                                label: 'Note moyenne',
                                color: AppColors.starFilled,
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 0),
                        sliver: SliverToBoxAdapter(
                          child: Row(
                            children: [
                              _buildStatTile(
                                icon: Icons.check_circle_rounded,
                                value: '${_earnings!['acceptance_rate'] ?? '\u2014'}%',
                                label: 'Taux acceptation',
                                color: AppColors.success,
                              ),
                              SizedBox(width: 12.w),
                              _buildStatTile(
                                icon: Icons.receipt_long_rounded,
                                value: '${NumberFormat('#,###').format(_earnings!['total_commission'] ?? 0)}',
                                label: 'Commission CDF',
                                color: AppColors.primary,
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Total balance card
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 0),
                        sliver: SliverToBoxAdapter(
                          child: Container(
                            padding: EdgeInsets.all(20.w),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: AppColors.ctaGradient,
                              ),
                              borderRadius: BorderRadius.circular(20.r),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: EdgeInsets.all(12.r),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(14.r),
                                  ),
                                  child: Icon(Icons.account_balance_wallet_rounded,
                                      color: Colors.white, size: 24.sp),
                                ),
                                SizedBox(width: 16.w),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Solde total',
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.8),
                                          fontSize: 13.sp,
                                        ),
                                      ),
                                      SizedBox(height: 4.h),
                                      Text(
                                        '${NumberFormat('#,###').format(_earnings!['total_balance'] ?? 0)} CDF',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 24.sp,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(child: SizedBox(height: 100.h)),
                    ],
                  ),
                ),
    );
  }

  Widget _buildFilterTab(int index, String label) {
    final isActive = _selectedFilter == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedFilter = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(vertical: 10.h),
          decoration: BoxDecoration(
            color: isActive ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10.r),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.white.withOpacity(0.6),
                fontSize: 13.sp,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMiniChart() {
    final today = (_earnings?['today'] ?? 0).toDouble();
    final week = (_earnings?['this_week'] ?? 0).toDouble();
    final month = (_earnings?['this_month'] ?? 0).toDouble();
    final maxVal = [today, week, month].reduce((a, b) => a > b ? a : b);
    final values = [today, week, month];
    final labels = ['Jour', 'Sem', 'Mois'];

    return SizedBox(
      height: 80.h,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(3, (i) {
          final ratio = maxVal > 0 ? values[i] / maxVal : 0.0;
          final isSelected = _selectedFilter == i;
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 32.w,
                  height: (ratio * 50.h).clamp(8.h, 50.h),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary
                        : Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6.r),
                  ),
                ),
                SizedBox(height: 6.h),
                Text(
                  labels[i],
                  style: TextStyle(
                    color: isSelected
                        ? AppColors.primary
                        : Colors.white.withOpacity(0.4),
                    fontSize: 10.sp,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStatTile({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.all(8.r),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Icon(icon, color: color, size: 18.sp),
            ),
            SizedBox(height: 10.h),
            Text(
              value,
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 2.h),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.sp,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
