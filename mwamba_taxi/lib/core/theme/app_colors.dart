import 'dart:ui';

import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Primary Brand Colors — Ambre foncé dominant
  static const Color primary = Color(0xFFD97706);        // Ambre foncé
  static const Color primaryLight = Color(0xFFFBBF24);   // Ambre clair
  static const Color primaryDark = Color(0xFFB45309);    // Ambre profond
  static const Color secondary = Color(0xFF0B0F19);      // Noir profond
  static const Color secondaryLight = Color(0xFF1E293B); // Slate
  static const Color secondaryDark = Color(0xFF020617);  // Noir total
  static const Color accent = Color(0xFFD97706);

  // Dark palette for premium feel
  static const Color dark = Color(0xFF0B0F19);
  static const Color darkLight = Color(0xFF1E293B);
  static const Color darkMedium = Color(0xFF0F172A);

  // Background
  static const Color background = Color(0xFFF9FAFB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF3F4F6);
  static const Color inputFill = Color(0xFFF3F4F6);

  // Text
  static const Color textPrimary = Color(0xFF0B0F19);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textHint = Color(0xFF9CA3AF);
  static const Color textOnPrimary = Color(0xFFFFFFFF);
  static const Color textOnSecondary = Color(0xFFFFFFFF);

  // Status
  static const Color success = Color(0xFF10B981);
  static const Color error = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);
  static const Color info = Color(0xFF3B82F6);

  // Others
  static const Color border = Color(0xFFE5E7EB);
  static const Color divider = Color(0xFFF3F4F6);
  static const Color shadow = Color(0x14000000);
  static const Color overlay = Color(0x80000000);
  static const Color shimmer = Color(0xFFE5E7EB);

  // Rating star
  static const Color starFilled = Color(0xFFD97706);
  static const Color starEmpty = Color(0xFFE5E7EB);

  // Gradients
  static const List<Color> primaryGradient = [
    Color(0xFFD97706),
    Color(0xFFB45309),
  ];
  static const List<Color> secondaryGradient = [
    Color(0xFF0B0F19),
    Color(0xFF1E293B),
  ];
  static const List<Color> darkGradient = [
    Color(0xFF0B0F19),
    Color(0xFF1E293B),
  ];
  static const List<Color> ctaGradient = [
    Color(0xFFB45309),
    Color(0xFFD97706),
  ];
  static const List<Color> premiumGradient = [
    Color(0xFFB45309),
    Color(0xFFD97706),
    Color(0xFFFBBF24),
  ];

  // Glassmorphism helper
  static Color glass = Colors.white.withOpacity(0.85);
  static Color glassBorder = Colors.white.withOpacity(0.3);
}
