import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Escala tipográfica do VisioSoil.
/// Display/titles: Manrope (bold, tight tracking)
/// Body/labels: Inter (legível em campo)
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

  /// TextTheme para uso com ThemeData
  static TextTheme get textTheme => TextTheme(
        headlineLarge: headlineLarge.copyWith(color: AppColors.onBackground),
        headlineMedium: headlineMedium.copyWith(color: AppColors.onBackground),
        headlineSmall: headlineSmall.copyWith(color: AppColors.onBackground),
        titleLarge: titleLarge.copyWith(color: AppColors.onBackground),
        titleMedium: titleMedium.copyWith(color: AppColors.onBackground),
        titleSmall: titleSmall.copyWith(color: AppColors.onBackground),
        bodyLarge: bodyLarge.copyWith(color: AppColors.onBackground),
        bodyMedium: bodyMedium.copyWith(color: AppColors.onBackground),
        bodySmall: bodySmall.copyWith(color: AppColors.onSurfaceVariant),
        labelLarge: labelLarge.copyWith(color: AppColors.onBackground),
        labelMedium: labelMedium.copyWith(color: AppColors.onSurfaceVariant),
        labelSmall: labelSmall.copyWith(color: AppColors.onSurfaceVariant),
      );
}
