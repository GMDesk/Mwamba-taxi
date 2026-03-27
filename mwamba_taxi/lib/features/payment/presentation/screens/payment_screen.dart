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

class _OperatorInfo {
  final String name;
  final Color color;
  const _OperatorInfo(this.name, this.color);
}

_OperatorInfo? _detectOperator(String phone) {
  final clean = phone.replaceAll(RegExp(r'[\s\-\+]'), '');
  String prefix;
  if (clean.startsWith('243') && clean.length >= 5) {
    prefix = clean.substring(3, 5);
  } else if (clean.startsWith('0') && clean.length >= 3) {
    prefix = clean.substring(1, 3);
  } else if (clean.length >= 2 && !clean.startsWith('243')) {
    prefix = clean.substring(0, 2);
  } else {
    return null;
  }
  switch (prefix) {
    case '81':
    case '82':
    case '83':
      return const _OperatorInfo('Vodacom', Color(0xFFE60000));
    case '97':
    case '99':
    case '98':
      return const _OperatorInfo('Airtel', Color(0xFFFF0000));
    case '80':
    case '84':
    case '85':
    case '89':
      return const _OperatorInfo('Orange', Color(0xFFFF6600));
    default:
      return null;
  }
}

double _toNum(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;

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
        _wallet = results[0].data is Map ? results[0].data : null;
        final txData = results[1].data;
        _transactions = txData is List
            ? txData
            : (txData is Map ? (txData['results'] ?? []) : []);
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
                onChanged: (_) => setSheetState(() {}),
                decoration: InputDecoration(
                  labelText: 'Numéro Mobile Money',
                  hintText: '0XX XXX XXXX',
                  filled: true,
                  fillColor: AppColors.inputFill,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14.r),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: Padding(
                    padding: EdgeInsets.only(left: 14.w, right: 8.w),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '🇨🇩 +243',
                          style: GoogleFonts.poppins(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        SizedBox(width: 6.w),
                        Container(
                          width: 1,
                          height: 20.h,
                          color: AppColors.border,
                        ),
                      ],
                    ),
                  ),
                  prefixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0),
                  suffixIcon: Builder(
                    builder: (_) {
                      final op = _detectOperator(phoneCtrl.text.trim());
                      if (op == null) return const SizedBox.shrink();
                      return Container(
                        margin: EdgeInsets.only(right: 10.w),
                        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                        decoration: BoxDecoration(
                          color: op.color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8.r),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.sim_card_rounded, size: 16.sp, color: op.color),
                            SizedBox(width: 4.w),
                            Text(
                              op.name,
                              style: GoogleFonts.poppins(
                                fontSize: 11.sp,
                                fontWeight: FontWeight.w700,
                                color: op.color,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
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
                          final rawPhone = phoneCtrl.text.trim();
                          if (rawPhone.isEmpty) return;
                          final phone = rawPhone.startsWith('0')
                              ? '+243${rawPhone.substring(1)}'
                              : '+243$rawPhone';
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
                              final errData = e.response?.data;
                              final msg = errData is Map
                                  ? (errData['detail'] ?? 'Erreur lors du dépôt')
                                  : 'Erreur lors du dépôt';
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(content: Text(msg.toString())),
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
    final balance = _toNum(_wallet?['balance']);

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
                                  if (_toNum(_wallet?['held_amount']) > 0)
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
                                        '🔒 ${fmt.format(_toNum(_wallet!['held_amount']))} bloqué',
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
    final amount = _toNum(tx['amount']);
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
