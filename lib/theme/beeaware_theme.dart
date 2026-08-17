import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_localizations.dart';
import '../map/map_incident.dart';

/// Spacing scale on an 8pt grid. Use these instead of hardcoded
/// EdgeInsets/SizedBox values.
class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Border radius scale shared by every card/button surface in the app.
class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double pill = 999;
}

/// Single source of truth for severity colors — used by the severity
/// picker, map pins, incident detail sheet, and cluster/summary legends
/// so a severity always renders as the same color everywhere it appears.
/// This is a hazard palette, kept intentionally separate from the brand
/// colors in [BeeAwareTheme].
class SeverityColors {
  static const Color high = Color(0xFFF44336);
  static const Color medium = Color(0xFFFF9800);
  static const Color low = Color(0xFFFFC107);

  static Color of(IncidentSeverity severity) {
    switch (severity) {
      case IncidentSeverity.high:
        return high;
      case IncidentSeverity.medium:
        return medium;
      case IncidentSeverity.low:
        return low;
    }
  }

  /// Plain localized label ("Low"/"Medium"/"High").
  static String label(BuildContext context, IncidentSeverity severity) {
    final loc = AppLocalizations.of(context)!;
    switch (severity) {
      case IncidentSeverity.high:
        return loc.severityHigh;
      case IncidentSeverity.medium:
        return loc.severityMedium;
      case IncidentSeverity.low:
        return loc.severityLow;
    }
  }

  /// Localized "Low severity"/"Medium severity"/"High severity" phrase.
  static String labelSuffixed(BuildContext context, IncidentSeverity severity) {
    return AppLocalizations.of(context)!.severitySuffixed(severity.name);
  }
}

/// Three-tone semantic colors (solid / soft background / on-soft text) for
/// status banners and messages — separate from the brand palette, so a
/// warning never has to borrow the accent color just to stand out.
class SemanticColors {
  static const Color success = Color(0xFF4CAF8C);
  static const Color successSoft = Color(0xFFEAF6F1);
  static const Color successText = Color(0xFF2F8566);

  static const Color alert = Color(0xFFF2C94C);
  static const Color alertSoft = Color(0xFFFFF8E1);
  static const Color alertText = Color(0xFF8A6D23);

  static const Color error = Color(0xFFD64545);
  static const Color errorSoft = Color(0xFFFBEAEA);
  static const Color errorText = Color(0xFFB23A3A);
}

class BeeAwareTheme {
  // ===== Brand colors =====
  // Navy is the primary brand color; amber is a deliberately sparing
  // accent (report button, token/plan badges) — not a general-purpose
  // color.
  static const Color primary = Color(0xFF1F3A5F);
  static const Color accent = Color(0xFFF59E0B);
  static const Color background = Color(0xFFFAF7F2);
  static const Color surface = Color(0xFFFBF7F2);
  static const Color border = Color(0xFFE3E8EF);

  static const Color textPrimary = Color(0xFF1F3A5F);
  static const Color textSecondary = Color(0xFF5F6C7B);
  static const Color textAux = Color(0xFF9AA4B2);

  static const Color cardShadowColor = Color(0x0F000000); // black @ 6%

  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: cardShadowColor,
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  // ===== THEME DATA =====
  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      onPrimary: Colors.white,
      surface: Colors.white,
    );

    final baseTextTheme = GoogleFonts.interTextTheme();

    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: background,
      primaryColor: primary,
      colorScheme: colorScheme,
      textTheme: baseTextTheme.copyWith(
        titleLarge: baseTextTheme.titleLarge
            ?.copyWith(color: textPrimary, fontWeight: FontWeight.w700),
        titleMedium: baseTextTheme.titleMedium
            ?.copyWith(color: textPrimary, fontWeight: FontWeight.w600),
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(color: textPrimary),
        bodySmall: baseTextTheme.bodySmall?.copyWith(color: textSecondary),
        labelLarge: baseTextTheme.labelLarge
            ?.copyWith(color: textPrimary, fontWeight: FontWeight.w600),
      ),
      iconTheme: const IconThemeData(color: textPrimary),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.inter(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: border),
        ),
        filled: true,
        fillColor: Colors.white,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: primary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
    );
  }
}
