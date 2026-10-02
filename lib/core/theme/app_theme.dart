import 'package:flutter/material.dart';
import 'app_palette.dart';
import 'app_radius.dart';
import 'app_typography.dart';

/// Main VisioSoil theme, in a light and a dark variant built from one
/// definition over [AppPalette] (SPEC 0107).
abstract final class AppTheme {
  static ThemeData get light => _build(AppPalette.light);

  static ThemeData get dark => _build(AppPalette.dark);

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
        progressIndicatorTheme: ProgressIndicatorThemeData(
          color: p.primary,
        ),
      );
}
