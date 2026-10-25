// Widget tests for the home capture control and stats.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/home/widgets/hero_capture_card.dart';
import 'package:visiosoil_app/core/features/home/widgets/stats_grid.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';

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
  testWidgets('HeroCaptureCard renders scan and decorative gallery icons, and '
      'fires onCapture', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(HeroCaptureCard(onCapture: () => taps++)));

    expect(find.text('Analisar solo'), findsOneWidget);
    expect(find.byIcon(Icons.center_focus_strong_outlined), findsOneWidget);
    expect(find.byIcon(Icons.photo_library_outlined), findsOneWidget);
    final title = tester.widget<Text>(find.text('Analisar solo'));
    expect(title.style?.fontSize, 22);
    expect(title.style?.fontWeight, FontWeight.w400);
    expect(
      find.ancestor(
        of: find.byIcon(Icons.photo_library_outlined),
        matching: find.byType(ExcludeSemantics),
      ),
      findsWidgets,
    );
    await tester.tap(find.byIcon(Icons.photo_library_outlined));
    expect(taps, 1);
    await tester.tap(find.text('Analisar solo'));
    expect(taps, 2);
  });

  for (final entry in {'light': AppTheme.light, 'sun': AppTheme.sun}.entries) {
    final theme = entry.value;
    testWidgets('stats are readable without overflow at 360dp ${entry.key}', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: StatsGrid(
                recordsAsync: AsyncValue.data([classifiedRecord()]),
              ),
            ),
          ),
        ),
      );
      final value = tester.widget<Text>(find.text('90%'));
      final label = tester.widget<Text>(find.text('última confiança'));
      expect(value.style?.fontSize, 28);
      expect(value.style?.fontWeight, FontWeight.w700);
      expect(
        value.style?.fontVariations,
        contains(const FontVariation('wght', 700)),
      );
      expect(label.style?.fontSize, 14);
      expect(
        value.style?.fontFamily,
        theme.textTheme.headlineMedium?.fontFamily,
      );
      expect(tester.takeException(), isNull);
    });
  }

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
