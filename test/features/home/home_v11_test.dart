import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/home/home_screen.dart';
import 'package:visiosoil_app/core/services/connectivity_service.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';
import 'package:visiosoil_app/core/theme/app_motion.dart';
import 'package:visiosoil_app/core/features/home/widgets/stats_grid.dart';
import 'package:visiosoil_app/core/widgets/analysis_tile.dart';
import 'package:visiosoil_app/core/widgets/stat_cell.dart';
import 'package:visiosoil_app/core/widgets/status_pill.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/connectivity_provider.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';

Widget home(
  ThemeData theme,
  Stream<List<SoilRecord>> stream, {
  bool offline = false,
  bool reduce = false,
}) => ProviderScope(
  overrides: [
    soilRecordsStreamProvider.overrideWith((ref) => stream),
    connectivityStatusProvider.overrideWith(
      (ref) => Stream.value(
        offline ? ConnectivityStatus.offline : ConnectivityStatus.online,
      ),
    ),
  ],
  child: MaterialApp(
    theme: theme,
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduce),
      child: const HomeScreen(),
    ),
  ),
);

void main() {
  testWidgets(
    'weekly stats exclude older records and collection deduplicates',
    (tester) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final monday = today.subtract(Duration(days: today.weekday - 1));
      final records = [
        SoilRecord(
          id: 1,
          imagePath: 'x',
          timestamp: now.toIso8601String(),
          textureClass: 'Argilosa',
          confidenceScore: .849,
        ),
        SoilRecord(
          id: 2,
          imagePath: 'x',
          timestamp: monday
              .subtract(const Duration(seconds: 1))
              .toIso8601String(),
          textureClass: 'Argilosa',
          confidenceScore: .2,
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatsGrid(recordsAsync: AsyncValue.data(records)),
          ),
        ),
      );
      final cells = tester.widgetList<StatCell>(find.byType(StatCell)).toList();
      expect(cells.map((s) => s.value), ['1', '1', '84%']);
      expect(cells.first.semanticLabel, '1 análises nesta semana');
    },
  );
  testWidgets('nonfinite latest confidence is an em dash', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatsGrid(
            recordsAsync: AsyncValue.data([
              SoilRecord(
                id: 1,
                imagePath: 'x',
                timestamp: DateTime.now().toIso8601String(),
                textureClass: 'Argilosa',
                confidenceScore: double.nan,
              ),
            ]),
          ),
        ),
      ),
    );
    expect(tester.widgetList<StatCell>(find.byType(StatCell)).last.value, '—');
    expect(tester.takeException(), isNull);
  });
  testWidgets('app reduced motion preference stops all loading animation', (
    tester,
  ) async {
    final stream = StreamController<List<SoilRecord>>();
    addTearDown(stream.close);
    AppMotion.reduceMotion = true;
    addTearDown(() => AppMotion.reduceMotion = false);
    await tester.pumpWidget(home(AppTheme.light, stream.stream));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
  testWidgets(
    'recent order uses instants and retains an unclassified capture',
    (tester) async {
      final records = [
        SoilRecord(
          id: 1,
          imagePath: 'x',
          timestamp: '2026-01-01T12:00:00+03:00',
          textureClass: 'Argilosa',
          confidenceScore: .9,
        ),
        SoilRecord(id: 2, imagePath: 'x', timestamp: '2026-01-01T10:00:00Z'),
      ];
      await tester.pumpWidget(home(AppTheme.light, Stream.value(records)));
      await tester.pumpAndSettle();
      final rows = tester
          .widgetList<AnalysisTile>(find.byType(AnalysisTile))
          .toList();
      expect(rows.map((r) => r.record.id), [2, 1]);
      final cells = tester.widgetList<StatCell>(find.byType(StatCell)).toList();
      expect(cells.last.value, '—');
    },
  );
  for (final entry in {
    'light': AppTheme.light,
    'dark': AppTheme.dark,
    'sun': AppTheme.sun,
  }.entries) {
    testWidgets('${entry.key} empty has guidance and accessible capture', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(home(entry.value, Stream.value([])));
      await tester.pumpAndSettle();
      expect(find.text('Analisar solo'), findsOneWidget);
      expect(find.text('Suas análises aparecem aqui.'), findsOneWidget);
      expect(find.text('última classe'), findsOneWidget);
      expect(find.bySemanticsLabel('Analisar solo'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Analisar solo')).rect.height,
        greaterThanOrEqualTo(entry.key == 'sun' ? 56 : 48),
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantics.dispose();
    });
    testWidgets('${entry.key} supports 200 percent text on a small phone', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            soilRecordsStreamProvider.overrideWith(
              (ref) => Stream.value([
                SoilRecord(
                  id: 1,
                  imagePath: 'x',
                  timestamp: DateTime.now().toIso8601String(),
                  textureClass: 'Muito Argilosa',
                  confidenceScore: .8,
                ),
              ]),
            ),
            connectivityStatusProvider.overrideWith(
              (ref) => Stream.value(ConnectivityStatus.offline),
            ),
          ],
          child: MaterialApp(
            theme: entry.value,
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: const HomeScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(StatsRow), findsNothing);
    });
    testWidgets('${entry.key} loading has three stat and row skeletons', (
      tester,
    ) async {
      final stream = StreamController<List<SoilRecord>>();
      addTearDown(stream.close);
      await tester.pumpWidget(home(entry.value, stream.stream));
      expect(
        tester
            .widgetList<StatCell>(find.byType(StatCell))
            .where((s) => s.isSkeleton),
        hasLength(3),
      );
      expect(find.byType(AnalysisTileSkeleton), findsNWidgets(3));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets('${entry.key} reduced loading stops shimmer', (tester) async {
      final stream = StreamController<List<SoilRecord>>();
      addTearDown(stream.close);
      await tester.pumpWidget(home(entry.value, stream.stream, reduce: true));
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
    testWidgets('${entry.key} error retains capture', (tester) async {
      await tester.pumpWidget(
        home(entry.value, Stream.error(StateError('test'))),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Não foi possível carregar suas análises.'),
        findsOneWidget,
      );
      expect(find.text('Tentar de novo'), findsOneWidget);
      expect(find.text('Analisar solo'), findsOneWidget);
    });
    for (final offline in [false, true]) {
      testWidgets(
        '${entry.key} recent records capped and offline=$offline pills',
        (tester) async {
          final semantics = tester.ensureSemantics();
          final records = List.generate(
            7,
            (i) => SoilRecord(
              id: i,
              imagePath: 'missing.png',
              timestamp: DateTime.now()
                  .subtract(Duration(minutes: i))
                  .toIso8601String(),
              textureClass: 'Argilosa',
              confidenceScore: .82,
              syncStatus: ['synced', 'pending', 'error'][i % 3],
            ),
          );
          await tester.pumpWidget(
            home(entry.value, Stream.value(records), offline: offline),
          );
          await tester.pumpAndSettle();
          expect(find.byType(AnalysisTile), findsNWidgets(5));
          final pills = tester
              .widgetList<StatusPill>(find.byType(StatusPill))
              .map((p) => p.status)
              .toList();
          expect(pills, contains(StatusPillStatus.pending));
          expect(pills.contains(StatusPillStatus.sent), !offline);
          expect(pills.contains(StatusPillStatus.error), !offline);
          expect(tester.takeException(), isNull);
          expect(
            find.bySemanticsLabel(RegExp('82% de confiança')),
            findsWidgets,
          );
          semantics.dispose();
        },
      );
    }
  }
}
