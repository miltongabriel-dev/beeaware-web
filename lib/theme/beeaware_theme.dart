import 'package:flutter/material.dart';

class BeeAwareTheme {
  // ===== Brand colors =====
  static const Color primary = Color(0xFF2F3A4A);
  static const Color background = Color(0xFFF7F8FA);

  static const Color textPrimary = Color(0xFF1F2933);
  static const Color textSecondary = Color(0xFF6B7280);

  // ===== Severity =====
  static const Color severityLow = Color(0xFFF2C94C); // yellow
  static const Color severityMedium = Color(0xFFF2994A); // amber
  static const Color severityHigh = Color(0xFFEB5757); // red

  // ===== THEME DATA =====
  static ThemeData get light => ThemeData(
        fontFamily: 'Inter',
        scaffoldBackgroundColor: background,
        primaryColor: primary,
        colorScheme: ColorScheme.light(
          primary: primary,
          background: background,
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: textPrimary),
          bodySmall: TextStyle(color: textSecondary),
        ),
        iconTheme: const IconThemeData(color: primary),
      );
}
