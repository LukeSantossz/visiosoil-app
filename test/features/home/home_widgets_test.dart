// Widget tests for the home screen's sections after the design-system
// alignment (#0029): greeting + avatar, green hero capture card, and the
// last-analysis section with a "Ver tudo" link and a record row.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/home/widgets/hero_capture_card.dart';
import 'package:visiosoil_app/core/features/home/widgets/home_greeting.dart';
import 'package:visiosoil_app/core/features/home/widgets/last_analysis_section.dart';
import 'package:visiosoil_app/core/features/home/widgets/stats_grid.dart';
import 'package:visiosoil_app/core/widgets/visio_soil_logo.dart';
import 'package:visiosoil_app/models/soil_record.dart';

SoilRecord classifiedRecord() => SoilRecord(
  id: 1,
  imagePath: 'x.png',
  timestamp: '2026-06-26T12:00:00Z',
  address: 'Fazenda Boa Vista',
  textureClass: 'Argilosa',
  confidenceScore: 0.9,
);

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('HomeGreeting shows the audience label and a settings avatar, '
      'not the wordmark', (tester) async {
    await tester.pumpWidget(host(const HomeGreeting()));

    expect(find.text('Agrônomo'), findsOneWidget);
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
    // The DS greeting carries no wordmark and no gear; the mark lives on splash.
    expect(find.text('VisioSoil'), findsNothing);
    expect(find.byType(VisioSoilLogo), findsNothing);
    expect(find.byIcon(Icons.settings_outlined), findsNothing);
  });

  testWidgets('HeroCaptureCard renders the eyebrow, headline and CTA, and '
      'fires onCapture', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(HeroCaptureCard(onCapture: () => taps++)));

    expect(find.text('Analisar solo'), findsOneWidget);
    await tester.tap(find.text('Analisar solo'));
    expect(taps, 1);
  });

  testWidgets('StatsGrid switches skeletons to local record values', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const StatsGrid(recordsAsync: AsyncValue.loading())),
    );
    expect(find.text('-'), findsNothing);
    await tester.pumpWidget(
      host(StatsGrid(recordsAsync: AsyncValue.data([classifiedRecord()]))),
    );
    expect(find.text('90%'), findsOneWidget);
    expect(find.text('coleção'), findsOneWidget);
  });

  testWidgets('LastAnalysisSection is empty until a record exists', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        LastAnalysisSection(
          latestAsync: const AsyncValue<SoilRecord?>.data(null),
          onSeeAll: () {},
        ),
      ),
    );
    expect(find.text('Última análise'), findsNothing);

    await tester.pumpWidget(
      host(
        LastAnalysisSection(
          latestAsync: AsyncValue.data(classifiedRecord()),
          onSeeAll: () {},
        ),
      ),
    );
    expect(find.text('Última análise'), findsOneWidget);
    expect(find.text('Ver tudo'), findsOneWidget);
    expect(find.text('Argilosa'), findsOneWidget);
    expect(find.textContaining('Fazenda Boa Vista'), findsOneWidget);
  });

  testWidgets('LastAnalysisSection "Ver tudo" fires onSeeAll', (tester) async {
    var seeAll = 0;
    await tester.pumpWidget(
      host(
        LastAnalysisSection(
          latestAsync: AsyncValue.data(classifiedRecord()),
          onSeeAll: () => seeAll++,
        ),
      ),
    );

    await tester.tap(find.text('Ver tudo'));
    expect(seeAll, 1);
  });

  testWidgets('LastAnalysisSection tolerates a non-finite confidence score', (
    tester,
  ) async {
    final record = SoilRecord(
      id: 1,
      imagePath: 'x.png',
      timestamp: '2026-06-26T12:00:00Z',
      address: 'Fazenda',
      textureClass: 'Argilosa',
      confidenceScore: double.nan,
    );

    await tester.pumpWidget(
      host(
        LastAnalysisSection(
          latestAsync: AsyncValue.data(record),
          onSeeAll: () {},
        ),
      ),
    );

    // The row builds (no `.round()` crash) and the confidence indicator falls
    // back to the level label with no percentage.
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Baixa'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
  });

  // SPEC 0118: the last-analysis row is one labelled button with ink.
  testWidgets('record_row_is_accessible', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      host(
        LastAnalysisSection(
          latestAsync: AsyncValue.data(classifiedRecord()),
          onSeeAll: () {},
        ),
      ),
    );

    final row = find.bySemanticsLabel(RegExp('Argilosa'));
    expect(row, findsOneWidget);
    final node = tester.getSemantics(row);
    expect(node.label, contains('Fazenda Boa Vista'));
    expect(node, isSemantics(isButton: true));
    expect(
      find.ancestor(of: find.text('Argilosa'), matching: find.byType(InkWell)),
      findsOneWidget,
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    semantics.dispose();
  });

  // The avatar is a 48 dp target around a circle still drawn at 40 dp
  // (SPEC 0133).
  testWidgets('settings_avatar_target', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(host(const HomeGreeting()));

    final node = tester.getSemantics(find.bySemanticsLabel('Configurações'));
    expect(node, isSemantics(isButton: true));
    expect(node.rect.size, const Size(48, 48));

    final circle = find.descendant(
      of: find.byType(HomeGreeting),
      matching: find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).shape == BoxShape.circle,
      ),
    );
    expect(tester.getSize(circle), const Size(40, 40));
    semantics.dispose();
  });
}
