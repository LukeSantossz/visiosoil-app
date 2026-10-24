import 'package:flutter/material.dart';
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
      AppTypography.labelLarge.copyWith(fontSize: 17),
    );
    final sunLabelMedium = AppTypography.labelMedium.copyWith(fontSize: 14);
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
      // >=7:1 pair instead (redesign v11 §1.1, §8, SPEC 0186).
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
      switchTheme: const SwitchThemeData(
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
          return sunLabelMedium.copyWith(color: AppPalette.sun.onSurfaceVariant);
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
        appBarTheme: AppBarTheme(
          backgroundColor: p.surface,
          foregroundColor: p.onSurface,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: AppTypography.titleLarge.copyWith(
            color: p.onSurface,
          ),
        ),
        scaffoldBackgroundColor: p.background,
        cardTheme: CardThemeData(
          color: p.surface,
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.borderRadiusLg,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: p.primary,
            foregroundColor: p.onPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: AppRadius.borderRadiusPill,
            ),
            textStyle: AppTypography.labelLarge,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: p.primary,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: AppRadius.borderRadiusPill,
            ),
            side: BorderSide(color: p.outlineVariant),
            textStyle: AppTypography.labelLarge,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: p.primary,
            textStyle: AppTypography.labelLarge,
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
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: p.surface,
          indicatorColor: p.primaryContainer,
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppTypography.labelMedium.copyWith(
                color: p.primary,
                fontWeight: FontWeight.w700,
              );
            }
            return AppTypography.labelMedium.copyWith(
              color: p.onSurfaceVariant,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return IconThemeData(color: p.primary);
            }
            return IconThemeData(color: p.onSurfaceVariant);
          }),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: p.inverseSurface,
          contentTextStyle: AppTypography.bodyMedium.copyWith(
            color: p.onInverseSurface,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.borderRadiusSm,
          ),
          behavior: SnackBarBehavior.floating,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: p.surface,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.borderRadiusXl,
          ),
          titleTextStyle: AppTypography.headlineSmall.copyWith(
            color: p.onSurface,
          ),
          contentTextStyle: AppTypography.bodyMedium.copyWith(
            color: p.onSurfaceVariant,
          ),
        ),
        dividerTheme: DividerThemeData(
          color: p.outlineVariant,
          thickness: 1,
        ),
        // The selected segment uses the mock's green `selected` token, not
        // M3's default secondaryContainer, which is brown in this palette and
        // reads the same as every other control's accent (redesign v11 §1.1,
        // SPEC 0186). Every other state (disabled, unselected) replicates the
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
        progressIndicatorTheme: ProgressIndicatorThemeData(
          color: p.primary,
        ),
      );
}
