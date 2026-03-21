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
  late final Animation<double> _logoFade;
  late final Animation<double> _logoScale;
  late final Animation<double> _titleFade;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _chipsFade;
  late final Animation<double> _btnFade;
  late final Animation<Offset> _btnSlide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _logoFade = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.3, curve: Curves.easeOut)),
    );
    _logoScale = Tween(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.35, curve: Curves.elasticOut)),
    );
    _titleFade = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.2, 0.5, curve: Curves.easeOut)),
    );
    _titleSlide = Tween(begin: const Offset(0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.2, 0.5, curve: Curves.easeOutCubic)),
    );
    _chipsFade = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.4, 0.7, curve: Curves.easeOut)),
    );
    _btnFade = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.6, 1.0, curve: Curves.easeOut)),
    );
    _btnSlide = Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(
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
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.dark, AppColors.darkLight],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 2),

                // Animated logo
                FadeTransition(
                  opacity: _logoFade,
                  child: ScaleTransition(
                    scale: _logoScale,
                    child: Container(
                      width: 130.w,
                      height: 130.w,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(32.r),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.3),
                            blurRadius: 40,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      padding: EdgeInsets.all(10.w),
                      child: Image.asset('assets/images/logo.png', fit: BoxFit.contain),
                    ),
                  ),
                ),
                SizedBox(height: 28.h),

                // Animated title
                SlideTransition(
                  position: _titleSlide,
                  child: FadeTransition(
                    opacity: _titleFade,
                    child: Column(
                      children: [
                        Text(
                          'MWAMBA DRIVER',
                          style: TextStyle(
                            fontSize: 28.sp,
                            fontWeight: FontWeight.w900,
                            color: AppColors.primary,
                            letterSpacing: 2,
                          ),
                        ),
                        SizedBox(height: 8.h),
                        Text(
                          'Espace Chauffeur',
                          style: TextStyle(
                            fontSize: 15.sp,
                            color: Colors.white.withOpacity(0.6),
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const Spacer(flex: 1),

                // Feature chips
                FadeTransition(
                  opacity: _chipsFade,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 40.w),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _FeatureChip(icon: Icons.attach_money_rounded, label: 'Revenus'),
                        _FeatureChip(icon: Icons.route_rounded, label: 'Courses'),
                        _FeatureChip(icon: Icons.star_rounded, label: 'Note'),
                      ],
                    ),
                  ),
                ),

                const Spacer(flex: 1),

                // Animated buttons
                SlideTransition(
                  position: _btnSlide,
                  child: FadeTransition(
                    opacity: _btnFade,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 28.w),
                      child: Column(
                        children: [
                          // Connexion — gradient button
                          GestureDetector(
                            onTap: () => context.go('/login'),
                            child: Container(
                              width: double.infinity,
                              height: 56.h,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: AppColors.primaryGradient,
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
                                borderRadius: BorderRadius.circular(18.r),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withOpacity(0.4),
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
                                    color: AppColors.dark,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: 14.h),

                          // Inscription — outlined
                          GestureDetector(
                            onTap: () => context.go('/register'),
                            child: Container(
                              width: double.infinity,
                              height: 56.h,
                              decoration: BoxDecoration(
                                border: Border.all(color: AppColors.primary.withOpacity(0.5), width: 1.5),
                                borderRadius: BorderRadius.circular(18.r),
                              ),
                              child: Center(
                                child: Text(
                                  AppStrings.register,
                                  style: TextStyle(
                                    fontSize: 16.sp,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                SizedBox(height: 40.h),
              ],
            ),
          ),
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
          width: 52.w,
          height: 52.w,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(color: AppColors.primary.withOpacity(0.15)),
          ),
          child: Icon(icon, color: AppColors.primary, size: 24.sp),
        ),
        SizedBox(height: 8.h),
        Text(
          label,
          style: TextStyle(
            fontSize: 12.sp,
            fontWeight: FontWeight.w500,
            color: Colors.white.withOpacity(0.6),
          ),
        ),
      ],
    );
  }
}
