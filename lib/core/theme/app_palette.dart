import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Every colour role a widget reads, in one instance per theme (SPEC 0107).
///
/// Widgets read `context.palette.<role>`, never [AppColors], so a screen follows
/// the theme it is drawn under. [light] holds [AppColors]' values unchanged.
/// [dark] takes each role's Material 3 dark tone from the light token's own hue
/// and chroma, fixed here as constants so a library update cannot move them.
///
/// The brand roles ([brand], [onBrand], [brandTileEnd], [shadowBrand]) are the
/// mark rather than a colour role, and hold the same values in both: in dark
/// mode [primary] is a pale accent, which must not become a large fill.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.brightness,
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.secondary,
    required this.onSecondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.tertiary,
    required this.onTertiary,
    required this.tertiaryContainer,
    required this.onTertiaryContainer,
    required this.error,
    required this.onError,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.warning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.background,
    required this.onBackground,
    required this.surface,
    required this.onSurface,
    required this.surfaceVariant,
    required this.onSurfaceVariant,
    required this.outline,
    required this.outlineVariant,
    required this.inverseSurface,
    required this.onInverseSurface,
    required this.inversePrimary,
    required this.shadow,
    required this.scrim,
    required this.shadowCard,
    required this.shadowControl,
    required this.shadowElevated,
    this.brand = AppColors.primary,
    this.onBrand = AppColors.onPrimary,
    this.brandTileEnd = AppColors.tertiary,
    this.shadowBrand = AppColors.shadowBrand,
  });

  final Brightness brightness;
  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color secondary;
  final Color onSecondary;
  final Color secondaryContainer;
  final Color onSecondaryContainer;
  final Color tertiary;
  final Color onTertiary;
  final Color tertiaryContainer;
  final Color onTertiaryContainer;
  final Color error;
  final Color onError;
  final Color errorContainer;
  final Color onErrorContainer;
  final Color warning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color background;
  final Color onBackground;
  final Color surface;
  final Color onSurface;
  final Color surfaceVariant;
  final Color onSurfaceVariant;
  final Color outline;
  final Color outlineVariant;
  final Color inverseSurface;
  final Color onInverseSurface;
  final Color inversePrimary;
  final Color shadow;
  final Color scrim;
  final Color shadowCard;
  final Color shadowControl;
  final Color shadowElevated;
  final Color brand;
  final Color onBrand;
  final Color brandTileEnd;
  final Color shadowBrand;

  static const light = AppPalette(
    brightness: Brightness.light,
    primary: AppColors.primary,
    onPrimary: AppColors.onPrimary,
    primaryContainer: AppColors.primaryContainer,
    onPrimaryContainer: AppColors.onPrimaryContainer,
    secondary: AppColors.secondary,
    onSecondary: AppColors.onSecondary,
    secondaryContainer: AppColors.secondaryContainer,
    onSecondaryContainer: AppColors.onSecondaryContainer,
    tertiary: AppColors.tertiary,
    onTertiary: AppColors.onTertiary,
    tertiaryContainer: AppColors.tertiaryContainer,
    onTertiaryContainer: AppColors.onTertiaryContainer,
    error: AppColors.error,
    onError: AppColors.onError,
    errorContainer: AppColors.errorContainer,
    onErrorContainer: AppColors.onErrorContainer,
    warning: AppColors.warning,
    warningContainer: AppColors.warningContainer,
    onWarningContainer: AppColors.onWarningContainer,
    background: AppColors.background,
    onBackground: AppColors.onBackground,
    surface: AppColors.surface,
    onSurface: AppColors.onSurface,
    surfaceVariant: AppColors.surfaceVariant,
    onSurfaceVariant: AppColors.onSurfaceVariant,
    outline: AppColors.outline,
    outlineVariant: AppColors.outlineVariant,
    inverseSurface: AppColors.inverseSurface,
    onInverseSurface: AppColors.onInverseSurface,
    inversePrimary: AppColors.inversePrimary,
    shadow: AppColors.shadow,
    scrim: AppColors.scrim,
    shadowCard: AppColors.shadowCard,
    shadowControl: AppColors.shadowControl,
    shadowElevated: AppColors.shadowElevated,
  );

  /// Tones are Material 3's dark mapping over the light tokens' hues: accents
  /// at 80 with their on-colour at 20, containers at 30 with theirs at 90, the
  /// page at neutral 6, surfaces at 12, text at 90 (SPEC 0107).
  static const dark = AppPalette(
    brightness: Brightness.dark,
    primary: Color(0xFFB1D1B9), // the light palette's inversePrimary, tone 81
    onPrimary: Color(0xFF1B3625),
    primaryContainer: Color(0xFF324D3B),
    onPrimaryContainer: Color(0xFFCBEAD2),
    secondary: Color(0xFFE4C192),
    onSecondary: Color(0xFF412C0A),
    secondaryContainer: Color(0xFF5A431E),
    onSecondaryContainer: Color(0xFFFFDDB1),
    tertiary: Color(0xFFB8CDA4),
    onTertiary: Color(0xFF243517),
    tertiaryContainer: Color(0xFF3A4C2C),
    onTertiaryContainer: Color(0xFFD4EABE),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
    warning: Color(0xFFFEB968),
    warningContainer: Color(0xFF604012),
    onWarningContainer: Color(0xFFFFDDB6),
    background: Color(0xFF121411),
    onBackground: Color(0xFFE2E3DD),
    surface: Color(0xFF1E201D),
    onSurface: Color(0xFFE2E3DD),
    surfaceVariant: Color(0xFF43483E),
    onSurfaceVariant: Color(0xFFC3C8BB),
    outline: Color(0xFF8D9287),
    outlineVariant: Color(0xFF43483E),
    inverseSurface: Color(0xFFE2E3DD),
    onInverseSurface: Color(0xFF2F312D),
    inversePrimary: AppColors.primary,
    shadow: AppColors.shadow,
    scrim: AppColors.scrim,
    // Black at the light shadows' alphas: a shadow tinted with the dark
    // theme's pale onSurface would glow instead of falling.
    shadowCard: Color(0x0A000000),
    shadowControl: Color(0x0F000000),
    shadowElevated: Color(0x33000000),
  );

  /// The palette of [context]'s theme, or the one matching its brightness when
  /// the theme carries none (a bare `MaterialApp` in a widget test).
  static AppPalette of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppPalette>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  ColorScheme get colorScheme => ColorScheme(
        brightness: brightness,
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

  /// The palette is fixed per theme, so there is nothing to override.
  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      brightness: t < 0.5 ? brightness : other.brightness,
      primary: mix(primary, other.primary),
      onPrimary: mix(onPrimary, other.onPrimary),
      primaryContainer: mix(primaryContainer, other.primaryContainer),
      onPrimaryContainer: mix(onPrimaryContainer, other.onPrimaryContainer),
      secondary: mix(secondary, other.secondary),
      onSecondary: mix(onSecondary, other.onSecondary),
      secondaryContainer: mix(secondaryContainer, other.secondaryContainer),
      onSecondaryContainer:
          mix(onSecondaryContainer, other.onSecondaryContainer),
      tertiary: mix(tertiary, other.tertiary),
      onTertiary: mix(onTertiary, other.onTertiary),
      tertiaryContainer: mix(tertiaryContainer, other.tertiaryContainer),
      onTertiaryContainer: mix(onTertiaryContainer, other.onTertiaryContainer),
      error: mix(error, other.error),
      onError: mix(onError, other.onError),
      errorContainer: mix(errorContainer, other.errorContainer),
      onErrorContainer: mix(onErrorContainer, other.onErrorContainer),
      warning: mix(warning, other.warning),
      warningContainer: mix(warningContainer, other.warningContainer),
      onWarningContainer: mix(onWarningContainer, other.onWarningContainer),
      background: mix(background, other.background),
      onBackground: mix(onBackground, other.onBackground),
      surface: mix(surface, other.surface),
      onSurface: mix(onSurface, other.onSurface),
      surfaceVariant: mix(surfaceVariant, other.surfaceVariant),
      onSurfaceVariant: mix(onSurfaceVariant, other.onSurfaceVariant),
      outline: mix(outline, other.outline),
      outlineVariant: mix(outlineVariant, other.outlineVariant),
      inverseSurface: mix(inverseSurface, other.inverseSurface),
      onInverseSurface: mix(onInverseSurface, other.onInverseSurface),
      inversePrimary: mix(inversePrimary, other.inversePrimary),
      shadow: mix(shadow, other.shadow),
      scrim: mix(scrim, other.scrim),
      shadowCard: mix(shadowCard, other.shadowCard),
      shadowControl: mix(shadowControl, other.shadowControl),
      shadowElevated: mix(shadowElevated, other.shadowElevated),
      brand: mix(brand, other.brand),
      onBrand: mix(onBrand, other.onBrand),
      brandTileEnd: mix(brandTileEnd, other.brandTileEnd),
      shadowBrand: mix(shadowBrand, other.shadowBrand),
    );
  }
}

extension AppPaletteContext on BuildContext {
  /// The colour roles of this context's theme (SPEC 0107).
  AppPalette get palette => AppPalette.of(this);
}
