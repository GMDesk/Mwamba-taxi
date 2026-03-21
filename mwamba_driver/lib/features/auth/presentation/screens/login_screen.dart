import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_alert.dart';
import '../bloc/auth_bloc.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      body: BlocListener<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is Authenticated) context.go('/home');
          if (state is OtpSent) context.go('/otp', extra: state.phone);
          if (state is AuthError) {
            AppAlert.show(context,
              message: state.message,
              title: 'Connexion échouée',
            );
          }
        },
        child: Column(
          children: [
            // Dark gradient header — compact
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.dark, AppColors.darkLight],
                ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(36),
                  bottomRight: Radius.circular(36),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 28.h),
                  child: Column(
                    children: [
                      // Back + logo row
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () => context.go('/welcome'),
                            child: Container(
                              width: 40.w,
                              height: 40.w,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(12.r),
                              ),
                              child: const Icon(Icons.arrow_back_ios_new, size: 17, color: Colors.white),
                            ),
                          ),
                          const Spacer(),
                          Container(
                            width: 42.w,
                            height: 42.w,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12.r),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withOpacity(0.3),
                                  blurRadius: 12,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            padding: EdgeInsets.all(4.w),
                            child: Image.asset('assets/images/logo.png', fit: BoxFit.contain),
                          ),
                        ],
                      ),
                      SizedBox(height: 20.h),
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
                        'Connectez-vous à votre espace chauffeur',
                        style: TextStyle(
                          fontSize: 13.sp,
                          color: Colors.white.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Form on dark background
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(24.w, 32.h, 24.w, 24.h),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Numéro de téléphone',
                        style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.7)),
                      ),
                      SizedBox(height: 8.h),
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: '097 000 0000',
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                          prefixText: '+243 ',
                          prefixStyle: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
                          prefixIcon: Icon(Icons.phone_outlined, color: AppColors.primary.withOpacity(0.7)),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.06),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16.r),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16.r),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16.r),
                            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                          ),
                        ),
                        validator: (v) => (v == null || v.isEmpty) ? 'Requis' : null,
                      ),
                      SizedBox(height: 20.h),

                      Text(
                        'Mot de passe',
                        style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.7)),
                      ),
                      SizedBox(height: 8.h),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: '••••••',
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                          prefixIcon: Icon(Icons.lock_outlined, color: AppColors.primary.withOpacity(0.7)),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.06),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16.r),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16.r),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16.r),
                            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                          ),
                        ),
                        validator: (v) => (v == null || v.isEmpty) ? 'Requis' : null,
                      ),
                      SizedBox(height: 36.h),

                      // Yellow gradient login button
                      BlocBuilder<AuthBloc, AuthState>(
                        builder: (context, state) {
                          final loading = state is AuthLoading;
                          return GestureDetector(
                            onTap: loading
                                ? null
                                : () {
                                    if (_formKey.currentState!.validate()) {
                                      context.read<AuthBloc>().add(LoginEvent(
                                            phone: '+243${_phoneController.text.trim()}',
                                            password: _passwordController.text,
                                          ));
                                    }
                                  },
                            child: Container(
                              width: double.infinity,
                              height: 56.h,
                              decoration: BoxDecoration(
                                gradient: loading
                                    ? null
                                    : const LinearGradient(
                                        colors: [AppColors.primaryDark, AppColors.primary],
                                      ),
                                color: loading ? Colors.grey.shade700 : null,
                                borderRadius: BorderRadius.circular(18.r),
                                boxShadow: loading
                                    ? []
                                    : [
                                        BoxShadow(
                                          color: AppColors.primaryDark.withOpacity(0.5),
                                          blurRadius: 14,
                                          offset: const Offset(0, 5),
                                        ),
                                      ],
                              ),
                              child: Center(
                                child: loading
                                    ? SizedBox(
                                        width: 24.w,
                                        height: 24.w,
                                        child: const CircularProgressIndicator(color: AppColors.textOnPrimary, strokeWidth: 2.5),
                                      )
                                    : Text(
                                        AppStrings.login,
                                        style: TextStyle(
                                          fontSize: 16.sp,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.textOnPrimary,
                                        ),
                                      ),
                              ),
                            ),
                          );
                        },
                      ),

                      SizedBox(height: 18.h),

                      // OTP button — styled outline
                      Center(
                        child: GestureDetector(
                          onTap: () {
                            final phone = _phoneController.text.trim();
                            if (phone.isNotEmpty) {
                              context.read<AuthBloc>().add(RequestOtpEvent(phone: '+243$phone'));
                            }
                          },
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
                            decoration: BoxDecoration(
                              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                              borderRadius: BorderRadius.circular(14.r),
                            ),
                            child: Text(
                              'Se connecter par OTP',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                                fontSize: 14.sp,
                              ),
                            ),
                          ),
                        ),
                      ),

                      SizedBox(height: 20.h),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Pas encore de compte ?',
                            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13.sp),
                          ),
                          TextButton(
                            onPressed: () => context.go('/register'),
                            child: Text(
                              'S\'inscrire',
                              style: TextStyle(
                                color: AppColors.primary,
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
    );
  }
}
