// Widget tests for the home capture control and stats.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
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
    expect(find.byIcon(LucideIcons.scan), findsOneWidget);
    expect(find.byIcon(LucideIcons.image), findsOneWidget);
    final title = tester.widget<Text>(find.text('Analisar solo'));
    expect(title.style?.fontSize, 17); // PNG 08, SPEC 0203.
    expect(title.style?.fontWeight, FontWeight.w400);
    expect(
      find.ancestor(
        of: find.byIcon(LucideIcons.image),
        matching: find.byType(ExcludeSemantics),
      ),
      findsWidgets,
    );
    await tester.tap(find.byIcon(LucideIcons.image));
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
      // 24 sp weight 650 over a 12 sp label (PNG 08, SPEC 0203).
      expect(value.style?.fontSize, 24);
      expect(value.style?.height, 32 / 24);
      expect(
        value.style?.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
      expect(value.style?.fontWeight, FontWeight.w600);
      expect(
        value.style?.fontVariations,
        contains(const FontVariation('wght', 650)),
      );
      // 12 sp in Modo Sol too, as PNG 25 draws it (SPEC 0213).
      expect(label.style?.fontSize, 12);
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

  // SPEC 0216: the cards take their content's height, 104 dp in PNG 09.
  testWidgets('stats_cards_take_their_content_height', (tester) async {
    // Wide enough for the test font's square glyphs to keep one line.
    await tester.binding.setSurfaceSize(const Size(1600, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      host(const StatsGrid(recordsAsync: AsyncValue.data(<SoilRecord>[]))),
    );
    expect(tester.getSize(find.byType(StatsGrid)).height, 104);
  });
}
