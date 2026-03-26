import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';

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
  Map<String, dynamic>? _wallet;
  List<dynamic> _transactions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.dio.get(ApiConstants.wallet),
        _api.dio.get(ApiConstants.walletTransactions),
      ]);
      setState(() {
        _wallet = results[0].data;
        _transactions = results[1].data['results'] ?? results[1].data;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  void _showTopUpSheet() {
    final amountCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    bool depositing = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
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
                  width: 40.w,
                  height: 4.h,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2.r),
                  ),
                ),
              ),
              SizedBox(height: 20.h),
              Text('Recharger le portefeuille',
                  style: GoogleFonts.poppins(
                      fontSize: 18.sp, fontWeight: FontWeight.w700)),
              SizedBox(height: 20.h),
              // Quick amount chips
              Wrap(
                spacing: 10.w,
                children: [1000, 2000, 5000, 10000].map((a) {
                  return ActionChip(
                    label: Text('$a FC'),
                    labelStyle: GoogleFonts.poppins(
                        fontSize: 13.sp, fontWeight: FontWeight.w600),
                    backgroundColor: AppColors.surfaceVariant,
                    side: BorderSide.none,
                    onPressed: () =>
                        amountCtrl.text = a.toString(),
                  );
                }).toList(),
              ),
              SizedBox(height: 16.h),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Montant (CDF)',
                  hintText: 'Min. 500 CDF',
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
                  onPressed: depositing
                      ? null
                      : () async {
                          final amount =
                              int.tryParse(amountCtrl.text.trim()) ?? 0;
                          if (amount < 500) return;
                          final phone = phoneCtrl.text.trim();
                          if (phone.isEmpty) return;
                          setSheetState(() => depositing = true);
                          try {
                            await _api.dio.post(
                              ApiConstants.walletDeposit,
                              data: {
                                'amount': amount,
                                'phone_number': phone,
                              },
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            _loadData();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Dépôt initié — confirmez sur votre téléphone')),
                              );
                            }
                          } on DioException catch (e) {
                            setSheetState(() => depositing = false);
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        e.response?.data?['detail'] ??
                                            'Erreur lors du dépôt')),
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16.r)),
                  ),
                  child: depositing
                      ? SizedBox(
                          width: 22.w,
                          height: 22.w,
                          child: const CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5))
                      : Text('Recharger',
                          style: GoogleFonts.poppins(
                              fontSize: 15.sp,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,###');
    final balance = (_wallet?['balance'] ?? 0).toDouble();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary))
            : RefreshIndicator(
                onRefresh: _loadData,
                color: AppColors.primary,
                child: CustomScrollView(
                  slivers: [
                    // Header
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 8.h),
                        child: Text(
                          'Portefeuille',
                          style: GoogleFonts.poppins(
                            fontSize: 26.sp,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),

                    // Wallet balance card
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: 20.w, vertical: 12.h),
                        child: Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(24.w),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: AppColors.darkGradient,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(24.r),
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
                                      borderRadius:
                                          BorderRadius.circular(12.r),
                                    ),
                                    child: Icon(
                                      Icons.account_balance_wallet_rounded,
                                      color: AppColors.primary,
                                      size: 24.sp,
                                    ),
                                  ),
                                  SizedBox(width: 14.w),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Solde disponible',
                                        style: GoogleFonts.poppins(
                                          fontSize: 13.sp,
                                          color: Colors.white.withOpacity(0.6),
                                        ),
                                      ),
                                      Text(
                                        _wallet?['currency'] ?? 'CDF',
                                        style: GoogleFonts.poppins(
                                          fontSize: 12.sp,
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Spacer(),
                                  if ((_wallet?['held_amount'] ?? 0) > 0)
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 10.w, vertical: 4.h),
                                      decoration: BoxDecoration(
                                        color:
                                            AppColors.warning.withOpacity(0.2),
                                        borderRadius:
                                            BorderRadius.circular(8.r),
                                      ),
                                      child: Text(
                                        '🔒 ${fmt.format(_wallet!['held_amount'])} bloqué',
                                        style: GoogleFonts.poppins(
                                          fontSize: 10.sp,
                                          color: AppColors.warning,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              SizedBox(height: 20.h),
                              Text(
                                '${fmt.format(balance)} CDF',
                                style: GoogleFonts.poppins(
                                  fontSize: 36.sp,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  height: 1,
                                ),
                              ),
                              SizedBox(height: 20.h),
                              SizedBox(
                                width: double.infinity,
                                height: 48.h,
                                child: ElevatedButton.icon(
                                  onPressed: _showTopUpSheet,
                                  icon: Icon(Icons.add_rounded,
                                      color: Colors.white, size: 20.sp),
                                  label: Text(
                                    'Recharger',
                                    style: GoogleFonts.poppins(
                                      fontSize: 14.sp,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(14.r),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Payment method badges
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: 20.w, vertical: 4.h),
                        child: Row(
                          children: [
                            _PaymentMethodChip(
                              icon: Icons.account_balance_wallet_rounded,
                              label: 'Portefeuille',
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
                      ),
                    ),

                    // Transactions header
                    SliverToBoxAdapter(
                      child: Padding(
                        padding:
                            EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 12.h),
                        child: Text(
                          'Transactions récentes',
                          style: GoogleFonts.poppins(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),

                    // Transaction list
                    _transactions.isEmpty
                        ? SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 72.w,
                                    height: 72.w,
                                    decoration: BoxDecoration(
                                      color:
                                          AppColors.primary.withOpacity(0.1),
                                      borderRadius:
                                          BorderRadius.circular(20.r),
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
                                    'Vos transactions apparaîtront ici',
                                    style: GoogleFonts.poppins(
                                      fontSize: 13.sp,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : SliverPadding(
                            padding:
                                EdgeInsets.fromLTRB(20.w, 0, 20.w, 24.h),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final tx = _transactions[index];
                                  return Padding(
                                    padding: EdgeInsets.only(bottom: 10.h),
                                    child: _TransactionTile(tx: tx),
                                  );
                                },
                                childCount: _transactions.length,
                              ),
                            ),
                          ),
                  ],
                ),
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
            ? AppColors.primary.withOpacity(0.1)
            : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: isActive ? AppColors.primary : AppColors.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 16.sp,
              color: isActive ? AppColors.primary : AppColors.textSecondary),
          SizedBox(width: 6.w),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12.sp,
              fontWeight: FontWeight.w600,
              color: isActive ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final Map<String, dynamic> tx;
  const _TransactionTile({required this.tx});

  static const _txIcons = {
    'deposit': Icons.arrow_downward_rounded,
    'ride_payment': Icons.local_taxi_rounded,
    'ride_hold': Icons.lock_rounded,
    'hold_release': Icons.lock_open_rounded,
    'refund': Icons.replay_rounded,
    'payout': Icons.arrow_upward_rounded,
  };

  static const _txColors = {
    'deposit': AppColors.success,
    'ride_payment': AppColors.error,
    'ride_hold': AppColors.warning,
    'hold_release': AppColors.info,
    'refund': AppColors.success,
    'payout': AppColors.info,
  };

  @override
  Widget build(BuildContext context) {
    final amount = (tx['amount'] ?? 0).toDouble();
    final txType = tx['tx_type'] ?? '';
    final description = tx['description'] ?? '';
    final status = tx['status'] ?? '';
    final isCredit = amount > 0;
    final color = _txColors[txType] ?? AppColors.textSecondary;
    final icon = _txIcons[txType] ?? Icons.swap_horiz_rounded;
    final fmt = NumberFormat('#,###');

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
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Icon(icon, color: color, size: 22.sp),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  description.isNotEmpty ? description : txType,
                  style: GoogleFonts.poppins(
                      fontSize: 14.sp, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  status == 'completed'
                      ? 'Complété'
                      : status == 'pending'
                          ? 'En attente'
                          : status,
                  style: GoogleFonts.poppins(
                      fontSize: 12.sp, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Text(
            '${isCredit ? '+' : ''}${fmt.format(amount.abs())} FC',
            style: GoogleFonts.poppins(
              fontSize: 15.sp,
              fontWeight: FontWeight.w700,
              color: isCredit ? AppColors.success : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

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
