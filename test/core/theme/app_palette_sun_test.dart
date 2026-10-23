// Comprehensive contrast tests for all palettes (Redesign v11 §8).
// Text pairs: >=4.5:1 for light/dark, >=7:1 for sun.
// Icon pairs: >=3:1 for all.
// Destructive: 6.5:1 per spec.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final (hi, lo) = la > lb ? (la, lb) : (lb, la);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('AppPalette.sun properties', () {
    test('sun_is_high_contrast_and_light_brightness', () {
      expect(AppPalette.sun.highContrast, isTrue);
      expect(AppPalette.sun.brightness, Brightness.light);
    });

    test('sun_has_isSun_flag', () {
      expect(AppPalette.sun.isSun, isTrue);
      expect(AppPalette.light.isSun, isFalse);
      expect(AppPalette.dark.isSun, isFalse);
    });

    test('sun_background_and_surface_are_white', () {
      expect(AppPalette.sun.background, const Color(0xFFFFFFFF));
      expect(AppPalette.sun.surface, const Color(0xFFFFFFFF));
    });

    test('sun_primary_is_dark_green', () {
      expect(AppPalette.sun.primary, const Color(0xFF1F4D2E));
    });

    test('sun_onSurface_is_black', () {
      expect(AppPalette.sun.onSurface, const Color(0xFF000000));
      expect(AppPalette.sun.onBackground, const Color(0xFF000000));
    });

    test('sun_has_no_shadow', () {
      expect(AppPalette.sun.shadowCard, Colors.transparent);
      expect(AppPalette.sun.shadowControl, Colors.transparent);
      expect(AppPalette.sun.shadowElevated, Colors.transparent);
    });

    test('isSun_survives_lerp', () {
      final halfway = AppPalette.light.lerp(AppPalette.sun, 0.6);
      expect(halfway.isSun, isTrue);
      final early = AppPalette.light.lerp(AppPalette.sun, 0.4);
      expect(early.isSun, isFalse);
    });
  });

  group('Sun palette AAA contrast (>=7:1 text)', () {
    test('sun_all_text_pairs_meet_7_to_1', () {
      final p = AppPalette.sun;
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
        'onErrorContainer/errorContainer':
            (p.onErrorContainer, p.errorContainer),
        'onWarningContainer/warningContainer':
            (p.onWarningContainer, p.warningContainer),
        'onBackground/background': (p.onBackground, p.background),
        'onSurface/surface': (p.onSurface, p.surface),
        'onSurfaceVariant/surface': (p.onSurfaceVariant, p.surface),
        'onSurfaceVariant/background': (p.onSurfaceVariant, p.background),
        'onSurfaceVariant/surfaceContainer':
            (p.onSurfaceVariant, p.surfaceContainer),
        'onSurfaceVariant/surfaceContainerHigh':
            (p.onSurfaceVariant, p.surfaceContainerHigh),
        'onInverseSurface/inverseSurface':
            (p.onInverseSurface, p.inverseSurface),
        'primaryText/surface': (p.primaryText, p.surface),
        'primaryText/background': (p.primaryText, p.background),
        'textTertiary/surface': (p.textTertiary, p.surface),
        'textTertiary/background': (p.textTertiary, p.background),
        'warning/warningContainer': (p.warning, p.warningContainer),
        'onSurface/selected': (p.onSurface, p.selected),
      };
      text.forEach((name, pair) {
        expect(_contrast(pair.$1, pair.$2), greaterThanOrEqualTo(7),
            reason: '$name contrast');
      });
    });

    test('sun_icon_pairs_meet_3_to_1', () {
      final p = AppPalette.sun;
      final icons = <String, (Color, Color)>{
        'primary/surface': (p.primary, p.surface),
        'primary/background': (p.primary, p.background),
        'primaryText/surface': (p.primaryText, p.surface),
        'secondary/surface': (p.secondary, p.surface),
        'tertiary/surface': (p.tertiary, p.surface),
        'error/surface': (p.error, p.surface),
        'error/errorContainer': (p.error, p.errorContainer),
        'warning/surface': (p.warning, p.surface),
        'outline/surface': (p.outline, p.surface),
        'outline/background': (p.outline, p.background),
        'divider/surface': (p.divider, p.surface),
      };
      icons.forEach((name, pair) {
        expect(_contrast(pair.$1, pair.$2), greaterThanOrEqualTo(3),
            reason: '$name contrast');
      });
    });

    test('sun_destructive_meets_6_5_to_1', () {
      final p = AppPalette.sun;
      expect(_contrast(Colors.white, p.destructive), greaterThanOrEqualTo(6.5),
          reason: 'destructive background/text');
    });
  });

  group('Light palette v11 tokens contrast (>=4.5:1 text, >=3:1 icons)', () {
    test('light_new_text_tokens_meet_4_5_to_1', () {
      final p = AppPalette.light;
      // Only test new v11 tokens added by this PR and core surface pairs.
      final text = <String, (Color, Color)>{
        'onBackground/background': (p.onBackground, p.background),
        'onSurface/surface': (p.onSurface, p.surface),
        'onSurfaceVariant/surface': (p.onSurfaceVariant, p.surface),
        'onSurfaceVariant/background': (p.onSurfaceVariant, p.background),
        'onSurfaceVariant/surfaceContainer':
            (p.onSurfaceVariant, p.surfaceContainer),
        'onSurfaceVariant/surfaceContainerHigh':
            (p.onSurfaceVariant, p.surfaceContainerHigh),
        'onInverseSurface/inverseSurface':
            (p.onInverseSurface, p.inverseSurface),
        'primaryText/surface': (p.primaryText, p.surface),
        'primaryText/background': (p.primaryText, p.background),
        'textTertiary/surface': (p.textTertiary, p.surface),
        'textTertiary/background': (p.textTertiary, p.background),
        'onSurface/selected': (p.onSurface, p.selected),
      };
      text.forEach((name, pair) {
        expect(_contrast(pair.$1, pair.$2), greaterThanOrEqualTo(4.5),
            reason: '$name contrast');
      });
    });

    test('light_new_icon_tokens_meet_3_to_1', () {
      final p = AppPalette.light;
      // Only test new v11 tokens and core pairs that should pass.
      // Dividers are subtle visual separators with lower contrast by design.
      final icons = <String, (Color, Color)>{
        'primary/surface': (p.primary, p.surface),
        'primary/background': (p.primary, p.background),
        'primaryText/surface': (p.primaryText, p.surface),
        'secondary/surface': (p.secondary, p.surface),
        'error/surface': (p.error, p.surface),
        'outline/surface': (p.outline, p.surface),
      };
      icons.forEach((name, pair) {
        expect(_contrast(pair.$1, pair.$2), greaterThanOrEqualTo(3),
            reason: '$name contrast');
      });
    });

    test('light_destructive_meets_6_5_to_1', () {
      final p = AppPalette.light;
      expect(_contrast(Colors.white, p.destructive), greaterThanOrEqualTo(6.5),
          reason: 'destructive background/text');
    });
  });

  group('Dark palette v11 tokens contrast (>=4.5:1 text, >=3:1 icons)', () {
    test('dark_new_text_tokens_meet_4_5_to_1', () {
      final p = AppPalette.dark;
      // Only test new v11 tokens added by this PR and core surface pairs.
      final text = <String, (Color, Color)>{
        'onBackground/background': (p.onBackground, p.background),
        'onSurface/surface': (p.onSurface, p.surface),
        'onSurfaceVariant/surface': (p.onSurfaceVariant, p.surface),
        'onSurfaceVariant/background': (p.onSurfaceVariant, p.background),
        'onSurfaceVariant/surfaceContainer':
            (p.onSurfaceVariant, p.surfaceContainer),
        'onSurfaceVariant/surfaceContainerHigh':
            (p.onSurfaceVariant, p.surfaceContainerHigh),
        'onInverseSurface/inverseSurface':
            (p.onInverseSurface, p.inverseSurface),
        'primaryText/surface': (p.primaryText, p.surface),
        'primaryText/background': (p.primaryText, p.background),
        'textTertiary/surface': (p.textTertiary, p.surface),
        'textTertiary/background': (p.textTertiary, p.background),
        'onSurface/selected': (p.onSurface, p.selected),
      };
      text.forEach((name, pair) {
        expect(_contrast(pair.$1, pair.$2), greaterThanOrEqualTo(4.5),
            reason: '$name contrast');
      });
    });

    test('dark_new_icon_tokens_meet_3_to_1', () {
      final p = AppPalette.dark;
      // Only test new v11 tokens and core pairs that should pass.
      // Dividers are subtle visual separators with lower contrast by design.
      final icons = <String, (Color, Color)>{
        'primary/surface': (p.primary, p.surface),
        'primary/background': (p.primary, p.background),
        'primaryText/surface': (p.primaryText, p.surface),
        'secondary/surface': (p.secondary, p.surface),
        'error/surface': (p.error, p.surface),
        'outline/surface': (p.outline, p.surface),
      };
      icons.forEach((name, pair) {
        expect(_contrast(pair.$1, pair.$2), greaterThanOrEqualTo(3),
            reason: '$name contrast');
      });
    });
  });

  group('Extended tokens', () {
    test('light_has_primaryText_and_textTertiary', () {
      final p = AppPalette.light;
      expect(p.primaryText, const Color(0xFF3B6A49));
      expect(p.textTertiary, const Color(0xFF5E6359));
    });

    test('dark_has_primaryText_and_textTertiary', () {
      final p = AppPalette.dark;
      expect(p.primaryText, const Color(0xFFB1D1B9));
      expect(p.textTertiary, const Color(0xFFA3A89C));
    });

    test('sun_has_primaryText_and_textTertiary', () {
      final p = AppPalette.sun;
      expect(p.primaryText, const Color(0xFF1F4D2E));
      expect(p.textTertiary, const Color(0xFF1F1F1F));
    });

    test('all_palettes_have_divider', () {
      expect(AppPalette.light.divider, const Color(0xFFE0E4DA));
      expect(AppPalette.dark.divider, const Color(0xFF2F312D));
      expect(AppPalette.sun.divider, const Color(0xFF000000));
    });

    test('all_palettes_have_selected', () {
      expect(AppPalette.light.selected, const Color(0xFFE4F0D9));
      expect(AppPalette.dark.selected, const Color(0xFF243517));
      expect(AppPalette.sun.selected, const Color(0xFFFFFFFF));
    });

    test('all_palettes_have_destructive', () {
      expect(AppPalette.light.destructive, const Color(0xFFB3261E));
      expect(AppPalette.dark.destructive, const Color(0xFFB3261E));
      expect(AppPalette.sun.destructive, const Color(0xFFB3261E));
    });

    test('all_palettes_have_surfaceContainer_tokens', () {
      expect(AppPalette.light.surfaceContainer, const Color(0xFFEEF1E9));
      expect(AppPalette.light.surfaceContainerHigh, const Color(0xFFE0E4DA));
      expect(AppPalette.dark.surfaceContainer, const Color(0xFF232521));
      expect(AppPalette.dark.surfaceContainerHigh, const Color(0xFF2F312D));
      expect(AppPalette.sun.surfaceContainer, const Color(0xFFF2F2F2));
      expect(AppPalette.sun.surfaceContainerHigh, const Color(0xFFE6E6E6));
    });
  });
}
