// ConfidenceBadge is the single source for rendering a confidence score
// (redesign v11 §3.14, §4): label + percentage, never color alone — not even
// in compact mode, which only renders denser (the trello acceptance
// criterion overrides §4's "só %" compact variant). The percentage floors
// rather than rounds, so it never crosses into the band above its own
// threshold check.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';
import 'package:visiosoil_app/core/widgets/confidence_badge.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';

Widget host(Widget child, {ThemeData? theme}) =>
    MaterialApp(theme: theme, home: Scaffold(body: child));

/// The pill's own [Container], carrying the level's background/border.
Container pill(WidgetTester tester) => tester.widget<Container>(
      find
          .descendant(
            of: find.byType(ConfidenceBadge),
            matching: find.byType(Container),
          )
          .first,
    );

void main() {
  final themes = {
    'light': AppTheme.light,
    'dark': AppTheme.dark,
    'sun': AppTheme.sun,
    'light high contrast': AppTheme.lightHighContrast,
    'dark high contrast': AppTheme.darkHighContrast,
  };
  for (final entry in themes.entries) {
    for (final score in [0.49, 0.50, 0.75]) {
      testWidgets(
        '${entry.key} $score encloses icon and text with safe contrast',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: entry.value,
              home: Scaffold(body: ConfidenceBadge(score: score)),
            ),
          );
          final pill = find.descendant(
            of: find.byType(ConfidenceBadge),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Container && widget.decoration is BoxDecoration,
            ),
          );
          expect(pill, findsOneWidget);
          final decoration =
              tester.widget<Container>(pill).decoration! as BoxDecoration;
          expect(decoration.borderRadius, BorderRadius.circular(6));
          final icon = find.descendant(of: pill, matching: find.byType(Icon));
          expect(icon, findsOneWidget);
          final text = find.descendant(of: pill, matching: find.byType(Text));
          expect(text, findsOneWidget);
          final palette = tester.element(pill).palette;
          if (palette.isSun) {
            expect(decoration.color, Colors.white);
            expect(
              decoration.border,
              Border.all(color: palette.onSurface, width: 2),
            );
            expect(palette.onSurface, Colors.black);
          } else {
            expect(decoration.border, isNull);
          }
          final background = decoration.color!.computeLuminance();
          for (final color in [
            tester.widget<Icon>(icon).color!,
            tester.widget<Text>(text).style!.color!,
          ]) {
            final foreground = color.computeLuminance();
            final ratio = foreground > background
                ? (foreground + 0.05) / (background + 0.05)
                : (background + 0.05) / (foreground + 0.05);
            expect(ratio, greaterThanOrEqualTo(4.5));
          }
        },
      );
    }
  }

  for (final (score, label, percent) in [
    (0.82, 'alta', 82),
    (0.749, 'média', 74),
    (0.499, 'baixa', 49),
  ]) {
    for (final compact in [false, true]) {
      testWidgets(
        'full $label label preserves percent and semantics, compact=$compact',
        (tester) async {
          final semantics = tester.ensureSemantics();
          await tester.pumpWidget(
            host(
              ConfidenceBadge(score: score, compact: compact, fullLabel: true),
            ),
          );
          expect(find.text('Confiança $label · $percent%'), findsOneWidget);
          expect(
            find.bySemanticsLabel('Confiança $label, $percent por cento'),
            findsOneWidget,
          );
          semantics.dispose();
        },
      );
    }
  }

  testWidgets('full label handles null and non-finite scores', (tester) async {
    await tester.pumpWidget(
      host(const ConfidenceBadge(score: null, fullLabel: true)),
    );
    expect(find.byType(Text), findsNothing);
    await tester.pumpWidget(
      host(const ConfidenceBadge(score: double.nan, fullLabel: true)),
    );
    expect(find.text('Confiança baixa'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('null score renders nothing', (tester) async {
    await tester.pumpWidget(host(const ConfidenceBadge(score: null)));
    expect(
      find.descendant(
        of: find.byType(ConfidenceBadge),
        matching: find.byType(Text),
      ),
      findsNothing,
    );
  });

  testWidgets('high confidence shows the label and the percentage',
      (tester) async {
    await tester.pumpWidget(host(const ConfidenceBadge(score: 0.95)));
    expect(find.text('95% · Alta'), findsOneWidget);
    expect(find.byIcon(Icons.verified), findsOneWidget);
  });

  testWidgets('moderate confidence reads Média, not Moderada', (tester) async {
    await tester.pumpWidget(host(const ConfidenceBadge(score: 0.6)));
    expect(find.text('60% · Média'), findsOneWidget);
  });

  testWidgets('low confidence shows the warning icon', (tester) async {
    await tester.pumpWidget(host(const ConfidenceBadge(score: 0.3)));
    expect(find.text('30% · Baixa'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });

  group('the percentage floors so it never crosses into the band above', () {
    testWidgets('0.499 shows 49% Baixa', (tester) async {
      await tester.pumpWidget(host(const ConfidenceBadge(score: 0.499)));
      expect(find.text('49% · Baixa'), findsOneWidget);
    });

    testWidgets('0.749 shows 74% Média', (tester) async {
      await tester.pumpWidget(host(const ConfidenceBadge(score: 0.749)));
      expect(find.text('74% · Média'), findsOneWidget);
    });

    testWidgets('0.50 shows 50% Média', (tester) async {
      await tester.pumpWidget(host(const ConfidenceBadge(score: 0.50)));
      expect(find.text('50% · Média'), findsOneWidget);
    });

    testWidgets('0.75 shows 75% Alta', (tester) async {
      await tester.pumpWidget(host(const ConfidenceBadge(score: 0.75)));
      expect(find.text('75% · Alta'), findsOneWidget);
    });
  });

  group('compact still shows the label and percent, only denser', () {
    testWidgets('renders the same label + percent text as the full badge',
        (tester) async {
      await tester.pumpWidget(
        host(const ConfidenceBadge(score: 0.82, compact: true)),
      );
      expect(find.text('82% · Alta'), findsOneWidget);
    });

    testWidgets('uses a smaller icon than the full badge', (tester) async {
      await tester.pumpWidget(host(const ConfidenceBadge(score: 0.82)));
      final fullSize = tester.widget<Icon>(find.byIcon(Icons.verified)).size!;

      await tester.pumpWidget(
        host(const ConfidenceBadge(score: 0.82, compact: true)),
      );
      final compactSize =
          tester.widget<Icon>(find.byIcon(Icons.verified)).size!;

      expect(compactSize, lessThan(fullSize));
    });
  });

  testWidgets('a non-finite score falls back to the level label with no %',
      (tester) async {
    await tester.pumpWidget(host(const ConfidenceBadge(score: double.nan)));
    expect(find.textContaining('Baixa'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('exposes the §8 semantics convention: "Confiança alta, 82 por '
      'cento"', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(host(const ConfidenceBadge(score: 0.82)));

    expect(
      find.bySemanticsLabel('Confiança alta, 82 por cento'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  group('semantics also floor the percentage', () {
    testWidgets('0.499 reads "Confiança baixa, 49 por cento"',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(host(const ConfidenceBadge(score: 0.499)));
      expect(
        find.bySemanticsLabel('Confiança baixa, 49 por cento'),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('0.749 reads "Confiança média, 74 por cento"',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(host(const ConfidenceBadge(score: 0.749)));
      expect(
        find.bySemanticsLabel('Confiança média, 74 por cento'),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('0.50 reads "Confiança média, 50 por cento"', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(host(const ConfidenceBadge(score: 0.50)));
      expect(
        find.bySemanticsLabel('Confiança média, 50 por cento'),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('0.75 reads "Confiança alta, 75 por cento"', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(host(const ConfidenceBadge(score: 0.75)));
      expect(
        find.bySemanticsLabel('Confiança alta, 75 por cento'),
        findsOneWidget,
      );
      semantics.dispose();
    });
  });

  // In Sol every container (primary/warning/error) is white, so the pill
  // needs its own 2 dp black border to read against the white page behind it
  // (redesign v11 §1.1, SPEC 0184).
  group('in Sol, the pill carries a 2dp black border', () {
    for (final score in [0.95, 0.6, 0.3]) {
      for (final compact in [false, true]) {
        testWidgets('score $score, compact $compact', (tester) async {
          await tester.pumpWidget(
            host(
              ConfidenceBadge(score: score, compact: compact),
              theme: AppTheme.sun,
            ),
          );

          final decoration = pill(tester).decoration as BoxDecoration;
          expect(decoration.border, Border.all(color: Colors.black, width: 2));
        });
      }
    }
  });

  testWidgets('outside Sol, the pill carries no border', (tester) async {
    await tester.pumpWidget(
      host(const ConfidenceBadge(score: 0.95), theme: AppTheme.light),
    );

    final decoration = pill(tester).decoration as BoxDecoration;
    expect(decoration.border, isNull);
  });
}
