// Widget tests for the home capture control and stats.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/home/widgets/hero_capture_card.dart';
import 'package:visiosoil_app/core/features/home/widgets/stats_grid.dart';
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
}
