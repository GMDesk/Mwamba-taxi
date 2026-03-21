import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../theme/app_colors.dart';

enum AlertType { error, warning, success, info }

class AppAlert {
  AppAlert._();

  /// Extract a human-readable message from a DioException.
  static String extractDioMessage(DioException e, {String? fallback}) {
    final data = e.response?.data;

    if (data is Map) {
      // {"detail": "..."}
      if (data.containsKey('detail')) return data['detail'].toString();
      // {"message": "..."}
      if (data.containsKey('message')) return data['message'].toString();
      // {"field": ["error msg"]}
      final messages = <String>[];
      data.forEach((key, value) {
        if (value is List && value.isNotEmpty) {
          messages.add(value.first.toString());
        } else if (value is String) {
          messages.add(value);
        }
      });
      if (messages.isNotEmpty) return messages.first;
    }

    if (data is String && data.isNotEmpty) return data;

    // Network / timeout / no response
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'La connexion a pris trop de temps. Vérifiez votre réseau.';
      case DioExceptionType.connectionError:
        return 'Impossible de se connecter au serveur. Vérifiez votre connexion internet.';
      case DioExceptionType.badCertificate:
        return 'Erreur de certificat de sécurité.';
      default:
        break;
    }

    final code = e.response?.statusCode;
    if (code != null) {
      switch (code) {
        case 400:
          return fallback ?? 'Données invalides. Vérifiez les informations saisies.';
        case 401:
          return 'Session expirée. Veuillez vous reconnecter.';
        case 403:
          return 'Vous n\'avez pas la permission d\'effectuer cette action. Votre compte est peut-être en attente d\'approbation.';
        case 404:
          return 'Ressource introuvable.';
        case 429:
          return 'Trop de requêtes. Réessayez dans quelques instants.';
        case 500:
          return 'Erreur interne du serveur. Réessayez plus tard.';
        default:
          return 'Erreur serveur ($code)';
      }
    }

    return fallback ?? 'Une erreur inattendue est survenue.';
  }

  /// Extract a message from any exception.
  static String extractMessage(Object e, {String? fallback}) {
    if (e is DioException) return extractDioMessage(e, fallback: fallback);
    return fallback ?? 'Une erreur inattendue est survenue.';
  }

  // ---------------------------------------------------------------------------
  // MODAL DIALOGS
  // ---------------------------------------------------------------------------

  static Future<void> show(
    BuildContext context, {
    required String message,
    String? title,
    AlertType type = AlertType.error,
  }) {
    final config = _alertConfig(type);

    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: BoxConstraints(maxWidth: 340.w),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20.r),
            boxShadow: [
              BoxShadow(
                color: config.color.withOpacity(0.25),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Colored top bar
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(vertical: 20.h),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [config.color, config.color.withOpacity(0.8)],
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20.r),
                    topRight: Radius.circular(20.r),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: EdgeInsets.all(12.r),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(config.icon, color: Colors.white, size: 32.sp),
                    ),
                    SizedBox(height: 10.h),
                    Text(
                      title ?? config.defaultTitle,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              // Message
              Padding(
                padding: EdgeInsets.fromLTRB(24.w, 20.h, 24.w, 8.h),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14.sp,
                    height: 1.5,
                  ),
                ),
              ),
              // Button
              Padding(
                padding: EdgeInsets.fromLTRB(24.w, 8.h, 24.w, 20.h),
                child: SizedBox(
                  width: double.infinity,
                  height: 46.h,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: config.color,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      'Compris',
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w600,
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

  /// Convenience for showing error from a DioException.
  static Future<void> showDioError(
    BuildContext context,
    DioException e, {
    String? fallback,
    String? title,
  }) {
    return show(
      context,
      message: extractDioMessage(e, fallback: fallback),
      title: title,
      type: AlertType.error,
    );
  }

  /// Convenience for showing error from any exception.
  static Future<void> showError(
    BuildContext context,
    Object e, {
    String? fallback,
    String? title,
  }) {
    return show(
      context,
      message: extractMessage(e, fallback: fallback),
      title: title,
      type: AlertType.error,
    );
  }

  /// Show a success modal.
  static Future<void> showSuccess(
    BuildContext context, {
    required String message,
    String? title,
  }) {
    return show(
      context,
      message: message,
      title: title,
      type: AlertType.success,
    );
  }

  // ---------------------------------------------------------------------------
  // CONFIG
  // ---------------------------------------------------------------------------

  static _AlertConfig _alertConfig(AlertType type) {
    switch (type) {
      case AlertType.error:
        return _AlertConfig(
          color: AppColors.error,
          icon: Icons.error_outline_rounded,
          defaultTitle: 'Erreur',
        );
      case AlertType.warning:
        return _AlertConfig(
          color: AppColors.warning,
          icon: Icons.warning_amber_rounded,
          defaultTitle: 'Attention',
        );
      case AlertType.success:
        return _AlertConfig(
          color: AppColors.success,
          icon: Icons.check_circle_outline_rounded,
          defaultTitle: 'Succès',
        );
      case AlertType.info:
        return _AlertConfig(
          color: AppColors.info,
          icon: Icons.info_outline_rounded,
          defaultTitle: 'Information',
        );
    }
  }
}

class _AlertConfig {
  final Color color;
  final IconData icon;
  final String defaultTitle;

  const _AlertConfig({
    required this.color,
    required this.icon,
    required this.defaultTitle,
  });
}
