import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final ApiClient _api = getIt<ApiClient>();
  Map<String, dynamic>? _profile;
  bool _loading = true;
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final resp = await _api.dio.get(ApiConstants.profile);
      final data = resp.data as Map<String, dynamic>;
      setState(() {
        _profile = data;
        _avatarUrl = data['avatar'];
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
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
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: Column(
                  children: [
                    SizedBox(height: 16.h),

                    // Header
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        AppStrings.tabAccount,
                        style: GoogleFonts.poppins(
                          fontSize: 26.sp,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    SizedBox(height: 24.h),

                    // Profile card
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(20.w),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: AppColors.ctaGradient,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20.r),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primaryDark.withOpacity(0.3),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          // Avatar
                          Container(
                            width: 64.w,
                            height: 64.w,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2.5),
                            ),
                            child: ClipOval(
                              child: _avatarUrl != null && _avatarUrl!.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: _avatarUrl!.startsWith('http')
                                          ? _avatarUrl!
                                          : '${ApiConstants.baseUrl.replaceAll('/api/v1', '')}$_avatarUrl',
                                      fit: BoxFit.cover,
                                      placeholder: (_, __) => Container(
                                        color: Colors.white.withOpacity(0.2),
                                        child: Icon(Icons.person, color: Colors.white, size: 28.sp),
                                      ),
                                      errorWidget: (_, __, ___) => Container(
                                        color: Colors.white.withOpacity(0.2),
                                        child: Icon(Icons.person, color: Colors.white, size: 28.sp),
                                      ),
                                    )
                                  : Container(
                                      color: Colors.white.withOpacity(0.2),
                                      child: Icon(Icons.person, color: Colors.white, size: 28.sp),
                                    ),
                            ),
                          ),
                          SizedBox(width: 16.w),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _profile?['full_name'] ?? 'Utilisateur',
                                  style: GoogleFonts.poppins(
                                    fontSize: 18.sp,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(height: 2.h),
                                Text(
                                  _profile?['phone_number'] ?? '',
                                  style: GoogleFonts.poppins(
                                    fontSize: 13.sp,
                                    color: Colors.white.withOpacity(0.8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 28.h),

                    // Menu items
                    _MenuSection(
                      children: [
                        _MenuItem(
                          icon: Icons.person_outline_rounded,
                          label: AppStrings.myProfile,
                          onTap: () => context.push('/profile'),
                        ),
                        _MenuItem(
                          icon: Icons.history_rounded,
                          label: AppStrings.rideHistory,
                          onTap: () => context.push('/history'),
                        ),
                        _MenuItem(
                          icon: Icons.confirmation_number_outlined,
                          label: AppStrings.promoCode,
                          onTap: () => context.push('/profile'),
                        ),
                      ],
                    ),
                    SizedBox(height: 16.h),

                    _MenuSection(
                      children: [
                        _MenuItem(
                          icon: Icons.help_outline_rounded,
                          label: 'Aide & Support',
                          onTap: () {},
                        ),
                        _MenuItem(
                          icon: Icons.info_outline_rounded,
                          label: 'À propos',
                          onTap: () {},
                        ),
                      ],
                    ),
                    SizedBox(height: 16.h),

                    // Logout
                    _MenuSection(
                      children: [
                        _MenuItem(
                          icon: Icons.logout_rounded,
                          label: AppStrings.logout,
                          color: AppColors.error,
                          onTap: () => _showLogoutDialog(),
                        ),
                      ],
                    ),
                    SizedBox(height: 32.h),
                  ],
                ),
              ),
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Déconnexion',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Voulez-vous vraiment vous déconnecter ?',
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _logout();
            },
            child: Text(
              'Déconnexion',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuSection extends StatelessWidget {
  final List<Widget> children;
  const _MenuSection({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
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
      child: Column(
        children: List.generate(children.length, (index) {
          return Column(
            children: [
              children[index],
              if (index < children.length - 1)
                Divider(height: 1, indent: 56.w, color: AppColors.divider),
            ],
          );
        }),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final fgColor = color ?? AppColors.textPrimary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16.r),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
          child: Row(
            children: [
              Container(
                width: 36.w,
                height: 36.w,
                decoration: BoxDecoration(
                  color: (color ?? AppColors.primary).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Icon(icon, size: 20.sp, color: color ?? AppColors.primary),
              ),
              SizedBox(width: 14.w),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w500,
                    color: fgColor,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AppColors.textHint, size: 20.sp),
            ],
          ),
        ),
      ),
    );
  }
}
