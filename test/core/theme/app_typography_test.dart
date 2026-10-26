// AppTypography tests for Inter font with features (Redesign v11 §1.2).
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_typography.dart';

void main() {
  group('Inter font family', () {
    test('body_styles_use_inter', () {
      expect(AppTypography.bodyLarge.fontFamily, 'InterVariable');
      expect(AppTypography.bodyMedium.fontFamily, 'InterVariable');
      expect(AppTypography.bodySmall.fontFamily, 'InterVariable');
    });

    test('label_styles_use_inter', () {
      expect(AppTypography.labelLarge.fontFamily, 'InterVariable');
      expect(AppTypography.labelMedium.fontFamily, 'InterVariable');
      expect(AppTypography.labelSmall.fontFamily, 'InterVariable');
    });
  });

  group('Inter font features', () {
    test('body_styles_have_cv11_and_ss01', () {
      for (final style in [
        AppTypography.bodyLarge,
        AppTypography.bodyMedium,
        AppTypography.bodySmall,
      ]) {
        final features = style.fontFeatures ?? [];
        expect(features.any((f) => f.feature == 'cv11'), isTrue,
            reason: 'cv11 missing');
        expect(features.any((f) => f.feature == 'ss01'), isTrue,
            reason: 'ss01 missing');
      }
    });

    test('label_styles_have_cv11_and_ss01', () {
      for (final style in [
        AppTypography.labelLarge,
        AppTypography.labelMedium,
        AppTypography.labelSmall,
      ]) {
        final features = style.fontFeatures ?? [];
        expect(features.any((f) => f.feature == 'cv11'), isTrue,
            reason: 'cv11 missing');
        expect(features.any((f) => f.feature == 'ss01'), isTrue,
            reason: 'ss01 missing');
      }
    });
  });

  group('tabular numbers helper', () {
    test('tabular_adds_tnum_feature', () {
      final tabular = AppTypography.tabular(AppTypography.bodyMedium);
      final features = tabular.fontFeatures ?? [];
      expect(features.any((f) => f.feature == 'tnum'), isTrue);
    });

    test('tabular_preserves_existing_features', () {
      final tabular = AppTypography.tabular(AppTypography.bodyMedium);
      final features = tabular.fontFeatures ?? [];
      expect(features.any((f) => f.feature == 'cv11'), isTrue);
      expect(features.any((f) => f.feature == 'ss01'), isTrue);
      expect(features.any((f) => f.feature == 'tnum'), isTrue);
    });
  });

  group('displaySmall (new in v11)', () {
    test('displaySmall_is_40_with_weight_600', () {
      expect(AppTypography.displaySmall.fontSize, 40);
      expect(AppTypography.displaySmall.fontWeight, FontWeight.w600);
      expect(AppTypography.displaySmall.height, closeTo(44 / 40, 0.01));
    });
  });

  group('existing styles unchanged', () {
    test('labelLarge_unchanged', () {
      expect(AppTypography.labelLarge.fontFamily, 'InterVariable');
      expect(AppTypography.labelLarge.fontSize, 14);
      expect(AppTypography.labelLarge.fontWeight, FontWeight.w600);
    });

    test('labelMedium_unchanged', () {
      expect(AppTypography.labelMedium.fontFamily, 'InterVariable');
      expect(AppTypography.labelMedium.fontSize, 12);
      expect(AppTypography.labelMedium.fontWeight, FontWeight.w600);
    });

    test('bodyLarge_height_unchanged', () {
      expect(AppTypography.bodyLarge.height, 1.5);
    });
  });

  group('headlineMedium and titleMedium are Inter (SPEC 0186)', () {
    test('headlineMedium_has_spec_values', () {
      expect(AppTypography.headlineMedium.fontFamily, 'InterVariable');
      expect(AppTypography.headlineMedium.fontVariations, [
        const FontVariation('wght', 650),
        const FontVariation('opsz', 28),
      ]);
      expect(AppTypography.headlineMedium.fontSize, 28);
      expect(AppTypography.headlineMedium.fontWeight, FontWeight.w600);
      expect(AppTypography.headlineMedium.letterSpacing, closeTo(-0.7, 0.01));
      expect(AppTypography.headlineMedium.height, closeTo(36 / 28, 0.01));
      final features = AppTypography.headlineMedium.fontFeatures ?? [];
      expect(features.any((f) => f.feature == 'cv11'), isTrue);
      expect(features.any((f) => f.feature == 'ss01'), isTrue);
    });

    test('titleMedium_has_spec_values', () {
      expect(AppTypography.titleMedium.fontFamily, 'InterVariable');
      expect(AppTypography.titleMedium.fontSize, 16);
      expect(AppTypography.titleMedium.fontWeight, FontWeight.w600);
      expect(AppTypography.titleMedium.height, closeTo(22 / 16, 0.01));
      final features = AppTypography.titleMedium.fontFeatures ?? [];
      expect(features.any((f) => f.feature == 'cv11'), isTrue);
      expect(features.any((f) => f.feature == 'ss01'), isTrue);
    });
  });

  group('bodySmall and bodyMedium line heights (SPEC 0186)', () {
    test('bodyMedium_height_is_20_over_14', () {
      expect(AppTypography.bodyMedium.height, closeTo(20 / 14, 0.001));
    });

    test('bodySmall_height_is_16_over_12', () {
      expect(AppTypography.bodySmall.height, closeTo(16 / 12, 0.001));
    });
  });

  group('v11 additive tokens', () {
    test('v11LabelLarge_has_spec_values', () {
      expect(AppTypography.v11LabelLarge.fontFamily, 'InterVariable');
      expect(AppTypography.v11LabelLarge.fontSize, 15);
      expect(AppTypography.v11LabelLarge.fontWeight, FontWeight.w600);
      final features = AppTypography.v11LabelLarge.fontFeatures ?? [];
      expect(features.any((f) => f.feature == 'cv11'), isTrue);
    });
  });

  group('textThemeFor scales up for Modo Sol (redesign v11 §1.2, SPEC 0182)',
      () {
    test('sun_sizes_up_titleMedium_bodyLarge_bodyMedium_bodySmall', () {
      final sun = AppTypography.textThemeFor(AppPalette.sun);
      expect(sun.titleMedium?.fontSize, 17);
      expect(sun.titleMedium?.height, closeTo(24 / 17, 0.01));
      expect(sun.bodyLarge?.fontSize, 18);
      expect(sun.bodyLarge?.height, closeTo(27 / 18, 0.01));
      expect(sun.bodyMedium?.fontSize, 16);
      expect(sun.bodyMedium?.height, closeTo(24 / 16, 0.01));
      expect(sun.bodySmall?.fontSize, 14);
      expect(sun.bodySmall?.height, closeTo(20 / 14, 0.01));
      expect(sun.labelLarge?.fontSize, 17);
      expect(sun.labelMedium?.fontSize, 14);
    });

    test('light_and_dark_keep_the_base_sizes', () {
      final light = AppTypography.textThemeFor(AppPalette.light);
      expect(light.titleMedium?.fontSize, AppTypography.titleMedium.fontSize);
      expect(light.bodyLarge?.fontSize, AppTypography.bodyLarge.fontSize);
      expect(light.bodyMedium?.fontSize, AppTypography.bodyMedium.fontSize);
      expect(light.bodySmall?.fontSize, AppTypography.bodySmall.fontSize);
      expect(light.labelLarge?.fontSize, AppTypography.labelLarge.fontSize);
      expect(light.labelMedium?.fontSize, AppTypography.labelMedium.fontSize);

      final dark = AppTypography.textThemeFor(AppPalette.dark);
      expect(dark.titleMedium?.fontSize, AppTypography.titleMedium.fontSize);
    });

    // Sun's bodySmall is already black via the palette's own onSurfaceVariant
    // (SPEC 0182), so no special-casing is needed in textThemeFor.
    test('sun_bodySmall_colour_is_black', () {
      final sun = AppTypography.textThemeFor(AppPalette.sun);
      expect(sun.bodySmall?.color, const Color(0xFF000000));
    });
  });
}
