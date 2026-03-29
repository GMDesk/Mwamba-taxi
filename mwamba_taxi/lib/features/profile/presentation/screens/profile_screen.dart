import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ApiClient _api = getIt<ApiClient>();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _promoController = TextEditingController();
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();

  Map<String, dynamic>? _profile;
  bool _loading = true;
  bool _saving = false;
  File? _pickedImage;
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _promoController.dispose();
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final resp = await _api.dio.get(ApiConstants.profile);
      final data = resp.data as Map<String, dynamic>;
      setState(() {
        _profile = data;
        _nameController.text = data['full_name'] ?? '';
        _emailController.text = data['email'] ?? '';
        _avatarUrl = data['avatar'];
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (picked != null && mounted) {
      setState(() => _pickedImage = File(picked.path));
    }
  }

  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 20.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Changer la photo',
                style: TextStyle(
                  fontSize: 17.sp,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 20.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ImageSourceOption(
                    icon: Icons.camera_alt_rounded,
                    label: 'Caméra',
                    onTap: () {
                      Navigator.pop(context);
                      _pickImage(ImageSource.camera);
                    },
                  ),
                  _ImageSourceOption(
                    icon: Icons.photo_library_rounded,
                    label: 'Galerie',
                    onTap: () {
                      Navigator.pop(context);
                      _pickImage(ImageSource.gallery);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final formData = FormData.fromMap({
        'full_name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        if (_pickedImage != null)
          'avatar': await MultipartFile.fromFile(
            _pickedImage!.path,
            filename: 'avatar.jpg',
          ),
      });

      await _api.dio.patch(
        ApiConstants.profile,
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Profil mis à jour !'),
            backgroundColor: AppColors.success,
          ),
        );
        _pickedImage = null;
        _loadProfile();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Erreur lors de la mise à jour'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changePassword() async {
    final old = _oldPasswordController.text;
    final newPwd = _newPasswordController.text;
    if (old.isEmpty || newPwd.length < 6) return;

    try {
      await _api.dio.post(
        ApiConstants.changePassword,
        data: {'old_password': old, 'new_password': newPwd},
      );
      if (mounted) {
        _oldPasswordController.clear();
        _newPasswordController.clear();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Mot de passe modifié !'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Ancien mot de passe incorrect'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _applyPromo() async {
    final code = _promoController.text.trim();
    if (code.isEmpty) return;
    try {
      final resp = await _api.dio.post(ApiConstants.validatePromo, data: {'code': code});
      final data = resp.data as Map<String, dynamic>;
      if (mounted) {
        _promoController.clear();
        final discount = data['estimated_discount'] ?? data['discount_value'] ?? '';
        final desc = data['description'] ?? '';
        final msg = discount.toString().isNotEmpty && discount != '0'
            ? 'Code "$code" appliqué ! Réduction : $discount CDF\n$desc'
            : 'Code "$code" valide ! ${desc}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Code promo invalide ou expiré'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showReferralSheet() {
    final code = _profile?['referral_code'] as String? ?? '';
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(24.w, 20.h, 24.w, 32.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40.w,
              height: 4.h,
              margin: EdgeInsets.only(bottom: 20.h),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2.r),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primaryDark.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.people_alt_rounded,
                  color: AppColors.primaryDark, size: 32.sp),
            ),
            SizedBox(height: 16.h),
            Text(
              'Parrainez vos amis',
              style: TextStyle(
                fontSize: 20.sp,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'Partagez votre code et gagnez des bonus\npour chaque ami qui s\'inscrit.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.sp,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            SizedBox(height: 24.h),
            // Code box
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 18.h),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primaryDark, AppColors.primary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16.r),
              ),
              child: Column(
                children: [
                  Text(
                    'Votre code de parrainage',
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: Colors.white.withOpacity(0.85),
                    ),
                  ),
                  SizedBox(height: 6.h),
                  Text(
                    code.isNotEmpty ? code : '--------',
                    style: TextStyle(
                      fontSize: 28.sp,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 6,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16.h),
            // Copy button
            SizedBox(
              width: double.infinity,
              height: 56.h,
              child: OutlinedButton.icon(
                onPressed: code.isNotEmpty
                    ? () {
                        Clipboard.setData(ClipboardData(text: code));
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Code "$code" copié !'),
                            backgroundColor: AppColors.success,
                          ),
                        );
                      }
                    : null,
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Copier le code'),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                      color: AppColors.primaryDark, width: 1.5),
                  foregroundColor: AppColors.primaryDark,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18.r),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _logout() async {
    await _api.clearTokens();
    if (mounted) context.go('/welcome');
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F6FA),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _profile == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, size: 48.sp,
                            color: AppColors.textHint),
                        SizedBox(height: 12.h),
                        const Text('Erreur de chargement'),
                        SizedBox(height: 16.h),
                        ElevatedButton(
                          onPressed: () {
                            setState(() => _loading = true);
                            _loadProfile();
                          },
                          child: const Text('Réessayer'),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    child: Column(
                      children: [
                        _buildHeader(),
                        _buildStatsRow(),
                        _buildEditForm(),
                        _buildMenuSection(),
                        _buildLogoutButton(),
                        SizedBox(height: 32.h),
                      ],
                    ),
                  ),
      ),
    );
  }

  // ── Yellow branded header with avatar ──
  Widget _buildHeader() {
    return Container(
      width: double.infinity,
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
            color: AppColors.primaryDark.withOpacity(0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 6.h, 16.w, 16.h),
          child: Column(
            children: [
              // Top row: back + title + spacer
              Row(
                children: [
                  GestureDetector(
                    onTap: () => context.go('/home'),
                    child: Container(
                      width: 40.w,
                      height: 40.w,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      child: Icon(
                        Icons.arrow_back_ios_new,
                        size: 17,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Mon Profil',
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  SizedBox(width: 40.w),
                ],
              ),
              SizedBox(height: 20.h),

              // Avatar with camera overlay
              GestureDetector(
                onTap: _showImageSourceSheet,
                child: Stack(
                  children: [
                    Container(
                      width: 96.w,
                      height: 96.w,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: _pickedImage != null
                            ? Image.file(_pickedImage!, fit: BoxFit.cover)
                            : _avatarUrl != null && _avatarUrl!.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: _avatarUrl!.startsWith('http')
                                        ? _avatarUrl!
                                        : '${ApiConstants.baseUrl.replaceAll('/api/v1', '')}$_avatarUrl',
                                    fit: BoxFit.cover,
                                    placeholder: (_, __) =>
                                        _buildInitialsAvatar(),
                                    errorWidget: (_, __, ___) =>
                                        _buildInitialsAvatar(),
                                  )
                                : _buildInitialsAvatar(),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 32.w,
                        height: 32.w,
                        decoration: BoxDecoration(
                          color: AppColors.secondary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: Icon(
                          Icons.camera_alt_rounded,
                          size: 15.sp,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 14.h),

              Text(
                _profile!['full_name'] ?? '',
                style: TextStyle(
                  fontSize: 20.sp,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 4.h),
              Text(
                _profile!['phone_number'] ?? '',
                style: TextStyle(
                  fontSize: 14.sp,
                  color: Colors.white.withOpacity(0.85),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInitialsAvatar() {
    final name = _profile?['full_name'] as String? ?? '';
    final parts = name.trim().split(' ');
    final initials = parts.length >= 2
        ? '${parts.first[0]}${parts.last[0]}'.toUpperCase()
        : name.isNotEmpty
            ? name[0].toUpperCase()
            : '?';
    return Container(
      color: Colors.white,
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            fontSize: 34.sp,
            fontWeight: FontWeight.w800,
            color: AppColors.primaryDark,
          ),
        ),
      ),
    );
  }

  // ── Stats row ──
  Widget _buildStatsRow() {
    final totalRides = _profile?['total_rides'] ?? 0;
    final rating = _profile?['avg_rating'] ?? 0;

    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 0),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 16.h),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            _StatItem(
              icon: Icons.local_taxi_rounded,
              value: '$totalRides',
              label: 'Courses',
              color: const Color(0xFFE53935),
            ),
            Container(width: 1, height: 40.h, color: AppColors.divider),
            _StatItem(
              icon: Icons.star_rounded,
              value: (rating is num && rating > 0) ? rating.toStringAsFixed(1) : '—',
              label: 'Note',
              color: AppColors.primaryDark,
            ),
            Container(width: 1, height: 40.h, color: AppColors.divider),
            _StatItem(
              icon: Icons.card_giftcard_rounded,
              value: _profile?['referral_code'] != null ? '1' : '0',
              label: 'Parrainages',
              color: AppColors.success,
            ),
          ],
        ),
      ),
    );
  }

  // ── Editable form section ──
  Widget _buildEditForm() {
    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 24.h, 20.w, 0),
      child: Form(
        key: _formKey,
        child: Container(
          padding: EdgeInsets.all(20.w),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20.r),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Informations personnelles',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 18.h),

              // Full Name
              _buildTextField(
                controller: _nameController,
                label: 'Nom complet',
                icon: Icons.person_outlined,
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Le nom est requis'
                    : null,
              ),
              SizedBox(height: 14.h),

              // Email
              _buildTextField(
                controller: _emailController,
                label: 'Adresse e-mail',
                icon: Icons.email_outlined,
                hint: 'Pour recevoir les notifications',
                keyboardType: TextInputType.emailAddress,
              ),
              SizedBox(height: 14.h),

              // Phone (read-only)
              _buildTextField(
                label: 'Téléphone',
                icon: Icons.phone_outlined,
                initialValue: _profile!['phone_number'] ?? '',
                readOnly: true,
              ),
              SizedBox(height: 22.h),

              // Save button
              SizedBox(
                width: double.infinity,
                height: 56.h,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: _saving
                        ? null
                        : const LinearGradient(
                            colors: [AppColors.primaryDark, AppColors.primary],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                    color: _saving ? Colors.grey.shade300 : null,
                    borderRadius: BorderRadius.circular(18.r),
                    boxShadow: _saving
                        ? []
                        : [
                            BoxShadow(
                              color: AppColors.primaryDark.withOpacity(0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                  ),
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _saveProfile,
                    icon: _saving
                        ? SizedBox(
                            width: 20.w,
                            height: 20.w,
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_rounded, size: 20),
                    label: Text(_saving
                        ? 'Enregistrement...'
                        : 'Enregistrer les modifications'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18.r),
                      ),
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

  Widget _buildTextField({
    TextEditingController? controller,
    required String label,
    required IconData icon,
    String? hint,
    String? initialValue,
    bool readOnly = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      initialValue: controller == null ? initialValue : null,
      readOnly: readOnly,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20.sp),
        filled: true,
        fillColor: readOnly
            ? AppColors.textHint.withOpacity(0.08)
            : const Color(0xFFF8F9FC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14.r),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14.r),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14.r),
          borderSide: const BorderSide(color: AppColors.secondary, width: 1.5),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
      ),
    );
  }

  // ── Menu section ──
  Widget _buildMenuSection() {
    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            _MenuItem(
              icon: Icons.lock_outline_rounded,
              title: 'Changer le mot de passe',
              onTap: _showChangePasswordDialog,
            ),
            _divider(),
            _MenuItem(
              icon: Icons.history_rounded,
              title: 'Historique des courses',
              onTap: () => context.go('/history'),
            ),
            _divider(),
            _MenuItem(
              icon: Icons.card_giftcard_rounded,
              title: 'Code promo',
              onTap: _showPromoDialog,
            ),
            _divider(),
            _MenuItem(
              icon: Icons.share_rounded,
              title: 'Parrainage',
              subtitle: _profile!['referral_code'] != null
                  ? 'Code: ${_profile!['referral_code']}'
                  : null,
              onTap: _showReferralSheet,
            ),
            _divider(),
            _MenuItem(
              icon: Icons.info_outline_rounded,
              title: 'À propos',
              onTap: () {},
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider() => Divider(
        height: 1,
        indent: 60.w,
        color: Colors.grey.shade100,
      );

  // ── Logout button ──
  Widget _buildLogoutButton() {
    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 24.h, 20.w, 0),
      child: SizedBox(
        width: double.infinity,
        height: 56.h,
        child: OutlinedButton.icon(
          onPressed: _logout,
          icon: Icon(Icons.logout_rounded,
              color: AppColors.error, size: 20.sp),
          label: Text(
            'Se déconnecter',
            style: TextStyle(
              color: AppColors.error,
              fontWeight: FontWeight.w600,
              fontSize: 16.sp,
            ),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: AppColors.error.withOpacity(0.4)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18.r),
            ),
          ),
        ),
      ),
    );
  }

  // ── Dialogs ──
  void _showChangePasswordDialog() {
    _oldPasswordController.clear();
    _newPasswordController.clear();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.r),
        ),
        title: Text(
          'Changer le mot de passe',
          style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _oldPasswordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Ancien mot de passe',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
              ),
            ),
            SizedBox(height: 14.h),
            TextField(
              controller: _newPasswordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Nouveau mot de passe',
                helperText: 'Minimum 6 caractères',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Annuler',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: _changePassword,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.secondary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.r),
              ),
            ),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
  }

  void _showPromoDialog() {
    _promoController.clear();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.r),
        ),
        title: Text(
          'Code Promo',
          style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: _promoController,
          decoration: InputDecoration(
            hintText: 'Entrer votre code',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.r),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Annuler',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _applyPromo();
            },
            child: const Text('Appliquer'),
          ),
        ],
      ),
    );
  }
}

// ── Menu item widget ──
class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
        child: Row(
          children: [
            Container(
              width: 40.w,
              height: 40.w,
              decoration: BoxDecoration(
                color: AppColors.secondary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Icon(icon, color: AppColors.secondary, size: 20.sp),
            ),
            SizedBox(width: 14.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (subtitle != null) ...[
                    SizedBox(height: 2.h),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: AppColors.textHint, size: 22.sp),
          ],
        ),
      ),
    );
  }
}

// ── Image source option widget ──
class _ImageSourceOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ImageSourceOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60.w,
            height: 60.w,
            decoration: BoxDecoration(
              color: AppColors.secondary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16.r),
            ),
            child: Icon(icon, color: AppColors.secondary, size: 28.sp),
          ),
          SizedBox(height: 8.h),
          Text(
            label,
            style: TextStyle(
              fontSize: 13.sp,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stat item widget ──
class _StatItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _StatItem({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36.w,
            height: 36.w,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Icon(icon, color: color, size: 18.sp),
          ),
          SizedBox(height: 6.h),
          Text(
            value,
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 2.h),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.sp,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
