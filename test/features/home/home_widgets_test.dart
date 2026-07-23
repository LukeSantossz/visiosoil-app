// Widget tests for the home screen's extracted sections (#120). Home had no
// test file before the decomposition; these cover each public section's render
// contract so the split is protected.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/home/widgets/hero_section.dart';
import 'package:visiosoil_app/core/features/home/widgets/last_analysis_section.dart';
import 'package:visiosoil_app/core/features/home/widgets/primary_action.dart';
import 'package:visiosoil_app/core/features/home/widgets/stats_grid.dart';
import 'package:visiosoil_app/models/home_stats.dart';
import 'package:visiosoil_app/models/soil_record.dart';

SoilRecord classifiedRecord() => SoilRecord(
      id: 1,
      imagePath: 'x.png',
      timestamp: '2026-06-26T12:00:00Z',
      textureClass: 'Argilosa',
      confidenceScore: 0.9,
    );

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('HeroSection renders the brand bar and settings entry',
      (tester) async {
    await tester.pumpWidget(
      host(const HeroSection(latestAsync: AsyncValue<SoilRecord?>.data(null))),
    );

    expect(find.text('VisioSoil'), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
  });

  testWidgets('HeroSection shows the last-analysis line for a classified record',
      (tester) async {
    await tester.pumpWidget(
      host(HeroSection(latestAsync: AsyncValue.data(classifiedRecord()))),
    );

    expect(
      find.textContaining('Última análise', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('PrimaryAction renders its label and fires onTap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(PrimaryAction(onTap: () => taps++)));

    expect(find.text('Nova análise'), findsOneWidget);

    await tester.tap(find.text('Nova análise'));
    expect(taps, 1);
  });

  testWidgets('StatsGrid shows dashes while loading and values once resolved',
      (tester) async {
    await tester.pumpWidget(
      host(const StatsGrid(statsAsync: AsyncValue<HomeStats>.loading())),
    );
    expect(find.text('Analises'), findsOneWidget);
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
      host(const LastAnalysisSection(
        latestAsync: AsyncValue<SoilRecord?>.data(null),
      )),
    );
    expect(find.text('ÚLTIMA ANÁLISE'), findsNothing);

    await tester.pumpWidget(
      host(LastAnalysisSection(latestAsync: AsyncValue.data(classifiedRecord()))),
    );
    expect(find.text('ÚLTIMA ANÁLISE'), findsOneWidget);
    expect(find.text('Ver detalhes'), findsOneWidget);
  });
}
