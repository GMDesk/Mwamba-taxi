import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/constants/app_strings.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _heroFade;
  late final Animation<double> _logoScale;
  late final Animation<double> _chipsFade;
  late final Animation<Offset> _chipsSlide;
  late final Animation<double> _btnFade;
  late final Animation<Offset> _btnSlide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _heroFade = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.3, curve: Curves.easeOut)),
    );
    _logoScale = Tween(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.4, curve: Curves.elasticOut)),
    );
    _chipsFade = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.35, 0.65, curve: Curves.easeOut)),
    );
    _chipsSlide = Tween(begin: const Offset(0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.35, 0.65, curve: Curves.easeOutCubic)),
    );
    _btnFade = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.6, 1.0, curve: Curves.easeOut)),
    );
    _btnSlide = Tween(begin: const Offset(0, 0.5), end: Offset.zero).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.6, 1.0, curve: Curves.easeOutCubic)),
    );
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Column(
          children: [
            // ── Yellow branded hero ──
            Expanded(
              flex: 4,
              child: FadeTransition(
                opacity: _heroFade,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primaryDark, AppColors.primary, AppColors.primaryLight],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      stops: [0.0, 0.6, 1.0],
                    ),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(44),
                      bottomRight: Radius.circular(44),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryDark.withOpacity(0.3),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Spacer(),
                        // Animated logo
                        ScaleTransition(
                          scale: _logoScale,
                          child: Container(
                            width: 130.w,
                            height: 130.w,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(32.r),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.12),
                                  blurRadius: 30,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            padding: EdgeInsets.all(8.w),
                            child: Image.asset(
                              'assets/images/logo.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        SizedBox(height: 20.h),
                        Text(
                          'MWAMBA TAXI',
                          style: TextStyle(
                            fontSize: 26.sp,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 2,
                          ),
                        ),
                        SizedBox(height: 8.h),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 40.w),
                          child: Text(
                            AppStrings.welcomeSubtitle,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13.sp,
                              color: Colors.white.withOpacity(0.8),
                              height: 1.5,
                            ),
                          ),
                        ),
                        const Spacer(),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Bottom section
            Expanded(
              flex: 3,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 28.w),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(),
                    // Animated feature chips
                    SlideTransition(
                      position: _chipsSlide,
                      child: FadeTransition(
                        opacity: _chipsFade,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _FeatureChip(icon: Icons.shield_outlined, label: 'Sécurisé'),
                            _FeatureChip(icon: Icons.speed_outlined, label: 'Rapide'),
                            _FeatureChip(icon: Icons.payments_outlined, label: 'Abordable'),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    // Animated buttons
                    SlideTransition(
                      position: _btnSlide,
                      child: FadeTransition(
                        opacity: _btnFade,
                        child: Column(
                          children: [
                            // Login — gradient CTA
                            GestureDetector(
                              onTap: () => context.push('/login'),
                              child: Container(
                                width: double.infinity,
                                height: 56.h,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFFB71C1C), Color(0xFFE53935)],
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                  ),
                                  borderRadius: BorderRadius.circular(18.r),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFB71C1C).withOpacity(0.35),
                                      blurRadius: 16,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Text(
                                    AppStrings.login,
                                    style: TextStyle(
                                      fontSize: 16.sp,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: 14.h),
                            // Register — outlined
                            GestureDetector(
                              onTap: () => context.push('/register'),
                              child: Container(
                                width: double.infinity,
                                height: 56.h,
                                decoration: BoxDecoration(
                                  border: Border.all(color: AppColors.textSecondary.withOpacity(0.3), width: 1.5),
                                  borderRadius: BorderRadius.circular(18.r),
                                ),
                                child: Center(
                                  child: Text(
                                    AppStrings.register,
                                    style: TextStyle(
                                      fontSize: 16.sp,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 32.h),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FeatureChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56.w,
          height: 56.w,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(18.r),
            border: Border.all(color: AppColors.primary.withOpacity(0.15)),
          ),
          child: Icon(icon, color: AppColors.primaryDark, size: 24.sp),
        ),
        SizedBox(height: 8.h),
        Text(
          label,
          style: TextStyle(
            fontSize: 12.sp,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
