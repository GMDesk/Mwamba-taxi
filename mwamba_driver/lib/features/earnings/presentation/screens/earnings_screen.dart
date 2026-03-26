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

  void _showWithdrawSheet() {
    final amountCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    bool sending = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final walletBalance = (_earnings?['wallet_balance'] ?? 0).toDouble();
          return Container(
            padding: EdgeInsets.fromLTRB(
                20.w, 12.h, 20.w, MediaQuery.of(ctx).viewInsets.bottom + 24.h),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40.w, height: 4.h,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2.r),
                    ),
                  ),
                ),
                SizedBox(height: 20.h),
                Text('Retirer vers Mobile Money',
                    style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700)),
                SizedBox(height: 8.h),
                Text(
                  'Solde disponible: ${NumberFormat('#,###').format(walletBalance)} CDF',
                  style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary),
                ),
                SizedBox(height: 20.h),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Montant (CDF)',
                    hintText: 'Min. 1 000 CDF',
                    filled: true,
                    fillColor: AppColors.inputFill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14.r),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                SizedBox(height: 12.h),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Numéro Mobile Money',
                    hintText: '+243 8XX XXX XXX',
                    filled: true,
                    fillColor: AppColors.inputFill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14.r),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                SizedBox(height: 20.h),
                SizedBox(
                  width: double.infinity,
                  height: 52.h,
                  child: ElevatedButton(
                    onPressed: sending
                        ? null
                        : () async {
                            final amount = int.tryParse(amountCtrl.text.trim()) ?? 0;
                            if (amount < 1000) return;
                            final phone = phoneCtrl.text.trim();
                            if (phone.isEmpty) return;
                            setSheetState(() => sending = true);
                            try {
                              await _api.dio.post(
                                ApiConstants.payoutRequest,
                                data: {'amount': amount, 'phone_number': phone},
                              );
                              if (ctx.mounted) Navigator.pop(ctx);
                              _load();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Retrait initié — vérifiez votre téléphone')),
                                );
                              }
                            } on DioException catch (e) {
                              setSheetState(() => sending = false);
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(
                                      content: Text(e.response?.data?['detail'] ??
                                          'Erreur lors du retrait')),
                                );
                              }
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16.r)),
                    ),
                    child: sending
                        ? SizedBox(
                            width: 22.w, height: 22.w,
                            child: const CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5))
                        : Text('Retirer',
                            style: TextStyle(
                                fontSize: 15.sp,
                                fontWeight: FontWeight.w700,
                                color: Colors.white)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,###');
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
                      TextButton(onPressed: _load, child: const Text('Réessayer')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.primary,
                  child: CustomScrollView(
                    slivers: [
                      // Header with earnings
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
                                  Text('Mes Revenus',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 18.sp,
                                          fontWeight: FontWeight.w700)),
                                  SizedBox(height: 20.h),
                                  // Filter tabs
                                  Container(
                                    padding: EdgeInsets.all(4.w),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(14.r),
                                    ),
                                    child: Row(children: [
                                      _buildFilterTab(0, 'Jour'),
                                      _buildFilterTab(1, 'Semaine'),
                                      _buildFilterTab(2, 'Mois'),
                                    ]),
                                  ),
                                  SizedBox(height: 24.h),
                                  Text(_filterLabel,
                                      style: TextStyle(
                                          color: Colors.white.withOpacity(0.6),
                                          fontSize: 13.sp)),
                                  SizedBox(height: 6.h),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(_currentAmount,
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 40.sp,
                                              fontWeight: FontWeight.w800,
                                              height: 1)),
                                      Padding(
                                        padding: EdgeInsets.only(bottom: 4.h, left: 6.w),
                                        child: Text('CDF',
                                            style: TextStyle(
                                                color: AppColors.primary,
                                                fontSize: 16.sp,
                                                fontWeight: FontWeight.w700)),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 20.h),
                                  _buildMiniChart(),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Wallet balance card with withdraw button
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 0),
                        sliver: SliverToBoxAdapter(
                          child: Container(
                            padding: EdgeInsets.all(20.w),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: AppColors.ctaGradient),
                              borderRadius: BorderRadius.circular(20.r),
                            ),
                            child: Column(
                              children: [
                                Row(
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
                                          Text('Portefeuille',
                                              style: TextStyle(
                                                  color: Colors.white.withOpacity(0.8),
                                                  fontSize: 13.sp)),
                                          SizedBox(height: 4.h),
                                          Text(
                                            '${fmt.format(_earnings!['wallet_balance'] ?? 0)} CDF',
                                            style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 24.sp,
                                                fontWeight: FontWeight.w800),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 16.h),
                                SizedBox(
                                  width: double.infinity,
                                  height: 44.h,
                                  child: ElevatedButton.icon(
                                    onPressed: _showWithdrawSheet,
                                    icon: Icon(Icons.arrow_upward_rounded,
                                        color: AppColors.primary, size: 18.sp),
                                    label: Text('Retirer vers Mobile Money',
                                        style: TextStyle(
                                            fontSize: 14.sp,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.primary)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12.r)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Stats grid
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 0),
                        sliver: SliverToBoxAdapter(
                          child: Row(children: [
                            _buildStatTile(
                                icon: Icons.local_taxi_rounded,
                                value: '${_earnings!['total_rides'] ?? 0}',
                                label: 'Courses totales',
                                color: AppColors.info),
                            SizedBox(width: 12.w),
                            _buildStatTile(
                                icon: Icons.star_rounded,
                                value: '${(_earnings!['avg_rating'] ?? 0).toStringAsFixed(1)}',
                                label: 'Note moyenne',
                                color: AppColors.starFilled),
                          ]),
                        ),
                      ),
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 0),
                        sliver: SliverToBoxAdapter(
                          child: Row(children: [
                            _buildStatTile(
                                icon: Icons.check_circle_rounded,
                                value: '${_earnings!['acceptance_rate'] ?? '—'}%',
                                label: 'Taux acceptation',
                                color: AppColors.success),
                            SizedBox(width: 12.w),
                            _buildStatTile(
                                icon: Icons.receipt_long_rounded,
                                value: '${fmt.format(_earnings!['total_commission'] ?? 0)}',
                                label: 'Commission CDF',
                                color: AppColors.primary),
                          ]),
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
            child: Text(label,
                style: TextStyle(
                    color: isActive ? Colors.white : Colors.white.withOpacity(0.6),
                    fontSize: 13.sp,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500)),
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
                    color: isSelected ? AppColors.primary : Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6.r),
                  ),
                ),
                SizedBox(height: 6.h),
                Text(labels[i],
                    style: TextStyle(
                        color: isSelected ? AppColors.primary : Colors.white.withOpacity(0.4),
                        fontSize: 10.sp,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500)),
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
            Text(value,
                style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            SizedBox(height: 2.h),
            Text(label,
                style: TextStyle(fontSize: 11.sp, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
