import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/widgets/app_alert.dart';

class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({super.key});

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  final ApiClient _api = getIt<ApiClient>();
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _driverProfile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _api.dio.get(ApiConstants.profile),
        _api.dio.get(ApiConstants.driverProfile),
      ]);
      setState(() {
        _profile = results[0].data;
        _driverProfile = results[1].data;
        _loading = false;
      });
    } on DioException catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        AppAlert.showDioError(context, e,
          fallback: 'Impossible de charger votre profil.',
          title: 'Chargement du profil',
        );
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    await _api.clearTokens();
    if (mounted) context.go('/welcome');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.primary,
              child: CustomScrollView(
                slivers: [
                  // Gradient header
                  SliverToBoxAdapter(
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: AppColors.darkGradient,
                        ),
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(32),
                          bottomRight: Radius.circular(32),
                        ),
                      ),
                      child: SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 32.h),
                          child: Column(
                            children: [
                              Text(
                                AppStrings.profile,
                                style: TextStyle(
                                  fontSize: 18.sp,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(height: 20.h),
                              // Avatar
                              Container(
                                width: 84.w,
                                height: 84.w,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: AppColors.ctaGradient,
                                  ),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.3),
                                    width: 3,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    _initials(),
                                    style: TextStyle(
                                      fontSize: 28.sp,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(height: 12.h),
                              Text(
                                '${_profile?['first_name'] ?? ''} ${_profile?['last_name'] ?? ''}',
                                style: TextStyle(
                                  fontSize: 20.sp,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(height: 4.h),
                              Text(
                                _profile?['phone'] ?? '',
                                style: TextStyle(
                                  fontSize: 13.sp,
                                  color: Colors.white.withOpacity(0.7),
                                ),
                              ),
                              SizedBox(height: 14.h),
                              // Rating & status badges
                              if (_driverProfile != null)
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _badge(
                                      icon: Icons.star_rounded,
                                      text: (_driverProfile!['avg_rating'] ?? 0)
                                          .toStringAsFixed(1),
                                    ),
                                    SizedBox(width: 12.w),
                                    _badge(
                                      icon: _driverProfile!['is_approved'] == true
                                          ? Icons.verified_rounded
                                          : Icons.hourglass_top_rounded,
                                      text: _driverProfile!['is_approved'] == true
                                          ? 'Approuv\u00e9'
                                          : 'En attente',
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Content
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 0),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        // Stats row
                        Container(
                          padding: EdgeInsets.symmetric(vertical: 16.h),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20.r),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              _StatItem(
                                icon: Icons.local_taxi_rounded,
                                value: '${_driverProfile?['total_rides'] ?? 0}',
                                label: 'Courses',
                                color: AppColors.primary,
                              ),
                              Container(width: 1, height: 40.h, color: AppColors.divider),
                              _StatItem(
                                icon: Icons.star_rounded,
                                value: (_driverProfile?['avg_rating'] != null && (_driverProfile!['avg_rating'] is num ? _driverProfile!['avg_rating'] > 0 : (num.tryParse(_driverProfile!['avg_rating'].toString()) ?? 0) > 0))
                                    ? (num.tryParse(_driverProfile!['avg_rating'].toString()) ?? 0).toStringAsFixed(1)
                                    : '\u2014',
                                label: 'Note',
                                color: AppColors.starFilled,
                              ),
                              Container(width: 1, height: 40.h, color: AppColors.divider),
                              _StatItem(
                                icon: Icons.account_balance_wallet_rounded,
                                value: '${_driverProfile?['balance'] ?? 0}',
                                label: 'CDF',
                                color: AppColors.success,
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 24.h),

                        if (_driverProfile != null) ...[
                          _SectionTitle(title: AppStrings.vehicleInfo),
                          SizedBox(height: 8.h),
                          _InfoCard(children: [
                            _InfoRow(label: 'Marque', value: _driverProfile!['vehicle_brand'] ?? '\u2014'),
                            _InfoRow(label: 'Mod\u00e8le', value: _driverProfile!['vehicle_model'] ?? '\u2014'),
                            _InfoRow(label: 'Couleur', value: _driverProfile!['vehicle_color'] ?? '\u2014'),
                            _InfoRow(label: 'Plaque', value: _driverProfile!['license_plate'] ?? '\u2014'),
                          ]),
                          SizedBox(height: 24.h),
                          _SectionTitle(title: AppStrings.documents),
                          SizedBox(height: 8.h),
                          _InfoCard(children: [
                            _DocRow(label: 'Permis de conduire', uploaded: _driverProfile!['license_document'] != null),
                            _DocRow(label: 'Carte d\'identit\u00e9', uploaded: _driverProfile!['id_document'] != null),
                            _DocRow(label: 'Assurance v\u00e9hicule', uploaded: _driverProfile!['insurance_document'] != null),
                          ]),
                        ],

                        SizedBox(height: 24.h),

                        // Settings section
                        _SectionTitle(title: 'Param\u00e8tres'),
                        SizedBox(height: 8.h),
                        _SettingsTile(
                          icon: Icons.language_rounded,
                          label: 'Langue',
                          trailing: 'Fran\u00e7ais',
                        ),
                        _SettingsTile(
                          icon: Icons.notifications_rounded,
                          label: 'Notifications',
                          trailing: 'Activ\u00e9es',
                        ),
                        _SettingsTile(
                          icon: Icons.help_outline_rounded,
                          label: 'Support',
                        ),

                        SizedBox(height: 24.h),

                        // Logout
                        OutlinedButton.icon(
                          onPressed: _logout,
                          icon: const Icon(Icons.logout, color: AppColors.error),
                          label: const Text(
                            AppStrings.logout,
                            style: TextStyle(color: AppColors.error),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.error),
                            minimumSize: Size(double.infinity, 50.h),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14.r),
                            ),
                          ),
                        ),
                        SizedBox(height: 100.h),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _badge({required IconData icon, required String text}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16.sp),
          SizedBox(width: 4.w),
          Text(
            text,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13.sp,
            ),
          ),
        ],
      ),
    );
  }

  String _initials() {
    final f = (_profile?['first_name'] as String?)?.isNotEmpty == true
        ? _profile!['first_name'][0]
        : '';
    final l = (_profile?['last_name'] as String?)?.isNotEmpty == true
        ? _profile!['last_name'][0]
        : '';
    return '$f$l'.toUpperCase();
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16.sp,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final List<Widget> children;
  const _InfoCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
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
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      child: Column(children: children),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary)),
          Text(value, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _DocRow extends StatelessWidget {
  final String label;
  final bool uploaded;
  const _DocRow({required this.label, required this.uploaded});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Row(
        children: [
          Icon(
            uploaded ? Icons.check_circle_rounded : Icons.upload_file_rounded,
            color: uploaded ? AppColors.success : AppColors.textHint,
            size: 20.sp,
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 14.sp)),
          ),
          Text(
            uploaded ? 'T\u00e9l\u00e9charg\u00e9' : 'Manquant',
            style: TextStyle(
              fontSize: 12.sp,
              color: uploaded ? AppColors.success : AppColors.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _StatItem({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 20.sp),
          SizedBox(height: 4.h),
          Text(
            value,
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.sp,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? trailing;

  const _SettingsTile({required this.icon, required this.label, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8.r),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Icon(icon, color: AppColors.primary, size: 20.sp),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: TextStyle(
                fontSize: 13.sp,
                color: AppColors.textSecondary,
              ),
            ),
          SizedBox(width: 4.w),
          Icon(Icons.chevron_right_rounded, color: AppColors.textHint, size: 20.sp),
        ],
      ),
    );
  }
}
