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
  late final Animation<double> _sloganFade;
  late final Animation<Offset> _sloganSlide;
  late final Animation<double> _btnFade;
  late final Animation<Offset> _btnSlide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _sloganFade = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.15, 0.5, curve: Curves.easeOut)),
    );
    _sloganSlide = Tween(begin: const Offset(0, 0.15), end: Offset.zero).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.15, 0.5, curve: Curves.easeOutCubic)),
    );
    _btnFade = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.5, 1.0, curve: Curves.easeOut)),
    );
    _btnSlide = Tween(begin: const Offset(0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.5, 1.0, curve: Curves.easeOutCubic)),
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
        body: Stack(
          fit: StackFit.expand,
          children: [
            // ── Background photo ──
            Image.asset(
              'assets/images/welcome.webp',
              fit: BoxFit.cover,
            ),

            // ── Dark gradient overlay ──
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.15),
                    Colors.black.withValues(alpha: 0.35),
                    Colors.black.withValues(alpha: 0.75),
                  ],
                  stops: const [0.0, 0.4, 1.0],
                ),
              ),
            ),

            // ── Content ──
            SafeArea(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 28.w),
                child: Column(
                  children: [
                    SizedBox(height: 24.h),

                    // ── Logo ──
                    FadeTransition(
                      opacity: _sloganFade,
                      child: Image.asset(
                        'assets/images/logo.png',
                        width: 150.w,
                        height: 150.w,
                      ),
                    ),

                    SizedBox(height: 20.h),

                    // ── Slogan ──
                    SlideTransition(
                      position: _sloganSlide,
                      child: FadeTransition(
                        opacity: _sloganFade,
                        child: Text(
                          'Votre course,\nnotre engagement.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 30.sp,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            height: 1.3,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                    ),

                    SizedBox(height: 12.h),

                    SlideTransition(
                      position: _sloganSlide,
                      child: FadeTransition(
                        opacity: _sloganFade,
                        child: Text(
                          AppStrings.welcomeSubtitle,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14.sp,
                            color: Colors.white.withValues(alpha: 0.75),
                            height: 1.5,
                          ),
                        ),
                      ),
                    ),

                    const Spacer(),

                    // ── Buttons ──
                    SlideTransition(
                      position: _btnSlide,
                      child: FadeTransition(
                        opacity: _btnFade,
                        child: Column(
                          children: [
                            // Se connecter — solid amber
                            SizedBox(
                              width: double.infinity,
                              height: 56.h,
                              child: ElevatedButton(
                                onPressed: () => context.push('/login'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18.r),
                                  ),
                                ),
                                child: Text(
                                  AppStrings.login,
                                  style: TextStyle(
                                    fontSize: 16.sp,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),

                            SizedBox(height: 12.h),

                            // S'inscrire — outlined white
                            SizedBox(
                              width: double.infinity,
                              height: 56.h,
                              child: OutlinedButton(
                                onPressed: () => context.push('/register'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.5),
                                    width: 1.5,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18.r),
                                  ),
                                ),
                                child: Text(
                                  AppStrings.register,
                                  style: TextStyle(
                                    fontSize: 16.sp,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    SizedBox(height: 36.h),
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
