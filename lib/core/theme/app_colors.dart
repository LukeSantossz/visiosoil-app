import 'package:flutter/material.dart';

/// Paleta de cores do VisioSoil seguindo Material Design 3
/// com tons terrosos e verdes remetendo a solo e agricultura.
abstract final class AppColors {
  // Primary - Verde terroso
  static const Color primary = Color(0xFF4A7C59);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color primaryContainer = Color(0xFFCCE8D4);
  static const Color onPrimaryContainer = Color(0xFF0D2818);

  // Secondary - Marrom terroso
  static const Color secondary = Color(0xFF8B6F47);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color secondaryContainer = Color(0xFFF5E6D3);
  static const Color onSecondaryContainer = Color(0xFF2D1F0E);

  // Tertiary - Verde oliva
  static const Color tertiary = Color(0xFF6B7F5A);
  static const Color onTertiary = Color(0xFFFFFFFF);
  static const Color tertiaryContainer = Color(0xFFE4F0D9);
  static const Color onTertiaryContainer = Color(0xFF1A2610);

  // Error
  static const Color error = Color(0xFFBA1A1A);
  static const Color onError = Color(0xFFFFFFFF);
  static const Color errorContainer = Color(0xFFFFDAD6);
  static const Color onErrorContainer = Color(0xFF410002);

  // Warning - Amber terroso
  static const Color warning = Color(0xFFC88A3D);
  static const Color warningContainer = Color(0xFFFBEBD2);

  // Success (alias for primary in agricultural context)
  static const Color success = Color(0xFF4A7C59);

  // Background & Surface
  static const Color background = Color(0xFFF8FAF5);
  static const Color onBackground = Color(0xFF1A1C19);
  static const Color surface = Color(0xFFFCFDF8);
  static const Color onSurface = Color(0xFF1A1C19);
  static const Color surfaceDim = Color(0xFFF0F2EB);
  static const Color surfaceVariant = Color(0xFFE0E4DA);
  static const Color onSurfaceVariant = Color(0xFF43483E);

  // Outline
  static const Color outline = Color(0xFF73796D);
  static const Color outlineVariant = Color(0xFFC3C8BB);

  // Inverse
  static const Color inverseSurface = Color(0xFF2F312D);
  static const Color onInverseSurface = Color(0xFFF0F1EB);
  static const Color inversePrimary = Color(0xFFB1D1B9);

  // Misc
  static const Color shadow = Color(0xFF000000);
  static const Color scrim = Color(0xFF000000);

  // --- Soil texture class colors ---
  static const Color soilSandy = Color(0xFFD8B384);
  static const Color soilSilt = Color(0xFFB8A27C);
  static const Color soilMedium = Color(0xFF9C7B4F);
  static const Color soilClay = Color(0xFF7A4E2D);
  static const Color soilVeryClay = Color(0xFF5B3518);

  /// ColorScheme para uso com ThemeData
  static ColorScheme get colorScheme => const ColorScheme(
        brightness: Brightness.light,
        primary: primary,
        onPrimary: onPrimary,
        primaryContainer: primaryContainer,
        onPrimaryContainer: onPrimaryContainer,
        secondary: secondary,
        onSecondary: onSecondary,
        secondaryContainer: secondaryContainer,
        onSecondaryContainer: onSecondaryContainer,
        tertiary: tertiary,
        onTertiary: onTertiary,
        tertiaryContainer: tertiaryContainer,
        onTertiaryContainer: onTertiaryContainer,
        error: error,
        onError: onError,
        errorContainer: errorContainer,
        onErrorContainer: onErrorContainer,
        surface: surface,
        onSurface: onSurface,
        surfaceContainerHighest: surfaceVariant,
        onSurfaceVariant: onSurfaceVariant,
        outline: outline,
        outlineVariant: outlineVariant,
        shadow: shadow,
        scrim: scrim,
        inverseSurface: inverseSurface,
        onInverseSurface: onInverseSurface,
        inversePrimary: inversePrimary,
      );
}
