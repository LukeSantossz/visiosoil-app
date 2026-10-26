import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'app_density.dart';
import 'app_palette.dart';
import 'app_radius.dart';
import 'app_typography.dart';

/// Main VisioSoil theme, in a light and a dark variant built from one
/// definition over [AppPalette] (SPEC 0107).
abstract final class AppTheme {
  static ThemeData get light => _build(AppPalette.light);

  static ThemeData get dark => _build(AppPalette.dark);

  /// [light] with solid structural edges (SPEC 0130).
  static ThemeData get lightHighContrast =>
      _build(AppPalette.lightHighContrast);

  /// [dark] with solid structural edges (SPEC 0130).
  static ThemeData get darkHighContrast => _build(AppPalette.darkHighContrast);

  /// Modo Sol: a fixed high-contrast light theme for outdoor field use
  /// (redesign v11 §2, SPEC 0182), built over [AppPalette.sun] with 56 dp
  /// minimum tap targets and 2 dp black borders (§1.4) instead of shadows
  /// (§1.5).
  static ThemeData get sun {
    final base = _build(AppPalette.sun);
    const blackBorder = BorderSide(color: Colors.black, width: 2);
    const minSize = WidgetStatePropertyAll(Size(64, 56));
    const blackSide = WidgetStatePropertyAll(blackBorder);
    const flat = WidgetStatePropertyAll(0.0);
    // The same scaled sizes `textThemeFor(AppPalette.sun)` gives `labelLarge`
    // and `labelMedium` (§1.2), so the button and navigation themes below —
    // which carry an explicit `textStyle` the ambient `TextTheme` cannot
    // reach — read the sun sizes too, not the base (unscaled) ones.
    final sunLabelLarge = WidgetStatePropertyAll(
      AppTypography.resized(AppTypography.labelLarge, 17),
    );
    final sunLabelMedium = AppTypography.resized(AppTypography.labelMedium, 14);
    return base.copyWith(
      extensions: [AppPalette.sun, AppDensity.sun],
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: base.elevatedButtonTheme.style?.copyWith(
          minimumSize: minSize,
          textStyle: sunLabelLarge,
          elevation: flat,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: base.outlinedButtonTheme.style?.copyWith(
          minimumSize: minSize,
          side: blackSide,
          textStyle: sunLabelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: base.textButtonTheme.style?.copyWith(
          minimumSize: minSize,
          textStyle: sunLabelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(56, 56)),
      ),
      // SegmentedButton never forwards `minimumSize` to its segments (only
      // `padding` reaches their height calculation), so 56 dp comes from
      // padding sized against the 17 sp label this theme already scales to.
      // FilledButton and SegmentedButton carry no explicit `textStyle` theme
      // override here (unlike Elevated/Outlined/Text below): both already
      // fall back to `Theme.textTheme.labelLarge`, which `_build` already
      // scales for `AppPalette.sun`; adding an explicit one would instead
      // break `AnimatedTheme`'s interpolation against the other themes'
      // unset (null) style, which asserts on mismatched TextStyle.inherit.
      //
      // The selected segment is black with white text, not the base theme's
      // `selected` token above: `AppPalette.sun.selected` is white, the same
      // as the unselected fill, so the chosen segment needs its own explicit
      // >=7:1 pair instead (redesign v11 §1.1, §8, SPEC 0184).
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return null;
            if (states.contains(WidgetState.selected)) return Colors.black;
            return null;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return Colors.black.withValues(alpha: 0.38);
            }
            if (states.contains(WidgetState.selected)) return Colors.white;
            return Colors.black;
          }),
        ),
      ),
      cardTheme: base.cardTheme.copyWith(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.borderRadiusLg,
          side: blackBorder,
        ),
      ),
      chipTheme: const ChipThemeData(side: blackBorder),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : Colors.black,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.black
              : Colors.white,
        ),
        trackOutlineWidth: const WidgetStatePropertyAll(2),
        trackOutlineColor: WidgetStatePropertyAll(Colors.black),
      ),
      navigationBarTheme: base.navigationBarTheme.copyWith(
        height: 88,
        indicatorColor: Colors.black,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return sunLabelMedium.copyWith(
              color: AppPalette.sun.primary,
              fontWeight: FontWeight.w700,
            );
          }
          return sunLabelMedium.copyWith(
            color: AppPalette.sun.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: Colors.white);
          }
          return const IconThemeData(color: Colors.black);
        }),
      ),
      // Modo Sol never draws a shadow (§1.5): flat buttons, FAB, snackbar and
      // dialog, matching the card above.
      floatingActionButtonTheme: base.floatingActionButtonTheme.copyWith(
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        disabledElevation: 0,
      ),
      snackBarTheme: base.snackBarTheme.copyWith(elevation: 0),
      dialogTheme: base.dialogTheme.copyWith(elevation: 0),
    );
  }

  static ThemeData _build(AppPalette p) => ThemeData(
    useMaterial3: true,
    brightness: p.brightness,
    colorScheme: p.colorScheme,
    textTheme: AppTypography.textThemeFor(p),
    extensions: [p],
    // Over the screen's own background, 64 dp tall, as in the mocks
    // (SPEC 0201).
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      surfaceTintColor: Colors.transparent,
      toolbarHeight: 64,
      foregroundColor: p.onSurface,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: AppTypography.titleLarge.copyWith(color: p.onSurface),
    ),
    // Lucide's arrow on every pushed route (redesign v11 §5, SPEC 0201).
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (_) => const Icon(LucideIcons.arrowLeft),
    ),
    scaffoldBackgroundColor: p.background,
    cardTheme: CardThemeData(
      color: p.surface,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.borderRadiusLg),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      // 52 dp tall, the mocks' buttonHeight (§1.4, SPEC 0202).
      style: ElevatedButton.styleFrom(
        backgroundColor: p.primary,
        foregroundColor: p.onPrimary,
        minimumSize: const Size(64, 52),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.borderRadiusPill),
        textStyle: AppTypography.v11LabelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.primary,
        minimumSize: const Size(64, 52),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.borderRadiusPill),
        side: BorderSide(color: p.outlineVariant),
        textStyle: AppTypography.v11LabelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.primary,
        textStyle: AppTypography.v11LabelLarge,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: p.primary,
      foregroundColor: p.onPrimary,
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: p.surface,
      selectedItemColor: p.primary,
      unselectedItemColor: p.onSurfaceVariant,
      selectedLabelStyle: AppTypography.labelMedium,
      unselectedLabelStyle: AppTypography.labelMedium,
      type: BottomNavigationBarType.fixed,
    ),
    // On surfaceContainer, the labels 12 sp with the selected one in ink
    // (PNG 08, SPEC 0203); MainScreen draws the rule on top.
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      indicatorColor: p.primaryContainer,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final label = AppTypography.labelMedium.copyWith(letterSpacing: 0);
        if (states.contains(WidgetState.selected)) {
          return label.copyWith(
            color: p.onSurface,
            fontWeight: FontWeight.w600,
          );
        }
        return label.copyWith(
          color: p.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return IconThemeData(color: p.onPrimaryContainer);
        }
        return IconThemeData(color: p.onSurfaceVariant);
      }),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.inverseSurface,
      contentTextStyle: AppTypography.bodyMedium.copyWith(
        color: p.onInverseSurface,
      ),
      shape: RoundedRectangleBorder(borderRadius: AppRadius.borderRadiusSm),
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.borderRadiusXl),
      titleTextStyle: AppTypography.headlineSmall.copyWith(color: p.onSurface),
      contentTextStyle: AppTypography.bodyMedium.copyWith(
        color: p.onSurfaceVariant,
      ),
    ),
    dividerTheme: DividerThemeData(color: p.outlineVariant, thickness: 1),
    // The selected segment uses the mock's green `selected` token, not
    // M3's default secondaryContainer, which is brown in this palette and
    // reads the same as every other control's accent (redesign v11 §1.1,
    // SPEC 0184). Every other state (disabled, unselected) replicates the
    // M3 default, since setting any state on this property replaces the
    // default `WidgetStateProperty` wholesale rather than layering over it.
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return null;
          if (states.contains(WidgetState.selected)) return p.selected;
          return null;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return p.onSurface.withValues(alpha: 0.38);
          }
          if (states.contains(WidgetState.selected)) {
            return p.onPrimaryContainer;
          }
          return p.onSurface;
        }),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.primary),
  );
}
