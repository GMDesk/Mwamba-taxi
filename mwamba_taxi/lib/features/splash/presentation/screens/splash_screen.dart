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
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _logoScale;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.5, curve: Curves.easeOut)),
    );
    _logoScale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic)),
    );

    _ctrl.forward();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) _navigate();
    });
  }

  void _navigate() {
    try {
      final state = context.read<AuthBloc>().state;
      if (state is AuthAuthenticated) {
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
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.primary,
        body: Center(
          child: ScaleTransition(
            scale: _logoScale,
            child: FadeTransition(
              opacity: _logoOpacity,
              child: Image.asset(
                'assets/images/logo.png',
                width: 150.w,
                height: 150.w,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
