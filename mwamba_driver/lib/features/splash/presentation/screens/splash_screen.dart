import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _mainController;
  late final AnimationController _pulseController;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<Offset> _textSlide;
  late final Animation<double> _textOpacity;
  late final Animation<double> _lineWidth;
  late final Animation<double> _pulseScale;

  @override
  void initState() {
    super.initState();

    _mainController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _logoScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.0, 0.4, curve: Curves.elasticOut),
      ),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.0, 0.2, curve: Curves.easeOut),
      ),
    );
    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.3, 0.6, curve: Curves.easeOutCubic),
      ),
    );
    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.3, 0.55, curve: Curves.easeOut),
      ),
    );
    _lineWidth = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.55, 0.8, curve: Curves.easeInOut),
      ),
    );
    _pulseScale = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _mainController.forward();
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) _pulseController.repeat(reverse: true);
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) _navigate();
    });
  }

  void _navigate() {
    try {
      final state = context.read<AuthBloc>().state;
      if (state is Authenticated) {
        context.go('/home');
      } else if (state is AuthSessionExpiredState) {
        context.go('/welcome');
      } else {
        context.go('/welcome');
      }
    } catch (_) {
      context.go('/welcome');
    }
  }

  @override
  void dispose() {
    _mainController.dispose();
    _pulseController.dispose();
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
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.dark,
                AppColors.darkLight,
              ],
            ),
          ),
          child: Stack(
            children: [
              // Decorative circles
              Positioned(
                top: -80.w,
                right: -60.w,
                child: _decorativeCircle(220.w, AppColors.primary.withOpacity(0.06)),
              ),
              Positioned(
                bottom: -100.w,
                left: -70.w,
                child: _decorativeCircle(280.w, AppColors.primary.withOpacity(0.04)),
              ),
              Positioned(
                top: MediaQuery.of(context).size.height * 0.25,
                left: -40.w,
                child: _decorativeCircle(120.w, AppColors.primary.withOpacity(0.05)),
              ),

              // Main content
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Pulsing + scaling logo
                    AnimatedBuilder(
                      animation: Listenable.merge([_logoScale, _pulseScale]),
                      builder: (context, child) => Opacity(
                        opacity: _logoOpacity.value,
                        child: Transform.scale(
                          scale: _logoScale.value * _pulseScale.value,
                          child: child,
                        ),
                      ),
                      child: Container(
                        width: 140.w,
                        height: 140.w,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(32.r),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.3),
                              blurRadius: 40,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        padding: EdgeInsets.all(12.w),
                        child: Image.asset(
                          'assets/images/logo.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    SizedBox(height: 32.h),

                    // Text with slide animation
                    SlideTransition(
                      position: _textSlide,
                      child: FadeTransition(
                        opacity: _textOpacity,
                        child: Column(
                          children: [
                            Text(
                              'MWAMBA DRIVER',
                              style: TextStyle(
                                fontSize: 26.sp,
                                fontWeight: FontWeight.w900,
                                color: AppColors.primary,
                                letterSpacing: 3,
                              ),
                            ),
                            SizedBox(height: 8.h),
                            Text(
                              'Espace Chauffeur',
                              style: TextStyle(
                                fontSize: 14.sp,
                                fontWeight: FontWeight.w400,
                                color: Colors.white.withOpacity(0.6),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 40.h),

                    // Animated line
                    AnimatedBuilder(
                      animation: _lineWidth,
                      builder: (context, _) => Container(
                        width: 60.w * _lineWidth.value,
                        height: 3,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Bottom version text
              Positioned(
                bottom: 40.h + MediaQuery.of(context).padding.bottom,
                left: 0,
                right: 0,
                child: FadeTransition(
                  opacity: _textOpacity,
                  child: Text(
                    'v1.0.0',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: Colors.white.withOpacity(0.25),
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _decorativeCircle(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }
}
