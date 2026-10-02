// The two palettes the app themes from (SPEC 0107): the light one is today's
// tokens unchanged, the dark one meets AA on every text pair, and the brand
// surfaces do not change with the theme.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/theme/app_colors.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final (hi, lo) = la > lb ? (la, lb) : (lb, la);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('dark_text_pairs_meet_aa', () {
    const p = AppPalette.dark;
    final text = <String, (Color, Color)>{
      'onPrimary/primary': (p.onPrimary, p.primary),
      'onPrimaryContainer/primaryContainer':
          (p.onPrimaryContainer, p.primaryContainer),
      'onSecondary/secondary': (p.onSecondary, p.secondary),
      'onSecondaryContainer/secondaryContainer':
          (p.onSecondaryContainer, p.secondaryContainer),
      'onTertiary/tertiary': (p.onTertiary, p.tertiary),
      'onTertiaryContainer/tertiaryContainer':
          (p.onTertiaryContainer, p.tertiaryContainer),
      'onError/error': (p.onError, p.error),
      'onErrorContainer/errorContainer': (p.onErrorContainer, p.errorContainer),
      'onWarningContainer/warningContainer':
          (p.onWarningContainer, p.warningContainer),
      'onBackground/background': (p.onBackground, p.background),
      'onSurface/surface': (p.onSurface, p.surface),
      'onSurfaceVariant/surface': (p.onSurfaceVariant, p.surface),
      'onSurfaceVariant/background': (p.onSurfaceVariant, p.background),
      'onInverseSurface/inverseSurface': (p.onInverseSurface, p.inverseSurface),
    };
    text.forEach((name, pair) {
      expect(_contrast(pair.$1, pair.$2), greaterThanOrEqualTo(4.5),
          reason: name);
    });

    final nonText = <String, (Color, Color)>{
      'primary/surface': (p.primary, p.surface),
      'error/surface': (p.error, p.surface),
      'warning/surface': (p.warning, p.surface),
      'outline/surface': (p.outline, p.surface),
    };
    nonText.forEach((name, pair) {
      expect(_contrast(pair.$1, pair.$2), greaterThanOrEqualTo(3), reason: name);
    });
  });

  test('light_palette_is_unchanged', () {
    const p = AppPalette.light;
    final roles = <String, (Color, Color)>{
      'primary': (p.primary, AppColors.primary),
      'onPrimary': (p.onPrimary, AppColors.onPrimary),
      'primaryContainer': (p.primaryContainer, AppColors.primaryContainer),
      'onPrimaryContainer':
          (p.onPrimaryContainer, AppColors.onPrimaryContainer),
      'secondary': (p.secondary, AppColors.secondary),
      'onSecondary': (p.onSecondary, AppColors.onSecondary),
      'secondaryContainer': (p.secondaryContainer, AppColors.secondaryContainer),
      'onSecondaryContainer':
          (p.onSecondaryContainer, AppColors.onSecondaryContainer),
      'tertiary': (p.tertiary, AppColors.tertiary),
      'onTertiary': (p.onTertiary, AppColors.onTertiary),
      'tertiaryContainer': (p.tertiaryContainer, AppColors.tertiaryContainer),
      'onTertiaryContainer':
          (p.onTertiaryContainer, AppColors.onTertiaryContainer),
      'error': (p.error, AppColors.error),
      'onError': (p.onError, AppColors.onError),
      'errorContainer': (p.errorContainer, AppColors.errorContainer),
      'onErrorContainer': (p.onErrorContainer, AppColors.onErrorContainer),
      'warning': (p.warning, AppColors.warning),
      'warningContainer': (p.warningContainer, AppColors.warningContainer),
      'onWarningContainer':
          (p.onWarningContainer, AppColors.onWarningContainer),
      'background': (p.background, AppColors.background),
      'onBackground': (p.onBackground, AppColors.onBackground),
      'surface': (p.surface, AppColors.surface),
      'onSurface': (p.onSurface, AppColors.onSurface),
      'surfaceVariant': (p.surfaceVariant, AppColors.surfaceVariant),
      'onSurfaceVariant': (p.onSurfaceVariant, AppColors.onSurfaceVariant),
      'outline': (p.outline, AppColors.outline),
      'outlineVariant': (p.outlineVariant, AppColors.outlineVariant),
      'inverseSurface': (p.inverseSurface, AppColors.inverseSurface),
      'onInverseSurface': (p.onInverseSurface, AppColors.onInverseSurface),
      'inversePrimary': (p.inversePrimary, AppColors.inversePrimary),
      'shadowCard': (p.shadowCard, AppColors.shadowCard),
      'shadowControl': (p.shadowControl, AppColors.shadowControl),
      'shadowElevated': (p.shadowElevated, AppColors.shadowElevated),
    };
    roles.forEach((name, pair) => expect(pair.$1, pair.$2, reason: name));
    expect(p.brightness, Brightness.light);
    expect(AppPalette.dark.brightness, Brightness.dark);
  });

  test('brand_surfaces_hold_in_both_themes', () {
    for (final p in [AppPalette.light, AppPalette.dark]) {
      expect(p.brand, AppColors.primary, reason: '${p.brightness}');
      expect(p.brandTileEnd, AppColors.tertiary, reason: '${p.brightness}');
      expect(p.onBrand, const Color(0xFFFFFFFF), reason: '${p.brightness}');
      expect(p.shadowBrand, AppColors.shadowBrand, reason: '${p.brightness}');
    }
    // In dark mode `primary` is the pale accent, so it must not be the brand.
    expect(AppPalette.dark.primary, isNot(AppPalette.dark.brand));
  });

  testWidgets('a bare MaterialApp still resolves a palette by brightness',
      (tester) async {
    late AppPalette light;
    late AppPalette dark;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.light),
      home: Builder(builder: (context) {
        light = context.palette;
        return Theme(
          data: ThemeData(brightness: Brightness.dark),
          child: Builder(builder: (context) {
            dark = context.palette;
            return const SizedBox();
          }),
        );
      }),
    ));

    expect(light, same(AppPalette.light));
    expect(dark, same(AppPalette.dark));
  });
}
