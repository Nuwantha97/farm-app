import 'package:flutter/material.dart';

class AppColors {
  // Primary palette — earthy green tones
  static const Color primary = Color(0xFF2E7D32);
  static const Color primaryLight = Color(0xFF60AD5E);
  static const Color primaryDark = Color(0xFF005005);

  // Secondary palette — warm amber
  static const Color secondary = Color(0xFFF9A825);
  static const Color secondaryLight = Color(0xFFFFD95A);
  static const Color secondaryDark = Color(0xFFC17900);

  // Background & Surface
  static const Color background = Color(0xFFF5F7F0);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFE8F0E2);
  static const Color card = Color(0xFFFFFFFF);

  // Text
  static const Color textPrimary = Color(0xFF1B2A1B);
  static const Color textSecondary = Color(0xFF5A6B5A);
  static const Color textHint = Color(0xFF9CAF9C);

  // Status colors
  static const Color success = Color(0xFF43A047);
  static const Color warning = Color(0xFFFFA726);
  static const Color error = Color(0xFFE53935);
  static const Color info = Color(0xFF29B6F6);

  // Expense / Finance
  static const Color expense = Color(0xFFEF5350);
  static const Color income = Color(0xFF66BB6A);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2E7D32), Color(0xFF60AD5E)],
  );

  static const LinearGradient headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1B5E20), Color(0xFF388E3C)],
  );

  // Shadows
  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];
}
