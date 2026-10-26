// AppDensity ThemeExtension tests (Redesign v11 §1.4).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/theme/app_density.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';

void main() {
  group('AppDensity', () {
    test('standard_has_48dp_tap_target', () {
      expect(AppDensity.standard.tap, 48);
    });

    test('standard_has_52dp_button_height', () {
      expect(AppDensity.standard.buttonHeight, 48);
    });

    test('standard_has_1dp_border_width', () {
      expect(AppDensity.standard.borderWidth, 1);
    });

    test('standard_has_80dp_nav_height', () {
      expect(AppDensity.standard.navHeight, 80);
    });

    test('standard_has_72dp_shutter', () {
      expect(AppDensity.standard.shutter, 72);
    });

    test('sun_has_56dp_tap_target', () {
      expect(AppDensity.sun.tap, 56);
    });

    test('sun_has_56dp_button_height', () {
      expect(AppDensity.sun.buttonHeight, 56);
    });

    test('sun_has_2dp_border_width', () {
      expect(AppDensity.sun.borderWidth, 2);
    });

    test('sun_has_88dp_nav_height', () {
      expect(AppDensity.sun.navHeight, 88);
    });

    test('sun_has_80dp_shutter', () {
      expect(AppDensity.sun.shutter, 80);
    });
  });

  group('AppDensity.of', () {
    testWidgets('resolves from theme extension', (tester) async {
      late AppDensity density;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(extensions: [AppDensity.standard, AppPalette.light]),
        home: Builder(builder: (context) {
          density = AppDensity.of(context);
          return const SizedBox();
        }),
      ));
      expect(density, same(AppDensity.standard));
    });

    testWidgets('falls back to standard when no extension', (tester) async {
      late AppDensity density;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          density = AppDensity.of(context);
          return const SizedBox();
        }),
      ));
      expect(density.tap, AppDensity.standard.tap);
    });
  });

  test('lerp_interpolates_all_values', () {
    final result = AppDensity.standard.lerp(AppDensity.sun, 0.5);
    expect(result.tap, 52);
    expect(result.buttonHeight, 52);
    expect(result.borderWidth, 1.5);
    expect(result.navHeight, 84);
    expect(result.shutter, 76);
  });

  test('copyWith_returns_new_instance', () {
    final modified = AppDensity.standard.copyWith(tap: 60);
    expect(modified.tap, 60);
    expect(modified.buttonHeight, AppDensity.standard.buttonHeight);
  });
}
