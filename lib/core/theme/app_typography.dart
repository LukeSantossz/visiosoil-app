import 'package:flutter/material.dart';
import 'app_palette.dart';

/// VisioSoil typographic scale.
/// Display/titles: Manrope (bold, tight tracking)
/// Body/labels: Inter (legible in the field)
///
/// Fonts are bundled in assets/fonts/ and registered in pubspec.yaml
/// via the Flutter fonts: section (no runtime fetching).
abstract final class AppTypography {
  static const _displayFamily = 'Manrope';
  static const _bodyFamily = 'Inter';

  // --- Display (Manrope) ---

  static TextStyle get headlineLarge => TextStyle(
        fontFamily: _displayFamily,
        fontSize: 32,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        height: 1.2,
      );

  static TextStyle get headlineMedium => TextStyle(
        fontFamily: _displayFamily,
        fontSize: 28,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
        height: 1.2,
      );

  static TextStyle get headlineSmall => TextStyle(
        fontFamily: _displayFamily,
        fontSize: 22,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
        height: 1.2,
      );

  static TextStyle get titleLarge => TextStyle(
        fontFamily: _displayFamily,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        height: 1.3,
      );

  static TextStyle get titleMedium => TextStyle(
        fontFamily: _displayFamily,
        fontSize: 16,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        height: 1.4,
      );

  static TextStyle get titleSmall => TextStyle(
        fontFamily: _displayFamily,
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        height: 1.4,
      );

  // --- Body (Inter) ---

  static TextStyle get bodyLarge => TextStyle(
        fontFamily: _bodyFamily,
        fontSize: 16,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        height: 1.5,
      );

  static TextStyle get bodyMedium => TextStyle(
        fontFamily: _bodyFamily,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        height: 1.45,
      );

  static TextStyle get bodySmall => TextStyle(
        fontFamily: _bodyFamily,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        height: 1.4,
      );

  // --- Labels (Inter) ---

  static TextStyle get labelLarge => TextStyle(
        fontFamily: _bodyFamily,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        height: 1.4,
      );

  static TextStyle get labelMedium => TextStyle(
        fontFamily: _bodyFamily,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        height: 1.33,
      );

  static TextStyle get labelSmall => TextStyle(
        fontFamily: _bodyFamily,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.4,
        height: 1.45,
      );

  /// The text theme for [palette]: text on the page in `onBackground`, and
  /// the small print in `onSurfaceVariant`, so it follows the theme
  /// (SPEC 0107).
  static TextTheme textThemeFor(AppPalette palette) {
    final ink = palette.onBackground;
    final mute = palette.onSurfaceVariant;
    return TextTheme(
      headlineLarge: headlineLarge.copyWith(color: ink),
      headlineMedium: headlineMedium.copyWith(color: ink),
      headlineSmall: headlineSmall.copyWith(color: ink),
      titleLarge: titleLarge.copyWith(color: ink),
      titleMedium: titleMedium.copyWith(color: ink),
      titleSmall: titleSmall.copyWith(color: ink),
      bodyLarge: bodyLarge.copyWith(color: ink),
      bodyMedium: bodyMedium.copyWith(color: ink),
      bodySmall: bodySmall.copyWith(color: mute),
      labelLarge: labelLarge.copyWith(color: ink),
      labelMedium: labelMedium.copyWith(color: mute),
      labelSmall: labelSmall.copyWith(color: mute),
    );
  }
}
