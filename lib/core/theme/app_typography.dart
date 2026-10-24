import 'package:flutter/material.dart';
import 'app_palette.dart';

/// VisioSoil typographic scale.
/// Display: Manrope (bold, tight tracking) for headlineLarge/Small and
/// titleLarge/Small.
/// headlineMedium, titleMedium, body and labels: Inter (legible in the
/// field; headlineMedium and titleMedium moved from Manrope to Inter in
/// SPEC 0188, per the redesign's §1.2).
///
/// Fonts are bundled in assets/fonts/ and registered in pubspec.yaml
/// via the Flutter fonts: section (no runtime fetching). headlineMedium uses
/// InterVariable for exact weight 650; other Inter styles use static instances.
///
/// Redesign v11 introduces Inter font features (cv11, ss01) on body/label
/// styles.
abstract final class AppTypography {
  static const _displayFamily = 'Manrope';
  static const _bodyFamily = 'Inter';

  /// Inter font features: cv11 (alternate 1), ss01 (stylistic set 1).
  static const _interFeatures = [
    FontFeature('cv11'),
    FontFeature('ss01'),
  ];

  // --- Display ---

  /// 40/44, weight 650 (approximated as w600). For confidence % in result.
  /// New in Redesign v11.
  static TextStyle get displaySmall => TextStyle(
        fontFamily: _bodyFamily,
        fontSize: 40,
        fontWeight: FontWeight.w600,
        height: 44 / 40,
        fontFeatures: _interFeatures,
      );

  static TextStyle get headlineLarge => TextStyle(
        fontFamily: _displayFamily,
        fontSize: 32,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        height: 1.2,
      );

  /// Inter 28/36, variable weight 650, tracking -0.025em
  /// (SPEC 0188; redesign v11 §1.2).
  static TextStyle get headlineMedium => TextStyle(
        fontFamily: 'InterVariable',
        fontVariations: const [FontVariation('wght', 650)],
        fontSize: 28,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.7, // -0.025em * 28
        height: 36 / 28,
        fontFeatures: _interFeatures,
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

  /// Inter 16/22, weight 600 (SPEC 0188; redesign v11 §1.2).
  static TextStyle get titleMedium => TextStyle(
        fontFamily: _bodyFamily,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 22 / 16,
        fontFeatures: _interFeatures,
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
        fontFeatures: _interFeatures,
      );

  static TextStyle get bodyMedium => TextStyle(
        fontFamily: _bodyFamily,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        height: 20 / 14, // SPEC 0188; redesign v11 §1.2
        fontFeatures: _interFeatures,
      );

  static TextStyle get bodySmall => TextStyle(
        fontFamily: _bodyFamily,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        height: 16 / 12, // SPEC 0188; redesign v11 §1.2
        fontFeatures: _interFeatures,
      );

  // --- Labels (Inter) ---

  static TextStyle get labelLarge => TextStyle(
        fontFamily: _bodyFamily,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        height: 1.4,
        fontFeatures: _interFeatures,
      );

  /// Redesign v11 labelLarge: 15–16, weight 600.
  /// Screens adopt this in later PRs via explicit use.
  static TextStyle get v11LabelLarge => TextStyle(
        fontFamily: _bodyFamily,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        height: 1.4,
        fontFeatures: _interFeatures,
      );

  static TextStyle get labelMedium => TextStyle(
        fontFamily: _bodyFamily,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        height: 1.33,
        fontFeatures: _interFeatures,
      );

  static TextStyle get labelSmall => TextStyle(
        fontFamily: _bodyFamily,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.4,
        height: 1.45,
        fontFeatures: _interFeatures,
      );

  /// Add tabular numbers feature (tnum) for %, times and statistics.
  static TextStyle tabular(TextStyle style) {
    final existing = style.fontFeatures ?? [];
    return style.copyWith(
      fontFeatures: [...existing, const FontFeature('tnum')],
    );
  }

  /// The text theme for [palette]: text on the page in `onBackground`, and
  /// the small print in `onSurfaceVariant`, so it follows the theme
  /// (SPEC 0107). In high contrast the body styles and [labelSmall] are one
  /// bundled weight heavier (SPEC 0135). In Modo Sol, [titleMedium],
  /// [bodyLarge], [bodyMedium], [bodySmall], [labelLarge] and [labelMedium]
  /// also scale up to the parenthetical sizes in the redesign's §1.2 table
  /// (SPEC 0182).
  static TextTheme textThemeFor(AppPalette palette) {
    final ink = palette.onBackground;
    final mute = palette.onSurfaceVariant;
    final hc = palette.highContrast;
    final sun = palette.isSun;
    final body = hc ? FontWeight.w500 : null;
    return TextTheme(
      displaySmall: displaySmall.copyWith(color: ink),
      headlineLarge: headlineLarge.copyWith(color: ink),
      headlineMedium: headlineMedium.copyWith(color: ink),
      headlineSmall: headlineSmall.copyWith(color: ink),
      titleLarge: titleLarge.copyWith(color: ink),
      titleMedium: (sun
              ? titleMedium.copyWith(fontSize: 17, height: 24 / 17)
              : titleMedium)
          .copyWith(color: ink),
      titleSmall: titleSmall.copyWith(color: ink),
      bodyLarge: (sun
              ? bodyLarge.copyWith(fontSize: 18, height: 27 / 18)
              : bodyLarge)
          .copyWith(color: ink, fontWeight: body),
      bodyMedium: (sun
              ? bodyMedium.copyWith(fontSize: 16, height: 24 / 16)
              : bodyMedium)
          .copyWith(color: ink, fontWeight: body),
      bodySmall: (sun
              ? bodySmall.copyWith(fontSize: 14, height: 20 / 14)
              : bodySmall)
          .copyWith(color: mute, fontWeight: body),
      labelLarge: (sun ? labelLarge.copyWith(fontSize: 17) : labelLarge)
          .copyWith(color: ink),
      labelMedium: (sun ? labelMedium.copyWith(fontSize: 14) : labelMedium)
          .copyWith(color: mute),
      labelSmall: labelSmall.copyWith(
        color: mute,
        fontWeight: hc ? FontWeight.w600 : null,
      ),
    );
  }
}
