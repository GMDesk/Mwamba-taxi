import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:pin_code_fields/pin_code_fields.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../bloc/auth_bloc.dart';

class OtpScreen extends StatefulWidget {
  final String phoneNumber;

  const OtpScreen({super.key, required this.phoneNumber});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _otpController = TextEditingController();

  void _verifyOtp() {
    if (_otpController.text.length == 6) {
      context.read<AuthBloc>().add(
        AuthOtpVerified(
          phoneNumber: widget.phoneNumber,
          code: _otpController.text,
        ),
      );
    }
  }

  void _resendOtp() {
    context.read<AuthBloc>().add(
      AuthOtpRequested(phoneNumber: widget.phoneNumber),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Code renvoyé !')),
    );
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocListener<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthAuthenticated) {
            context.go('/home');
          } else if (state is AuthError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message)),
            );
          }
        },
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 12.h),
                // Back button
                GestureDetector(
                  onTap: () => context.pop(),
                  child: Container(
                    width: 44.w,
                    height: 44.w,
                    decoration: BoxDecoration(
                      color: AppColors.inputFill,
                      borderRadius: BorderRadius.circular(14.r),
                    ),
                    child: const Icon(Icons.arrow_back_ios_new, size: 18),
                  ),
                ),
                SizedBox(height: 32.h),

                // Icon
                Container(
                  width: 64.w,
                  height: 64.w,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20.r),
                  ),
                  child: Icon(
                    Icons.sms_outlined,
                    color: AppColors.primaryDark,
                    size: 28.sp,
                  ),
                ),
                SizedBox(height: 24.h),

                Text(
                  'Vérification OTP',
                  style: TextStyle(
                    fontSize: 28.sp,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 8.h),
                RichText(
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: 15.sp,
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                    children: [
                      const TextSpan(text: 'Entrez le code envoyé au '),
                      TextSpan(
                        text: widget.phoneNumber,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 40.h),

                // OTP PIN fields
                PinCodeTextField(
                  appContext: context,
                  length: 6,
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  animationType: AnimationType.fade,
                  pinTheme: PinTheme(
                    shape: PinCodeFieldShape.box,
                    borderRadius: BorderRadius.circular(16.r),
                    fieldHeight: 58.h,
                    fieldWidth: 48.w,
                    activeFillColor: Colors.white,
                    inactiveFillColor: AppColors.inputFill,
                    selectedFillColor: Colors.white,
                    activeColor: AppColors.primary,
                    inactiveColor: Colors.transparent,
                    selectedColor: AppColors.primary,
                  ),
                  enableActiveFill: true,
                  onCompleted: (_) => _verifyOtp(),
                  onChanged: (_) {},
                ),
                SizedBox(height: 32.h),

                BlocBuilder<AuthBloc, AuthState>(
                  builder: (context, state) {
                    return SizedBox(
                      width: double.infinity,
                      height: 56.h,
                      child: ElevatedButton(
                        onPressed: state is AuthLoading ? null : _verifyOtp,
                        child: state is AuthLoading
                            ? SizedBox(
                                height: 24.h,
                                width: 24.h,
                                child: const CircularProgressIndicator(
                                  color: AppColors.textOnPrimary,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : Text(
                                AppStrings.verifyPhone,
                                style: TextStyle(
                                  fontSize: 16.sp,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    );
                  },
                ),
                SizedBox(height: 24.h),

                Center(
                  child: TextButton(
                    onPressed: _resendOtp,
                    child: Text(
                      'Renvoyer le code',
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.secondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
