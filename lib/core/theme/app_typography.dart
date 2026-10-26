import 'package:flutter/material.dart';
import 'app_palette.dart';

/// VisioSoil typographic scale: Inter for every role (redesign v11 §1.2,
/// SPEC 0186, SPEC 0201).
///
/// Every style is set in the bundled InterVariable, the only Inter that
/// carries the mocks' single-storey "a" (`cv11`), at the role's weight and
/// with its `opsz` axis at the font size, as a browser sets it when it
/// renders the mocks (SPEC 0201). Fonts are bundled in assets/fonts/
/// and registered in pubspec.yaml (no runtime fetching).
abstract final class AppTypography {
  static const _family = 'InterVariable';

  /// Inter font features: cv11 (single-storey a), ss01 (open digits).
  static const _interFeatures = [FontFeature('cv11'), FontFeature('ss01')];

  static TextStyle _inter(
    double size,
    double weight, {
    required double height,
    double letterSpacing = 0,
  }) => TextStyle(
    fontFamily: _family,
    fontSize: size,
    fontWeight: _nearest(weight),
    fontVariations: _axes(size, weight),
    letterSpacing: letterSpacing,
    height: height,
    fontFeatures: _interFeatures,
  );

  /// The engine sets `wght` from `fontWeight` unless the style names it, so
  /// only a weight between the named ones (650) names it, and a later
  /// `copyWith(fontWeight: ...)` still moves the axis.
  static List<FontVariation> _axes(double size, double weight) => [
    if (weight % 100 != 0) FontVariation('wght', weight),
    FontVariation('opsz', size.clamp(14, 32).toDouble()),
  ];

  static FontWeight _nearest(double weight) =>
      FontWeight.values[(((weight - 1) / 100).round() - 1).clamp(0, 8)];

  /// [style] at [weight], a weight between the named ones included.
  static TextStyle weighted(TextStyle style, double weight) => style.copyWith(
    fontWeight: _nearest(weight),
    fontVariations: _axes(style.fontSize ?? 14, weight),
  );

  /// [style] at [size], its `opsz` axis moved to the new size, as a plain
  /// `copyWith(fontSize: ...)` would not.
  static TextStyle resized(TextStyle style, double size, {double? height}) {
    final named = style.fontVariations?.where((v) => v.axis == 'wght');
    final weight = named != null && named.isNotEmpty
        ? named.first.value
        : (style.fontWeight ?? FontWeight.w400).value.toDouble();
    return style.copyWith(
      fontSize: size,
      height: height,
      fontVariations: _axes(size, weight),
    );
  }

  // --- Display ---

  /// 40/44, weight 650. For confidence % in result.
  static TextStyle get displaySmall => _inter(40, 650, height: 44 / 40);

  static TextStyle get headlineLarge =>
      _inter(32, 650, height: 40 / 32, letterSpacing: -0.8);

  /// Inter 28/36, weight 650, tracking -0.025em (SPEC 0186; §1.2).
  static TextStyle get headlineMedium =>
      _inter(28, 650, height: 36 / 28, letterSpacing: -0.7);

  /// The large title Início and Perfil open with: `headlineMedium` at 29 sp,
  /// which PNG 08 and 21 measure 3 % wider than the 28 sp headline
  /// (SPEC 0210).
  static TextStyle pageTitle(BuildContext context) => resized(
    Theme.of(context).textTheme.headlineMedium!,
    29,
    height: 36 / 29,
  ).copyWith(letterSpacing: -0.725);

  static TextStyle get headlineSmall =>
      _inter(22, 650, height: 28 / 22, letterSpacing: -0.55);

  /// The app bar title: Inter 600 20/28, tracking -0.025em, measured from
  /// the mocks' "Resultado" and "Histórico" (SPEC 0201).
  static TextStyle get titleLarge =>
      _inter(20, 600, height: 28 / 20, letterSpacing: -0.5);

  /// Inter 16/22, weight 600 (SPEC 0186; redesign v11 §1.2).
  static TextStyle get titleMedium => _inter(16, 600, height: 22 / 16);

  static TextStyle get titleSmall => _inter(14, 600, height: 20 / 14);

  // --- Body ---

  static TextStyle get bodyLarge => _inter(16, 400, height: 1.5);

  // SPEC 0186; redesign v11 §1.2.
  static TextStyle get bodyMedium => _inter(14, 400, height: 20 / 14);

  static TextStyle get bodySmall => _inter(12, 400, height: 16 / 12);

  // --- Labels ---

  static TextStyle get labelLarge =>
      _inter(14, 600, height: 1.4, letterSpacing: 0.1);

  /// Redesign v11 labelLarge: 15–16, weight 600.
  static TextStyle get v11LabelLarge =>
      _inter(15, 600, height: 1.4, letterSpacing: 0.1);

  static TextStyle get labelMedium =>
      _inter(12, 600, height: 1.33, letterSpacing: 0.4);

  static TextStyle get labelSmall =>
      _inter(11, 500, height: 1.45, letterSpacing: 0.4);

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
    TextStyle body(TextStyle style) => hc ? weighted(style, 500) : style;
    return TextTheme(
      displaySmall: displaySmall.copyWith(color: ink),
      headlineLarge: headlineLarge.copyWith(color: ink),
      headlineMedium: headlineMedium.copyWith(color: ink),
      headlineSmall: headlineSmall.copyWith(color: ink),
      titleLarge: titleLarge.copyWith(color: ink),
      titleMedium:
          (sun ? resized(titleMedium, 17, height: 24 / 17) : titleMedium)
              .copyWith(color: ink),
      titleSmall: titleSmall.copyWith(color: ink),
      bodyLarge: body(
        sun ? resized(bodyLarge, 18, height: 27 / 18) : bodyLarge,
      ).copyWith(color: ink),
      bodyMedium: body(
        sun ? resized(bodyMedium, 16, height: 24 / 16) : bodyMedium,
      ).copyWith(color: ink),
      bodySmall: body(
        sun ? resized(bodySmall, 14, height: 20 / 14) : bodySmall,
      ).copyWith(color: mute),
      labelLarge: (sun ? resized(labelLarge, 17) : labelLarge).copyWith(
        color: ink,
      ),
      labelMedium: (sun ? resized(labelMedium, 14) : labelMedium).copyWith(
        color: mute,
      ),
      labelSmall: (hc ? weighted(labelSmall, 600) : labelSmall).copyWith(
        color: mute,
      ),
    );
  }
}
