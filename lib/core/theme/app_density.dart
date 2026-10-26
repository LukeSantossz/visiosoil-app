import 'package:flutter/material.dart';

/// Density tokens for tap targets and component heights (Redesign v11 §1.4).
///
/// [standard] is the default for light and dark themes: 48 dp tap targets,
/// 48 dp buttons as the mocks draw them (SPEC 0210), 1 dp borders. [sun] is for the high-contrast Sun mode:
/// 56 dp tap targets, 56 dp buttons, 2 dp borders for visibility in sunlight.
@immutable
class AppDensity extends ThemeExtension<AppDensity> {
  const AppDensity({
    required this.tap,
    required this.buttonHeight,
    required this.borderWidth,
    required this.navHeight,
    required this.shutter,
  });

  /// Minimum tap target size in dp.
  final double tap;

  /// Primary button height in dp.
  final double buttonHeight;

  /// Border width for cards and controls in dp.
  final double borderWidth;

  /// Navigation bar height in dp.
  final double navHeight;

  /// Camera shutter button size in dp.
  final double shutter;

  /// Standard density: 48 dp taps, 48 dp buttons, 1 dp borders.
  static const standard = AppDensity(
    tap: 48,
    buttonHeight: 48,
    borderWidth: 1,
    navHeight: 80,
    shutter: 72,
  );

  /// Sun mode density: 56 dp taps, 56 dp buttons, 2 dp borders.
  static const sun = AppDensity(
    tap: 56,
    buttonHeight: 56,
    borderWidth: 2,
    navHeight: 88,
    shutter: 80,
  );

  /// The density of [context]'s theme, or [standard] when none is registered.
  static AppDensity of(BuildContext context) {
    return Theme.of(context).extension<AppDensity>() ?? standard;
  }

  @override
  AppDensity copyWith({
    double? tap,
    double? buttonHeight,
    double? borderWidth,
    double? navHeight,
    double? shutter,
  }) {
    return AppDensity(
      tap: tap ?? this.tap,
      buttonHeight: buttonHeight ?? this.buttonHeight,
      borderWidth: borderWidth ?? this.borderWidth,
      navHeight: navHeight ?? this.navHeight,
      shutter: shutter ?? this.shutter,
    );
  }

  @override
  AppDensity lerp(covariant AppDensity? other, double t) {
    if (other == null) return this;
    return AppDensity(
      tap: lerpDouble(tap, other.tap, t)!,
      buttonHeight: lerpDouble(buttonHeight, other.buttonHeight, t)!,
      borderWidth: lerpDouble(borderWidth, other.borderWidth, t)!,
      navHeight: lerpDouble(navHeight, other.navHeight, t)!,
      shutter: lerpDouble(shutter, other.shutter, t)!,
    );
  }

  double? lerpDouble(double a, double b, double t) {
    return a + (b - a) * t;
  }
}

extension AppDensityContext on BuildContext {
  /// The density tokens of this context's theme.
  AppDensity get density => AppDensity.of(this);
}
