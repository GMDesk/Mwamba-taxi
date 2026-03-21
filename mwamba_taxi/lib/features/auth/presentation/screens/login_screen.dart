import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../bloc/auth_bloc.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _login() {
    if (_formKey.currentState!.validate()) {
      context.read<AuthBloc>().add(
            AuthLoginRequested(
              phoneNumber: _phoneController.text.trim(),
              password: _passwordController.text,
            ),
          );
    }
  }

  void _loginWithOtp() {
    final phone = _phoneController.text.trim();
    if (phone.isNotEmpty) {
      context.read<AuthBloc>().add(
            AuthOtpRequested(phoneNumber: phone),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: BlocListener<AuthBloc, AuthState>(
          listener: (context, state) {
            if (state is AuthAuthenticated) {
              if (mounted) context.go('/home');
            } else if (state is AuthOtpSent) {
              if (mounted) context.push('/otp', extra: state.phoneNumber);
            } else if (state is AuthError) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(state.message),
                    backgroundColor: AppColors.error,
                  ),
                );
              }
            }
          },
          child: Column(
            children: [
              // ── Compact gradient header ──
              Container(
                width: double.infinity,
                padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primaryDark, AppColors.primary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(32),
                    bottomRight: Radius.circular(32),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryDark.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
                  child: Column(
                    children: [
                      // Back button
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () => context.pop(),
                            child: Container(
                              width: 40.w,
                              height: 40.w,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12.r),
                              ),
                              child: const Icon(Icons.arrow_back_ios_new, size: 17, color: Colors.white),
                            ),
                          ),
                          const Spacer(),
                          // Small logo
                          Container(
                            width: 40.w,
                            height: 40.w,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                            padding: EdgeInsets.all(4.w),
                            child: Image.asset('assets/images/logo.png', fit: BoxFit.contain),
                          ),
                        ],
                      ),
                      SizedBox(height: 16.h),
                      Text(
                        'Bon retour ! 👋',
                        style: TextStyle(
                          fontSize: 24.sp,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        'Connectez-vous pour continuer',
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // -- Form section --
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(24.w, 32.h, 24.w, 24.h),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Phone
                        Text(
                          'Numéro de téléphone',
                          style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        SizedBox(height: 8.h),
                        TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            hintText: AppStrings.phoneHint,
                            prefixIcon: Container(
                              width: 48.w,
                              alignment: Alignment.center,
                              child: Text('🇨🇩', style: TextStyle(fontSize: 20.sp)),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Le numéro de téléphone est requis';
                            }
                            return null;
                          },
                        ),
                        SizedBox(height: 20.h),

                        // Password
                        Text(
                          'Mot de passe',
                          style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        SizedBox(height: 8.h),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            hintText: '••••••••',
                            prefixIcon: const Icon(Icons.lock_outlined),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              ),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Le mot de passe est requis';
                            }
                            return null;
                          },
                        ),
                        SizedBox(height: 32.h),

                        // Login button — gradient
                        BlocBuilder<AuthBloc, AuthState>(
                          builder: (context, state) {
                            return GestureDetector(
                              onTap: state is AuthLoading ? null : _login,
                              child: Container(
                                width: double.infinity,
                                height: 56.h,
                                decoration: BoxDecoration(
                                  gradient: state is AuthLoading
                                      ? null
                                      : const LinearGradient(
                                          colors: [Color(0xFFB71C1C), Color(0xFFE53935)],
                                        ),
                                  color: state is AuthLoading ? Colors.grey.shade300 : null,
                                  borderRadius: BorderRadius.circular(18.r),
                                  boxShadow: state is AuthLoading
                                      ? []
                                      : [
                                          BoxShadow(
                                            color: const Color(0xFFB71C1C).withOpacity(0.35),
                                            blurRadius: 14,
                                            offset: const Offset(0, 5),
                                          ),
                                        ],
                                ),
                                child: Center(
                                  child: state is AuthLoading
                                      ? SizedBox(
                                          width: 24.w,
                                          height: 24.w,
                                          child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                        )
                                      : Text(
                                          AppStrings.login,
                                          style: TextStyle(
                                            fontSize: 16.sp,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                        ),
                                ),
                              ),
                            );
                          },
                        ),
                        SizedBox(height: 24.h),

                        // Divider
                        Row(
                          children: [
                            Expanded(child: Divider(color: AppColors.border)),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16.w),
                              child: Text('ou', style: TextStyle(color: AppColors.textHint, fontSize: 13.sp)),
                            ),
                            Expanded(child: Divider(color: AppColors.border)),
                          ],
                        ),
                        SizedBox(height: 24.h),

                        // OTP Login
                        GestureDetector(
                          onTap: _loginWithOtp,
                          child: Container(
                            width: double.infinity,
                            height: 56.h,
                            decoration: BoxDecoration(
                              border: Border.all(color: AppColors.border, width: 1.5),
                              borderRadius: BorderRadius.circular(18.r),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.sms_outlined, size: 20.sp, color: AppColors.textSecondary),
                                SizedBox(width: 10.w),
                                Text(
                                  'Se connecter avec un code OTP',
                                  style: TextStyle(
                                    fontSize: 15.sp,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(height: 32.h),

                        // Register link
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              AppStrings.noAccount,
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 14.sp),
                            ),
                            TextButton(
                              onPressed: () => context.pushReplacement('/register'),
                              child: Text(
                                AppStrings.register,
                                style: TextStyle(
                                  color: AppColors.primaryDark,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
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
}

