import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_strings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_alert.dart';
import '../bloc/auth_bloc.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _vehicleBrandCtrl = TextEditingController();
  final _vehicleModelCtrl = TextEditingController();
  final _vehicleColorCtrl = TextEditingController();
  final _licensePlateCtrl = TextEditingController();
  String _selectedCategory = 'economy';

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _passwordCtrl.dispose();
    _vehicleBrandCtrl.dispose();
    _vehicleModelCtrl.dispose();
    _vehicleColorCtrl.dispose();
    _licensePlateCtrl.dispose();
    super.dispose();
  }

  InputDecoration _fieldDeco(String label, IconData icon) {
    return InputDecoration(
      hintText: label,
      hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
      prefixIcon: Icon(icon, color: AppColors.primary.withOpacity(0.7)),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      body: BlocListener<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is Authenticated) context.go('/home');
          if (state is AuthError) {
            AppAlert.show(context,
              message: state.message,
              title: 'Inscription échouée',
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
                  padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
                  child: Column(
                    children: [
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
                      SizedBox(height: 16.h),
                      Text(
                        'Devenir Chauffeur',
                        style: TextStyle(
                          fontSize: 24.sp,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        'Créez votre compte pour commencer',
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

            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(24.w, 28.h, 24.w, 24.h),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Personal info section
                      _SectionHeader(icon: Icons.person, title: 'Informations personnelles'),
                      SizedBox(height: 14.h),
                      TextFormField(
                        controller: _firstNameCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: _fieldDeco(AppStrings.firstName, Icons.person),
                        validator: (v) => (v == null || v.isEmpty) ? 'Requis' : null,
                      ),
                      SizedBox(height: 12.h),
                      TextFormField(
                        controller: _lastNameCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: _fieldDeco(AppStrings.lastName, Icons.person_outline),
                        validator: (v) => (v == null || v.isEmpty) ? 'Requis' : null,
                      ),
                      SizedBox(height: 12.h),
                      TextFormField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        style: const TextStyle(color: Colors.white),
                        decoration: _fieldDeco(AppStrings.phone, Icons.phone).copyWith(
                          prefixText: '+243 ',
                          prefixStyle: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
                        ),
                        validator: (v) => (v == null || v.isEmpty) ? 'Requis' : null,
                      ),
                      SizedBox(height: 12.h),
                      TextFormField(
                        controller: _passwordCtrl,
                        obscureText: true,
                        style: const TextStyle(color: Colors.white),
                        decoration: _fieldDeco(AppStrings.password, Icons.lock),
                        validator: (v) => (v == null || v.length < 6) ? 'Minimum 6 caractères' : null,
                      ),

                      SizedBox(height: 28.h),
                      _SectionHeader(icon: Icons.directions_car, title: AppStrings.vehicleInfo),
                      SizedBox(height: 14.h),
                      TextFormField(
                        controller: _vehicleBrandCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: _fieldDeco('Marque du véhicule', Icons.directions_car),
                        validator: (v) => (v == null || v.isEmpty) ? 'Requis' : null,
                      ),
                      SizedBox(height: 12.h),
                      TextFormField(
                        controller: _vehicleModelCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: _fieldDeco('Modèle du véhicule', Icons.directions_car_outlined),
                        validator: (v) => (v == null || v.isEmpty) ? 'Requis' : null,
                      ),
                      SizedBox(height: 12.h),
                      TextFormField(
                        controller: _vehicleColorCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: _fieldDeco('Couleur du véhicule', Icons.palette),
                      ),
                      SizedBox(height: 12.h),
                      TextFormField(
                        controller: _licensePlateCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: _fieldDeco('Plaque d\'immatriculation', Icons.credit_card),
                        validator: (v) => (v == null || v.isEmpty) ? 'Requis' : null,
                      ),
                      SizedBox(height: 12.h),
                      DropdownButtonFormField<String>(
                        value: _selectedCategory,
                        decoration: _fieldDeco('Cat\u00e9gorie du v\u00e9hicule', Icons.category),
                        dropdownColor: AppColors.darkLight,
                        style: const TextStyle(color: Colors.white),
                        items: const [
                          DropdownMenuItem(value: 'economy', child: Text('\u00c9conomie')),
                          DropdownMenuItem(value: 'comfort', child: Text('Confort')),
                          DropdownMenuItem(value: 'van', child: Text('Van')),
                        ],
                        onChanged: (v) => setState(() => _selectedCategory = v ?? 'economy'),
                      ),

                      SizedBox(height: 32.h),

                      // Yellow gradient register button
                      BlocBuilder<AuthBloc, AuthState>(
                        builder: (context, state) {
                          final loading = state is AuthLoading;
                          return GestureDetector(
                            onTap: loading
                                ? null
                                : () {
                                    if (_formKey.currentState!.validate()) {
                                      context.read<AuthBloc>().add(RegisterEvent(
                                            phone: '+243${_phoneCtrl.text.trim()}',
                                            firstName: _firstNameCtrl.text.trim(),
                                            lastName: _lastNameCtrl.text.trim(),
                                            password: _passwordCtrl.text,
                                            vehicleBrand: _vehicleBrandCtrl.text.trim(),
                                            vehicleModel: _vehicleModelCtrl.text.trim(),
                                            vehicleColor: _vehicleColorCtrl.text.trim(),
                                            licensePlate: _licensePlateCtrl.text.trim(),
                                            vehicleCategory: _selectedCategory,
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
                                        AppStrings.register,
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Déjà un compte ?',
                            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13.sp),
                          ),
                          TextButton(
                            onPressed: () => context.go('/login'),
                            child: Text(
                              'Se connecter',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 16.h),
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

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.primary, size: 18.sp),
        ),
        SizedBox(width: 10.w),
        Text(
          title,
          style: TextStyle(
            fontSize: 15.sp,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
      ],
    );
  }
}
