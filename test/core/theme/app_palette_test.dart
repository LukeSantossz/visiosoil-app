// The two palettes the app themes from (SPEC 0107): the light one is today's
// tokens unchanged, the dark one meets AA on every text pair, and the brand
// surfaces do not change with the theme.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/theme/app_colors.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';

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

  // A card's edge is a role: a hairline by default, solid `outline` in high
  // contrast (SPEC 0130).
  group('card border', () {
    test('card_border_meets_3_to_1_in_high_contrast', () {
      for (final p in [
        AppPalette.lightHighContrast,
        AppPalette.darkHighContrast,
      ]) {
        expect(p.highContrast, isTrue, reason: '${p.brightness}');
        expect(p.cardBorder, p.outline, reason: '${p.brightness}');
        expect(_contrast(p.cardBorder, p.surface), greaterThanOrEqualTo(3),
            reason: '${p.brightness}');
      }
    });

    // Since SPEC 0135 they also raise `outlineVariant` to `outline`.
    test('high-contrast palettes differ from their base only there', () {
      for (final (hc, base) in [
        (AppPalette.lightHighContrast, AppPalette.light),
        (AppPalette.darkHighContrast, AppPalette.dark),
      ]) {
        expect(
          hc.colorScheme.copyWith(outlineVariant: base.outlineVariant),
          base.colorScheme,
          reason: '${base.brightness}',
        );
        expect(hc.warningContainer, base.warningContainer);
        expect(hc.brand, base.brand);
      }
    });

    // A copy that changes nothing is the palette itself, as the empty
    // copyWith used to return: AppPalette has no ==, so identity is what a
    // ThemeData comparison sees.
    test('a copy that changes nothing is the same palette', () {
      for (final p in [AppPalette.light, AppPalette.lightHighContrast]) {
        expect(p.copyWith(), same(p));
        expect(p.copyWith(highContrast: p.highContrast), same(p));
      }
    });

    test('default_card_border_is_unchanged', () {
      for (final p in [AppPalette.light, AppPalette.dark]) {
        expect(p.highContrast, isFalse, reason: '${p.brightness}');
        expect(p.cardBorder, p.outlineVariant.withValues(alpha: 0.5),
            reason: '${p.brightness}');
      }
    });

    test('card_borders_use_the_role', () {
      final hairlines = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .where((file) => !file.path.endsWith('app_palette.dart'))
          .where((file) => file
              .readAsStringSync()
              .contains('outlineVariant.withValues(alpha:'))
          .map((file) => file.path)
          .toList();

      expect(hairlines, isEmpty);
    });
  });

  // High contrast's second slice: solid lines, banner edges in their own text
  // colour, 2 dp edges and one step heavier body type (SPEC 0135).
  group('high contrast, slice 2', () {
    const hcPairs = [
      ('light', AppPalette.light),
      ('dark', AppPalette.dark),
    ];

    test('hc_lines_reach_3_to_1', () {
      for (final (hc, theme) in [
        (AppPalette.lightHighContrast, AppTheme.lightHighContrast),
        (AppPalette.darkHighContrast, AppTheme.darkHighContrast),
      ]) {
        expect(hc.outlineVariant, hc.outline, reason: '${hc.brightness}');
        expect(theme.colorScheme.outlineVariant, hc.outline,
            reason: '${hc.brightness}');
        expect(_contrast(hc.outlineVariant, hc.surface),
            greaterThanOrEqualTo(3), reason: '${hc.brightness}');
        expect(_contrast(hc.outlineVariant, hc.background),
            greaterThanOrEqualTo(3), reason: '${hc.brightness}');
      }
      expect(AppPalette.light.outlineVariant, AppColors.outlineVariant);
      for (final (name, base) in hcPairs) {
        expect(base.outlineVariant, isNot(base.outline), reason: name);
      }
    });

    test('hc_banner_edges_read', () {
      for (final p in [
        AppPalette.light,
        AppPalette.dark,
        AppPalette.lightHighContrast,
        AppPalette.darkHighContrast,
      ]) {
        for (final (accent, onContainer, container) in [
          (p.warning, p.onWarningContainer, p.warningContainer),
          (p.error, p.onErrorContainer, p.errorContainer),
        ]) {
          final edge = p.bannerBorder(accent: accent, onContainer: onContainer);
          if (p.highContrast) {
            expect(edge, onContainer, reason: '${p.brightness}');
            expect(_contrast(edge, container), greaterThanOrEqualTo(3),
                reason: '${p.brightness}');
          } else {
            expect(edge, accent.withValues(alpha: 0.3),
                reason: '${p.brightness}');
          }
        }
      }
    });

    test('hc_edges_are_thicker', () {
      expect(AppPalette.light.edgeWidth, 1);
      expect(AppPalette.dark.edgeWidth, 1);
      expect(AppPalette.lightHighContrast.edgeWidth, 2);
      expect(AppPalette.darkHighContrast.edgeWidth, 2);
    });

    test('hc_body_type_is_heavier', () {
      for (final (hc, base) in [
        (AppTheme.lightHighContrast, AppTheme.light),
        (AppTheme.darkHighContrast, AppTheme.dark),
      ]) {
        for (final (name, heavy, plain, weight, baseWeight) in [
          ('bodyLarge', hc.textTheme.bodyLarge, base.textTheme.bodyLarge,
              FontWeight.w500, FontWeight.w400),
          ('bodyMedium', hc.textTheme.bodyMedium, base.textTheme.bodyMedium,
              FontWeight.w500, FontWeight.w400),
          ('bodySmall', hc.textTheme.bodySmall, base.textTheme.bodySmall,
              FontWeight.w500, FontWeight.w400),
          ('labelSmall', hc.textTheme.labelSmall, base.textTheme.labelSmall,
              FontWeight.w600, FontWeight.w500),
        ]) {
          expect(heavy?.fontWeight, weight, reason: name);
          expect(plain?.fontWeight, baseWeight, reason: name);
        }
        expect(hc.textTheme.titleLarge?.fontWeight,
            base.textTheme.titleLarge?.fontWeight);
      }
    });

    // Every edge drawn from the two roles takes its width from the palette.
    test('edges_take_the_width', () {
      final missing = <String>[];
      for (final file in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))) {
        final source = file.readAsStringSync();
        var at = source.indexOf('Border.all(');
        while (at != -1) {
          var depth = 0;
          var end = at + 'Border.all'.length;
          do {
            final char = source[end];
            if (char == '(') depth++;
            if (char == ')') depth--;
            end++;
          } while (depth > 0);
          final call = source.substring(at, end);
          if ((call.contains('cardBorder') || call.contains('bannerBorder')) &&
              !call.contains('edgeWidth')) {
            missing.add('${file.path}: $call');
          }
          at = source.indexOf('Border.all(', end);
        }
      }

      expect(missing, isEmpty);
    });

    test('hc_page_separates_from_the_card', () {
      expect(AppPalette.lightHighContrast.background,
          AppPalette.light.surfaceVariant);
      expect(AppPalette.darkHighContrast.background, AppPalette.dark.scrim);
      expect(
        _contrast(AppPalette.lightHighContrast.background,
            AppPalette.lightHighContrast.surface),
        greaterThan(_contrast(
            AppPalette.light.background, AppPalette.light.surface)),
      );
      expect(
        _contrast(AppPalette.darkHighContrast.background,
            AppPalette.darkHighContrast.surface),
        greaterThan(
            _contrast(AppPalette.dark.background, AppPalette.dark.surface)),
      );
      expect(AppPalette.light.background, AppColors.background);
      expect(AppPalette.dark.background, const Color(0xFF121411));
      expect(AppTheme.lightHighContrast.scaffoldBackgroundColor,
          AppPalette.light.surfaceVariant);
    });

    test('hc_discs_are_solid', () {
      for (final p in [
        AppPalette.lightHighContrast,
        AppPalette.darkHighContrast,
      ]) {
        for (final (accent, container, ink) in [
          (p.primary, p.primaryContainer, p.onPrimaryContainer),
          (p.secondary, p.secondaryContainer, p.onSecondaryContainer),
          (p.warning, p.warningContainer, p.onWarningContainer),
        ]) {
          expect(p.discFill(accent, alpha: 0.12), container,
              reason: '${p.brightness}');
          expect(p.discInk(accent), ink, reason: '${p.brightness}');
          expect(_contrast(ink, container), greaterThanOrEqualTo(4.5),
              reason: '${p.brightness}');
        }
      }
      expect(AppPalette.light.discFill(AppPalette.light.primary, alpha: 0.12),
          AppPalette.light.primary.withValues(alpha: 0.12));
      expect(AppPalette.light.discInk(AppPalette.light.warning),
          AppPalette.light.warning);
    });
  });
}
