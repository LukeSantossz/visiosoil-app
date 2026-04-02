import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Escala tipográfica do VisioSoil seguindo Material Design 3.
abstract final class AppTypography {
  static const String _fontFamily = 'Roboto';

  static const TextStyle headlineLarge = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 32,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    height: 1.25,
  );

  static const TextStyle headlineMedium = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    height: 1.29,
  );

  static const TextStyle headlineSmall = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 24,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    height: 1.33,
  );

  static const TextStyle titleLarge = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 22,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    height: 1.27,
  );

  static const TextStyle titleMedium = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.15,
    height: 1.5,
  );

  static const TextStyle titleSmall = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
    height: 1.43,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.5,
    height: 1.5,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.25,
    height: 1.43,
  );

  static const TextStyle bodySmall = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.4,
    height: 1.33,
  );

  static const TextStyle labelLarge = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
    height: 1.43,
  );

  static const TextStyle labelMedium = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
    height: 1.33,
  );

  static const TextStyle labelSmall = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
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
