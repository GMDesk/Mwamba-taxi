import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:pin_code_fields/pin_code_fields.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_alert.dart';
import '../bloc/auth_bloc.dart';

class OtpScreen extends StatefulWidget {
  final String phoneNumber;

  const OtpScreen({super.key, required this.phoneNumber});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _otpController = TextEditingController();

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.otpVerification)),
      body: BlocListener<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is Authenticated) context.go('/home');
          if (state is AuthError) {
            AppAlert.show(context,
              message: state.message,
              title: 'Vérification échouée',
            );
          }
        },
        child: Padding(
          padding: EdgeInsets.all(24.w),
          child: Column(
            children: [
              SizedBox(height: 32.h),
              Icon(Icons.sms_outlined, size: 64.sp, color: AppColors.primary),
              SizedBox(height: 24.h),

              Text(
                AppStrings.enterOtp,
                style: TextStyle(fontSize: 16.sp, color: AppColors.textSecondary),
              ),
              SizedBox(height: 8.h),
              Text(
                widget.phoneNumber,
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 32.h),

              PinCodeTextField(
                appContext: context,
                length: 6,
                controller: _otpController,
                keyboardType: TextInputType.number,
                animationType: AnimationType.fade,
                pinTheme: PinTheme(
                  shape: PinCodeFieldShape.box,
                  borderRadius: BorderRadius.circular(8.r),
                  fieldHeight: 50.h,
                  fieldWidth: 45.w,
                  activeFillColor: AppColors.surface,
                  selectedFillColor: AppColors.inputFill,
                  inactiveFillColor: AppColors.inputFill,
                  activeColor: AppColors.primary,
                  selectedColor: AppColors.primary,
                  inactiveColor: AppColors.border,
                ),
                enableActiveFill: true,
                onCompleted: (code) {
                  context.read<AuthBloc>().add(VerifyOtpEvent(
                        phone: widget.phoneNumber,
                        code: code,
                      ));
                },
                onChanged: (_) {},
              ),

              SizedBox(height: 24.h),

              BlocBuilder<AuthBloc, AuthState>(
                builder: (context, state) {
                  final loading = state is AuthLoading;
                  return ElevatedButton(
                    onPressed: loading
                        ? null
                        : () {
                            if (_otpController.text.length == 6) {
                              context.read<AuthBloc>().add(VerifyOtpEvent(
                                    phone: widget.phoneNumber,
                                    code: _otpController.text,
                                  ));
                            }
                          },
                    child: loading
                        ? const CircularProgressIndicator(color: AppColors.textOnPrimary)
                        : const Text(AppStrings.verify),
                  );
                },
              ),

              SizedBox(height: 16.h),
              TextButton(
                onPressed: () {
                  context.read<AuthBloc>().add(
                      RequestOtpEvent(phone: widget.phoneNumber));
                },
                child: const Text('Renvoyer le code'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
