import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final ApiClient _api = getIt<ApiClient>();
  List<dynamic> _payments = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPayments();
  }

  Future<void> _loadPayments() async {
    setState(() => _loading = true);
    try {
      final resp = await _api.dio.get(ApiConstants.paymentHistory);
      setState(() {
        _payments = resp.data['results'] ?? resp.data;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
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
              padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 8.h),
              child: Text(
                AppStrings.tabPayment,
                style: GoogleFonts.poppins(
                  fontSize: 26.sp,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ),

            // Payment method card
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.all(20.w),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: AppColors.darkGradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20.r),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44.w,
                          height: 44.w,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                          child: Icon(
                            Icons.account_balance_wallet_rounded,
                            color: AppColors.primary,
                            size: 24.sp,
                          ),
                        ),
                        SizedBox(width: 14.w),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppStrings.mobileMoney,
                              style: GoogleFonts.poppins(
                                fontSize: 16.sp,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              'Moyen de paiement principal',
                              style: GoogleFonts.poppins(
                                fontSize: 12.sp,
                                color: Colors.white.withOpacity(0.6),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    SizedBox(height: 20.h),
                    Row(
                      children: [
                        _PaymentMethodChip(
                          icon: Icons.phone_android_rounded,
                          label: 'M-Pesa',
                          isActive: true,
                        ),
                        SizedBox(width: 10.w),
                        _PaymentMethodChip(
                          icon: Icons.money_rounded,
                          label: AppStrings.cash,
                          isActive: false,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Recent transactions header
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 12.h),
              child: Text(
                'Transactions récentes',
                style: GoogleFonts.poppins(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),

            // Transactions list
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _payments.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 72.w,
                                height: 72.w,
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20.r),
                                ),
                                child: Icon(
                                  Icons.receipt_long_rounded,
                                  size: 36.sp,
                                  color: AppColors.primary,
                                ),
                              ),
                              SizedBox(height: 16.h),
                              Text(
                                'Aucune transaction',
                                style: GoogleFonts.poppins(
                                  fontSize: 16.sp,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              SizedBox(height: 4.h),
                              Text(
                                'Vos paiements apparaîtront ici',
                                style: GoogleFonts.poppins(
                                  fontSize: 13.sp,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadPayments,
                          color: AppColors.primary,
                          child: ListView.separated(
                            padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 24.h),
                            itemCount: _payments.length,
                            separatorBuilder: (_, __) => SizedBox(height: 10.h),
                            itemBuilder: (context, index) {
                              final payment = _payments[index];
                              return _TransactionTile(payment: payment);
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

class _PaymentMethodChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;

  const _PaymentMethodChip({
    required this.icon,
    required this.label,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.primary.withOpacity(0.2)
            : Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: isActive ? AppColors.primary : Colors.white.withOpacity(0.15),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16.sp, color: isActive ? AppColors.primary : Colors.white60),
          SizedBox(width: 6.w),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12.sp,
              fontWeight: FontWeight.w600,
              color: isActive ? AppColors.primary : Colors.white60,
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final Map<String, dynamic> payment;
  const _TransactionTile({required this.payment});

  @override
  Widget build(BuildContext context) {
    final amount = payment['amount'] ?? '0';
    final status = payment['status'] ?? '';
    final isSuccess = status == 'completed' || status == 'success';

    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44.w,
            height: 44.w,
            decoration: BoxDecoration(
              color: (isSuccess ? AppColors.success : AppColors.warning).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Icon(
              isSuccess ? Icons.check_circle_rounded : Icons.pending_rounded,
              color: isSuccess ? AppColors.success : AppColors.warning,
              size: 22.sp,
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Paiement course',
                  style: GoogleFonts.poppins(fontSize: 14.sp, fontWeight: FontWeight.w600),
                ),
                Text(
                  isSuccess ? 'Complété' : 'En attente',
                  style: GoogleFonts.poppins(fontSize: 12.sp, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Text(
            '$amount CDF',
            style: GoogleFonts.poppins(
              fontSize: 15.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
