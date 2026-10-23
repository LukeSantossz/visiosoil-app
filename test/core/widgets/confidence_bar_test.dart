// ConfidenceBar: the fill animates to the score over AppMotion.reveal
// (redesign v11 §4 `ConfidenceBar`: "preenche 600 ms"), renders at the
// track's height (not a collapsed zero-height fill), and tints with each
// level's exact accentColor token.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/theme/app_motion.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';
import 'package:visiosoil_app/core/widgets/confidence_bar.dart';

const double _trackWidth = 200;
const double _trackHeight = 8; // matches ConfidenceBar's own height token.

Widget host(Widget child, {ThemeData? theme}) => MaterialApp(
      theme: theme,
      home: Scaffold(body: SizedBox(width: _trackWidth, child: child)),
    );

FractionallySizedBox fractionally(WidgetTester tester) => tester.widget(
      find.descendant(
        of: find.byType(ConfidenceBar),
        matching: find.byType(FractionallySizedBox),
      ),
    );

DecoratedBox fillBox(WidgetTester tester) => tester.widget(
      find.descendant(
        of: find.byType(ConfidenceBar),
        matching: find.byType(DecoratedBox),
      ),
    );

Size fillSize(WidgetTester tester) => tester.getSize(
      find.descendant(
        of: find.byType(ConfidenceBar),
        matching: find.byType(DecoratedBox),
      ),
    );

void main() {
  testWidgets('animates the fill from 0 to the score over AppMotion.reveal',
      (tester) async {
    await tester.pumpWidget(host(const ConfidenceBar(score: 0.75)));
    expect(fractionally(tester).widthFactor, 0);

    await tester.pump(AppMotion.reveal ~/ 2);
    final midway = fractionally(tester).widthFactor!;
    expect(midway, greaterThan(0));
    expect(midway, lessThan(0.75));

    await tester.pump(AppMotion.reveal);
    expect(fractionally(tester).widthFactor, 0.75);
  });

  testWidgets('animate: false renders the final fill immediately',
      (tester) async {
    await tester.pumpWidget(
      host(const ConfidenceBar(score: 0.3, animate: false)),
    );
    expect(fractionally(tester).widthFactor, 0.3);
  });

  testWidgets('a non-finite score renders an empty fill without crashing',
      (tester) async {
    await tester.pumpWidget(
      host(const ConfidenceBar(score: double.nan, animate: false)),
    );
    expect(tester.takeException(), isNull);
    expect(fractionally(tester).widthFactor, 0);
  });

  group('the fill renders at the track height, not a collapsed zero height',
      () {
    testWidgets('animate: true, after the reveal settles', (tester) async {
      await tester.pumpWidget(host(const ConfidenceBar(score: 0.75)));
      await tester.pumpAndSettle();

      final size = fillSize(tester);
      expect(size.height, _trackHeight);
      expect(size.width, closeTo(_trackWidth * 0.75, 0.5));
    });

    testWidgets('animate: false, immediately', (tester) async {
      await tester.pumpWidget(
        host(const ConfidenceBar(score: 0.3, animate: false)),
      );

      final size = fillSize(tester);
      expect(size.height, _trackHeight);
      expect(size.width, closeTo(_trackWidth * 0.3, 0.5));
    });
  });

  group('fills with the exact accentColor token for each level', () {
    testWidgets('high: palette.primary, light theme', (tester) async {
      await tester.pumpWidget(
        host(const ConfidenceBar(score: 0.8, animate: false),
            theme: AppTheme.light),
      );
      final decoration = fillBox(tester).decoration as BoxDecoration;
      expect(decoration.color, AppPalette.light.primary);
    });

    testWidgets('high: palette.primary, dark theme', (tester) async {
      await tester.pumpWidget(
        host(const ConfidenceBar(score: 0.8, animate: false),
            theme: AppTheme.dark),
      );
      final decoration = fillBox(tester).decoration as BoxDecoration;
      expect(decoration.color, AppPalette.dark.primary);
    });

    testWidgets('moderate: palette.warning, light theme', (tester) async {
      await tester.pumpWidget(
        host(const ConfidenceBar(score: 0.6, animate: false),
            theme: AppTheme.light),
      );
      final decoration = fillBox(tester).decoration as BoxDecoration;
      expect(decoration.color, AppPalette.light.warning);
    });

    testWidgets('moderate: palette.warning, dark theme', (tester) async {
      await tester.pumpWidget(
        host(const ConfidenceBar(score: 0.6, animate: false),
            theme: AppTheme.dark),
      );
      final decoration = fillBox(tester).decoration as BoxDecoration;
      expect(decoration.color, AppPalette.dark.warning);
    });

    testWidgets('low: palette.error, light theme', (tester) async {
      await tester.pumpWidget(
        host(const ConfidenceBar(score: 0.3, animate: false),
            theme: AppTheme.light),
      );
      final decoration = fillBox(tester).decoration as BoxDecoration;
      expect(decoration.color, AppPalette.light.error);
    });

    testWidgets('low: palette.error, dark theme', (tester) async {
      await tester.pumpWidget(
        host(const ConfidenceBar(score: 0.3, animate: false),
            theme: AppTheme.dark),
      );
      final decoration = fillBox(tester).decoration as BoxDecoration;
      expect(decoration.color, AppPalette.dark.error);
    });
  });
}
