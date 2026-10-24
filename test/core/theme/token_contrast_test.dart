// Guards the Designer-approved contrast fixes for `tertiary` and `warning`
// (SPEC 0180): `tertiary` must carry white text at AA, the icon tier of
// `warning` must clear the non-text (icon) threshold, and `warningText` — the
// new text-only tint — must clear AA on its own.
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
  for (final entry in {
    'light': AppPalette.light,
    'dark': AppPalette.dark,
    'sun': AppPalette.sun,
  }.entries) {
    final palette = entry.value;
    test('${entry.key}_warning_text_meets_surface_threshold', () {
      expect(
        _contrast(
          palette.warningText,
          palette.brightness == Brightness.dark
              ? palette.surface
              : Colors.white,
        ),
        greaterThanOrEqualTo(palette.isSun ? 7 : 4.5),
      );
    });
    test('${entry.key}_warning_container_text_meets_threshold', () {
      expect(
        _contrast(palette.onWarningContainer, palette.warningContainer),
        greaterThanOrEqualTo(palette.isSun ? 7 : 4.5),
      );
    });
  }

  test('tertiary_carries_white_text_at_aa', () {
    expect(
      _contrast(Colors.white, AppColors.tertiary),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('warning_icon_meets_the_non_text_threshold', () {
    expect(_contrast(Colors.white, AppColors.warning), greaterThanOrEqualTo(3));
  });

  test('warning_icon_meets_the_non_text_threshold_on_its_container', () {
    expect(
      _contrast(AppColors.warning, AppColors.warningContainer),
      greaterThanOrEqualTo(3),
    );
  });

  test('warning_text_meets_aa_on_its_own', () {
    expect(
      _contrast(Colors.white, AppColors.warningText),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('no_text_tint_uses_the_old_icon_only_warning_value', () {
    expect(AppColors.warningText, isNot(const Color(0xFFB07A35)));
  });
}
