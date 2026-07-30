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
import 'package:visiosoil_app/models/home_stats.dart';
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

    expect(find.text('ANÁLISE INSTANTÂNEA'), findsOneWidget);
    expect(
      find.text('Aponte para o solo e descubra a textura em segundos'),
      findsOneWidget,
    );
    expect(find.text('Nova análise'), findsOneWidget);

    await tester.tap(find.text('Nova análise'));
    expect(taps, 1);
  });

  testWidgets('StatsGrid shows dashes while loading and values once resolved',
      (tester) async {
    await tester.pumpWidget(
      host(const StatsGrid(statsAsync: AsyncValue<HomeStats>.loading())),
    );
    expect(find.text('Análises'), findsOneWidget);
    expect(find.text('-'), findsWidgets);

    await tester.pumpWidget(
      host(const StatsGrid(
        statsAsync: AsyncValue.data(
          HomeStats(
            totalRecords: 7,
            distinctLocations: 3,
            averageConfidence: 0.8,
          ),
        ),
      )),
    );
    expect(find.text('7'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('80%'), findsOneWidget);
  });

  testWidgets('LastAnalysisSection is empty until a record exists',
      (tester) async {
    await tester.pumpWidget(
      host(LastAnalysisSection(
        latestAsync: const AsyncValue<SoilRecord?>.data(null),
        onSeeAll: () {},
      )),
    );
    expect(find.text('Última análise'), findsNothing);

    await tester.pumpWidget(
      host(LastAnalysisSection(
        latestAsync: AsyncValue.data(classifiedRecord()),
        onSeeAll: () {},
      )),
    );
    expect(find.text('Última análise'), findsOneWidget);
    expect(find.text('Ver tudo'), findsOneWidget);
    expect(find.text('Argilosa'), findsOneWidget);
    expect(find.textContaining('Fazenda Boa Vista'), findsOneWidget);
  });

  testWidgets('LastAnalysisSection "Ver tudo" fires onSeeAll', (tester) async {
    var seeAll = 0;
    await tester.pumpWidget(
      host(LastAnalysisSection(
        latestAsync: AsyncValue.data(classifiedRecord()),
        onSeeAll: () => seeAll++,
      )),
    );

    await tester.tap(find.text('Ver tudo'));
    expect(seeAll, 1);
  });
}
