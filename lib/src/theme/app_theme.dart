import 'package:flutter/material.dart';

class CueColors {
  static const background = Color(0xFFF8F9FC);
  static const primary = Color(0xFF0066FF);
  static const ink = Color(0xFF111827);
  static const muted = Color(0xFF667085);
  static const positive = Color(0xFF00B894);
  static const negative = Color(0xFFFF5A5F);
}

class AppTheme {
  const AppTheme._();

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: CueColors.primary,
      brightness: Brightness.light,
      primary: CueColors.primary,
      surface: CueColors.background,
    );

    return _base(scheme).copyWith(
      scaffoldBackgroundColor: CueColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: CueColors.background,
        foregroundColor: CueColors.ink,
        centerTitle: false,
        elevation: 0,
      ),
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: CueColors.primary,
      brightness: Brightness.dark,
      primary: CueColors.primary,
      surface: const Color(0xFF101828),
    );

    return _base(scheme).copyWith(
      scaffoldBackgroundColor: const Color(0xFF0B1220),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0B1220),
        foregroundColor: Colors.white,
        centerTitle: false,
        elevation: 0,
      ),
    );
  }

  static ThemeData _base(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Roboto',
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: CueColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
      ),
    );
  }
}
