// AppTheme.sun tests (redesign v11 §2, SPEC 0182).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/theme/app_density.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';
import 'package:visiosoil_app/core/theme/app_typography.dart';

void main() {
  group('AppTheme.sun', () {
    testWidgets('switches resolve black and white in both states', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.sun,
          home: Scaffold(body: Switch(value: false, onChanged: (_) {})),
        ),
      );
      final theme = Theme.of(tester.element(find.byType(Switch))).switchTheme;
      for (final selected in [false, true]) {
        final states = <WidgetState>{if (selected) WidgetState.selected};
        expect(
          theme.thumbColor?.resolve(states),
          selected ? Colors.white : Colors.black,
        );
        expect(
          theme.trackColor?.resolve(states),
          selected ? Colors.black : Colors.white,
        );
        expect(theme.trackOutlineColor?.resolve(states), Colors.black);
        expect(theme.trackOutlineWidth?.resolve(states), 2);
      }
    });
    test('carries the sun palette and density extensions', () {
      final theme = AppTheme.sun;
      expect(theme.extension<AppPalette>()?.isSun, isTrue);
      expect(theme.extension<AppDensity>(), AppDensity.sun);
    });

    test('is a light, high-contrast brightness', () {
      expect(AppTheme.sun.brightness, Brightness.light);
    });

    test('taps are padded to the platform minimum or above', () {
      expect(AppTheme.sun.materialTapTargetSize, MaterialTapTargetSize.padded);
    });

    test('buttons claim a 64x56 minimum size', () {
      const size = Size(64, 56);
      expect(
        AppTheme.sun.elevatedButtonTheme.style?.minimumSize?.resolve({}),
        size,
      );
      expect(
        AppTheme.sun.outlinedButtonTheme.style?.minimumSize?.resolve({}),
        size,
      );
      expect(
        AppTheme.sun.textButtonTheme.style?.minimumSize?.resolve({}),
        size,
      );
    });

    test('outlined buttons carry a 2dp black side', () {
      final side = AppTheme.sun.outlinedButtonTheme.style?.side?.resolve({});
      expect(side, const BorderSide(color: Colors.black, width: 2));
    });

    test('cards have no elevation and a 2dp black border', () {
      expect(AppTheme.sun.cardTheme.elevation, 0);
      final shape = AppTheme.sun.cardTheme.shape as RoundedRectangleBorder?;
      expect(shape?.side, const BorderSide(color: Colors.black, width: 2));
    });

    test('the navigation bar is 88dp tall with a black indicator', () {
      expect(AppTheme.sun.navigationBarTheme.height, 88);
      expect(AppTheme.sun.navigationBarTheme.indicatorColor, Colors.black);
    });

    test('the selected navigation icon is white, unselected is black', () {
      final iconTheme = AppTheme.sun.navigationBarTheme.iconTheme;
      expect(iconTheme?.resolve({WidgetState.selected})?.color, Colors.white);
      expect(iconTheme?.resolve({})?.color, Colors.black);
    });

    // The sun-scaled labelLarge (17 sp, §1.2) must reach Elevated/Outlined/
    // TextButton's own explicit textStyle, not just the ambient TextTheme
    // those overrides shadow.
    test('Elevated, Outlined and TextButton use the sun-scaled labelLarge', () {
      final theme = AppTheme.sun;
      final expected = AppTypography.labelLarge.copyWith(fontSize: 17).fontSize;
      expect(
        theme.elevatedButtonTheme.style?.textStyle?.resolve({})?.fontSize,
        expected,
      );
      expect(
        theme.outlinedButtonTheme.style?.textStyle?.resolve({})?.fontSize,
        expected,
      );
      expect(
        theme.textButtonTheme.style?.textStyle?.resolve({})?.fontSize,
        expected,
      );
    });

    // FilledButton and SegmentedButton carry no theme-level textStyle
    // override (that would break AnimatedTheme's interpolation against the
    // other themes' unset style), but still render at the sun-scaled 17 sp
    // through `Theme.textTheme.labelLarge`, which `_build` already scales.
    testWidgets('FilledButton and SegmentedButton render at the sun-scaled'
        ' labelLarge', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.sun,
          home: Scaffold(
            body: Column(
              children: [
                FilledButton(onPressed: () {}, child: const Text('Filled')),
                SegmentedButton<int>(
                  segments: const [ButtonSegment(value: 0, label: Text('Seg'))],
                  selected: const {0},
                  onSelectionChanged: (_) {},
                ),
              ],
            ),
          ),
        ),
      );

      double? renderedFontSize(String label) => tester
          .widget<RichText>(
            find
                .descendant(
                  of: find.text(label),
                  matching: find.byType(RichText),
                )
                .first,
          )
          .text
          .style
          ?.fontSize;

      expect(renderedFontSize('Filled'), 17);
      expect(renderedFontSize('Seg'), 17);
    });

    // The navigation bar's own labelTextStyle override also needs the
    // sun-scaled labelMedium (14 sp, §1.2).
    test('the navigation bar label uses the sun-scaled labelMedium', () {
      final labelTextStyle = AppTheme.sun.navigationBarTheme.labelTextStyle;
      expect(labelTextStyle?.resolve({WidgetState.selected})?.fontSize, 14);
      expect(labelTextStyle?.resolve({})?.fontSize, 14);
    });

    // Modo Sol never draws a shadow (§1.5): flat buttons, FAB, snackbar and
    // dialog, matching the card's own elevation 0.
    test('buttons, FAB, snackbar and dialog have no elevation', () {
      final theme = AppTheme.sun;
      expect(theme.elevatedButtonTheme.style?.elevation?.resolve({}), 0);
      expect(theme.floatingActionButtonTheme.elevation, 0);
      expect(theme.floatingActionButtonTheme.highlightElevation, 0);
      expect(theme.floatingActionButtonTheme.focusElevation, 0);
      expect(theme.floatingActionButtonTheme.hoverElevation, 0);
      expect(theme.floatingActionButtonTheme.disabledElevation, 0);
      expect(theme.snackBarTheme.elevation, 0);
      expect(theme.dialogTheme.elevation, 0);
    });

    test('light, dark and high-contrast themes are unaffected', () {
      expect(AppTheme.light.extension<AppPalette>()?.isSun, isFalse);
      expect(AppTheme.dark.extension<AppPalette>()?.isSun, isFalse);
      expect(
        AppTheme.lightHighContrast.extension<AppPalette>()?.isSun,
        isFalse,
      );
      expect(AppTheme.darkHighContrast.extension<AppPalette>()?.isSun, isFalse);
      expect(AppTheme.light.extension<AppDensity>(), isNull);
    });

    // The selected segment is black with white text/icon, not the sun
    // palette's own `selected` token (white, same as unselected), so it is
    // visible against the all-white theme at >=7:1 contrast (redesign v11
    // §1.1, §8, SPEC 0184).
    test('the selected segment is black with white text', () {
      final style = AppTheme.sun.segmentedButtonTheme.style;
      const selected = {WidgetState.selected};
      expect(style?.backgroundColor?.resolve(selected), Colors.black);
      expect(style?.foregroundColor?.resolve(selected), Colors.white);
      expect(style?.backgroundColor?.resolve({}), isNot(Colors.black));
      expect(style?.foregroundColor?.resolve({}), isNot(Colors.white));
    });
  });

  group('AppTheme.light/dark segmentedButtonTheme', () {
    // The selected segment uses the mock's green `selected` token, not M3's
    // default secondaryContainer, which is brown in this palette (redesign
    // v11 §1.1, SPEC 0184).
    test('the selected segment uses the palette selected token', () {
      for (final (palette, theme) in [
        (AppPalette.light, AppTheme.light),
        (AppPalette.dark, AppTheme.dark),
      ]) {
        final style = theme.segmentedButtonTheme.style;
        expect(
          style?.backgroundColor?.resolve({WidgetState.selected}),
          palette.selected,
          reason: palette.brightness.name,
        );
        expect(
          style?.backgroundColor?.resolve({WidgetState.selected}),
          isNot(palette.secondaryContainer),
          reason: palette.brightness.name,
        );
      }
    });
  });

  // SPEC 0210: 48 dp and flat, as the mocks draw them.
  testWidgets('buttons_are_48_dp', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: ElevatedButton(onPressed: () {}, child: const Text('Ok')),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(ElevatedButton)).height, 48);
    expect(AppTheme.light.elevatedButtonTheme.style?.elevation?.resolve({}), 0);
  });
}
