import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';

class RatingScreen extends StatefulWidget {
  final String rideId;

  const RatingScreen({super.key, required this.rideId});

  @override
  State<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends State<RatingScreen> {
  final ApiClient _api = getIt<ApiClient>();
  final _commentController = TextEditingController();
  int _rating = 5;
  bool _isSubmitting = false;

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);
    try {
      await _api.dio.post(
        ApiConstants.createReview,
        data: {
          'ride_id': widget.rideId,
          'rating': _rating,
          'comment': _commentController.text.trim(),
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Merci pour votre avis !')),
        );
        context.go('/home');
      }
    } catch (e) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de l\'envoi')),
        );
      }
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: 24.w),
          child: Column(
            children: [
              SizedBox(height: 12.h),

              // Back button
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () => context.go('/home'),
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
              ),
              SizedBox(height: 28.h),

              // Emoji icon
              Container(
                width: 80.w,
                height: 80.w,
                decoration: BoxDecoration(
                  color: AppColors.starFilled.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(24.r),
                ),
                child: Center(
                  child: Text('⭐', style: TextStyle(fontSize: 36.sp)),
                ),
              ),
              SizedBox(height: 24.h),

              Text(
                'Comment était votre\ncourse ?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26.sp,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  height: 1.3,
                ),
              ),
              SizedBox(height: 8.h),
              Text(
                'Votre avis nous aide à améliorer le service',
                style: TextStyle(
                  fontSize: 14.sp,
                  color: AppColors.textSecondary,
                ),
              ),
              SizedBox(height: 32.h),

              // Star rating
              Container(
                padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20.r),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.shadow,
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) {
                        return GestureDetector(
                          onTap: () => setState(() => _rating = index + 1),
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6.w),
                            child: Icon(
                              index < _rating ? Icons.star_rounded : Icons.star_outline_rounded,
                              size: 44.sp,
                              color: index < _rating
                                  ? AppColors.starFilled
                                  : AppColors.starEmpty,
                            ),
                          ),
                        );
                      }),
                    ),
                    SizedBox(height: 8.h),
                    Text(
                      _getRatingText(),
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 28.h),

              // Comment field
              TextField(
                controller: _commentController,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Laisser un commentaire (optionnel)',
                  alignLabelWithHint: true,
                ),
              ),
              SizedBox(height: 32.h),

              // Submit button
              SizedBox(
                width: double.infinity,
                height: 56.h,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  child: _isSubmitting
                      ? SizedBox(
                          height: 24.h,
                          width: 24.h,
                          child: const CircularProgressIndicator(
                            color: AppColors.textOnPrimary,
                            strokeWidth: 2.5,
                          ),
                        )
                      : Text(
                          'Envoyer mon avis',
                          style: TextStyle(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
              SizedBox(height: 12.h),
              TextButton(
                onPressed: () => context.go('/home'),
                child: Text(
                  'Passer',
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              SizedBox(height: 16.h),
            ],
          ),
        ),
      ),
    );
  }

  String _getRatingText() {
    switch (_rating) {
      case 1: return 'Très mauvais';
      case 2: return 'Mauvais';
      case 3: return 'Moyen';
      case 4: return 'Bien';
      case 5: return 'Excellent !';
      default: return '';
    }
  }
}
