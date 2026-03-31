import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final TextEditingController _promoController = TextEditingController();

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

  Future<void> _applyPromo() async {
    final code = _promoController.text.trim();
    if (code.isEmpty) return;
    try {
      final resp = await _api.dio.post(ApiConstants.validatePromo, data: {'code': code});
      final data = resp.data as Map<String, dynamic>;
      if (mounted) {
        _promoController.clear();
        final discount = data['estimated_discount'] ?? data['discount_value'] ?? '';
        final desc = data['description'] ?? '';
        final msg = discount.toString().isNotEmpty && discount != '0'
            ? 'Code "$code" appliqué ! Réduction : $discount CDF\n$desc'
            : 'Code "$code" valide ! $desc';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AppColors.success, duration: const Duration(seconds: 4)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Code promo invalide ou expiré'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showPromoDialog() {
    _promoController.clear();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
        title: Text('Code Promo', style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: _promoController,
          decoration: InputDecoration(
            hintText: 'Entrer votre code',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Annuler', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () { Navigator.pop(context); _applyPromo(); },
            child: const Text('Appliquer'),
          ),
        ],
      ),
    );
  }

  void _showReferralSheet() {
    final code = _profile?['referral_code'] as String? ?? '';
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24.r))),
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(24.w, 20.h, 24.w, 32.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40.w, height: 4.h,
              margin: EdgeInsets.only(bottom: 20.h),
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2.r)),
            ),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.primaryDark.withOpacity(0.12), shape: BoxShape.circle),
              child: Icon(Icons.people_alt_rounded, color: AppColors.primaryDark, size: 32.sp),
            ),
            SizedBox(height: 16.h),
            Text('Parrainez vos amis', style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            SizedBox(height: 8.h),
            Text(
              'Partagez votre code et gagnez des bonus\npour chaque ami qui s\'inscrit.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary, height: 1.5),
            ),
            SizedBox(height: 24.h),
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 18.h),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: AppColors.ctaGradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(16.r),
              ),
              child: Column(
                children: [
                  Text('Votre code de parrainage', style: TextStyle(fontSize: 12.sp, color: Colors.white.withOpacity(0.85))),
                  SizedBox(height: 6.h),
                  Text(code.isNotEmpty ? code : '--------', style: TextStyle(fontSize: 28.sp, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 6)),
                ],
              ),
            ),
            SizedBox(height: 16.h),
            SizedBox(
              width: double.infinity, height: 56.h,
              child: OutlinedButton.icon(
                onPressed: code.isNotEmpty
                    ? () {
                        Clipboard.setData(ClipboardData(text: code));
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Code "$code" copié !'), backgroundColor: AppColors.success),
                        );
                      }
                    : null,
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Copier le code'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      body: SafeArea(
        child: _loading
            ? Center(child: CircularProgressIndicator(color: AppColors.primary))
            : SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: Column(
                  children: [
                    SizedBox(height: 24.h),

                    // ── Avatar + name + badge (Yango centered profile) ──
                    Center(
                      child: Column(
                        children: [
                          Container(
                            width: 80.w,
                            height: 80.w,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.primary, width: 3),
                            ),
                            child: ClipOval(
                              child: _avatarUrl != null && _avatarUrl!.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: _avatarUrl!.startsWith('http')
                                          ? _avatarUrl!
                                          : '${ApiConstants.baseUrl.replaceAll('/api/v1', '')}$_avatarUrl',
                                      fit: BoxFit.cover,
                                      placeholder: (_, __) => Container(
                                        color: AppColors.darkLight,
                                        child: Icon(Icons.person, color: Colors.white, size: 36.sp),
                                      ),
                                      errorWidget: (_, __, ___) => Container(
                                        color: AppColors.darkLight,
                                        child: Icon(Icons.person, color: Colors.white, size: 36.sp),
                                      ),
                                    )
                                  : Container(
                                      color: AppColors.darkLight,
                                      child: Icon(Icons.person, color: Colors.white, size: 36.sp),
                                    ),
                            ),
                          ),
                          SizedBox(height: 12.h),
                          // Green "Excellent" badge like Yango
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 4.h),
                            decoration: BoxDecoration(
                              color: AppColors.success,
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                            child: Text(
                              'Excellent',
                              style: GoogleFonts.poppins(
                                fontSize: 12.sp,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          SizedBox(height: 10.h),
                          Text(
                            _profile?['full_name'] ?? 'Utilisateur',
                            style: GoogleFonts.poppins(
                              fontSize: 22.sp,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 2.h),
                          Text(
                            _profile?['phone_number'] ?? '',
                            style: GoogleFonts.poppins(
                              fontSize: 14.sp,
                              color: Colors.white.withOpacity(0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 28.h),

                    // ── Group 1: Réductions & Paiement ──
                    _DarkMenuSection(
                      children: [
                        _DarkMenuItem(
                          icon: Icons.confirmation_number_outlined,
                          label: 'Réductions',
                          onTap: _showPromoDialog,
                        ),
                        _DarkMenuItem(
                          icon: Icons.account_balance_wallet_rounded,
                          label: 'Paiement',
                          onTap: () {},
                        ),
                      ],
                    ),
                    SizedBox(height: 12.h),

                    // ── Group 2: Historique, Adresses, Assistance ──
                    _DarkMenuSection(
                      children: [
                        _DarkMenuItem(
                          icon: Icons.history_rounded,
                          label: AppStrings.rideHistory,
                          onTap: () => context.push('/history'),
                        ),
                        _DarkMenuItem(
                          icon: Icons.bookmark_outline_rounded,
                          label: 'Adresses',
                          onTap: () {},
                        ),
                        _DarkMenuItem(
                          icon: Icons.support_agent_rounded,
                          label: 'Assistance',
                          onTap: () {},
                        ),
                      ],
                    ),
                    SizedBox(height: 12.h),

                    // ── Red CTA: Driver ──
                    GestureDetector(
                      onTap: () {},
                      child: Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
                        decoration: BoxDecoration(
                          color: AppColors.darkLight,
                          borderRadius: BorderRadius.circular(16.r),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40.w,
                              height: 40.w,
                              decoration: BoxDecoration(
                                color: AppColors.error.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12.r),
                              ),
                              child: Icon(Icons.local_taxi_rounded, size: 22.sp, color: AppColors.error),
                            ),
                            SizedBox(width: 14.w),
                            Expanded(
                              child: Text(
                                'Travaillez comme conducteur',
                                style: GoogleFonts.poppins(
                                  fontSize: 15.sp,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.error,
                                ),
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded, color: AppColors.error.withOpacity(0.6), size: 20.sp),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 12.h),

                    // ── Group 3: Sécurité ──
                    _DarkMenuSection(
                      children: [
                        _DarkMenuItem(
                          icon: Icons.shield_outlined,
                          label: 'Sécurité',
                          onTap: () {},
                        ),
                      ],
                    ),
                    SizedBox(height: 12.h),

                    // ── Group 4: Parrainage, Paramètres, Informations ──
                    _DarkMenuSection(
                      children: [
                        _DarkMenuItem(
                          icon: Icons.share_rounded,
                          label: 'Parrainage',
                          onTap: _showReferralSheet,
                        ),
                        _DarkMenuItem(
                          icon: Icons.person_outline_rounded,
                          label: AppStrings.myProfile,
                          onTap: () => context.push('/profile'),
                        ),
                        _DarkMenuItem(
                          icon: Icons.settings_outlined,
                          label: 'Paramètres',
                          onTap: () {},
                        ),
                        _DarkMenuItem(
                          icon: Icons.info_outline_rounded,
                          label: 'Informations',
                          onTap: () {},
                        ),
                      ],
                    ),
                    SizedBox(height: 12.h),

                    // ── Logout ──
                    _DarkMenuSection(
                      children: [
                        _DarkMenuItem(
                          icon: Icons.logout_rounded,
                          label: AppStrings.logout,
                          iconColor: AppColors.error,
                          textColor: AppColors.error,
                          onTap: () => _showLogoutDialog(),
                        ),
                      ],
                    ),
                    SizedBox(height: 40.h),
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
        backgroundColor: AppColors.darkLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
        title: Text(
          'Déconnexion',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: Colors.white),
        ),
        content: Text(
          'Voulez-vous vraiment vous déconnecter ?',
          style: GoogleFonts.poppins(color: Colors.white.withOpacity(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Annuler', style: TextStyle(color: Colors.white.withOpacity(0.5))),
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

// ─── Yango-style dark grouped menu section ──────────────────────

class _DarkMenuSection extends StatelessWidget {
  final List<Widget> children;
  const _DarkMenuSection({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.darkLight,
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Column(
        children: List.generate(children.length, (index) {
          return Column(
            children: [
              children[index],
              if (index < children.length - 1)
                Divider(height: 1, indent: 56.w, color: Colors.white.withOpacity(0.08)),
            ],
          );
        }),
      ),
    );
  }
}

class _DarkMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? textColor;

  const _DarkMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final fg = textColor ?? Colors.white;
    final ic = iconColor ?? AppColors.primary;
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
                  color: ic.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Icon(icon, size: 20.sp, color: ic),
              ),
              SizedBox(width: 14.w),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w500,
                    color: fg,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.white.withOpacity(0.3), size: 20.sp),
            ],
          ),
        ),
      ),
    );
  }
}
