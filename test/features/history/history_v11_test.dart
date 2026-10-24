import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/history/history_screen.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';
import 'package:visiosoil_app/core/services/connectivity_service.dart';
import 'package:visiosoil_app/core/widgets/analysis_tile.dart';
import 'package:visiosoil_app/core/widgets/offline_banner.dart';
import 'package:visiosoil_app/core/widgets/swipe_to_delete.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/connectivity_provider.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';
import '../../support/fake_soil_record_repository.dart';
import '../../support/haptics_recorder.dart';

final records = [
  for (var id = 1; id <= 3; id++)
    SoilRecord(
      id: id,
      imagePath: 'missing.png',
      timestamp: DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
        12,
        id,
      ).toIso8601String(),
      textureClass: 'Argilosa',
      confidenceScore: .82,
    ),
];

Widget app(
  ThemeData theme,
  AsyncValue<List<SoilRecord>> data, {
  bool offline = false,
  FakeSoilRecordRepository? repository,
}) => ProviderScope(
  overrides: [
    soilRecordRepositoryProvider.overrideWithValue(
      repository ?? FakeSoilRecordRepository(),
    ),
    soilRecordsStreamProvider.overrideWithValue(data),
    filteredRecordsProvider.overrideWithValue(data),
    connectivityStatusProvider.overrideWithValue(
      AsyncData(
        offline ? ConnectivityStatus.offline : ConnectivityStatus.online,
      ),
    ),
  ],
  child: MaterialApp(theme: theme, home: const HistoryScreen()),
);

void main() {
  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
    ('sun', AppTheme.sun),
  ]) {
    testWidgets('$name renders list, dates, semantics and collection', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(app(theme, AsyncData(records)));
      await tester.pumpAndSettle();
      expect(find.byType(AnalysisTile), findsNWidgets(3));
      expect(find.text('Hoje'), findsOneWidget);
      expect(find.byType(SwipeToDelete), findsNWidgets(3));
      expect(find.bySemanticsLabel(RegExp('82% de confiança')), findsWidgets);
      await tester.tap(find.text('Coleção'));
      await tester.pumpAndSettle();
      expect(find.text('Areia'), findsOneWidget);
      expect(find.byType(AnalysisTile), findsNothing);
      semantics.dispose();
    });
    testWidgets('$name renders empty, loading and error states', (
      tester,
    ) async {
      await tester.pumpWidget(app(theme, const AsyncData([])));
      await tester.pumpAndSettle();
      expect(find.text('Nenhuma análise ainda'), findsOneWidget);
      expect(find.text('Fazer primeira análise'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app(theme, const AsyncLoading()));
      await tester.pump();
      expect(find.text('Carregando histórico'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        app(theme, AsyncError(Exception('read'), StackTrace.current)),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Não foi possível carregar o histórico.'),
        findsOneWidget,
      );
      expect(find.text('Tentar de novo'), findsOneWidget);
    });
    for (final count in [0, 1, 2]) {
      testWidgets('$name offline copy for $count pending', (tester) async {
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          app(theme, AsyncData(records.take(count).toList()), offline: true),
        );
        await tester.pumpAndSettle();
        expect(find.text('Sem conexão'), findsOneWidget);
        expect(
          tester.getSemantics(find.byType(OfflineBanner)),
          isSemantics(isLiveRegion: true),
        );
        semantics.dispose();
        expect(
          find.text(
            '${count == 1 ? '1 análise aguarda' : '$count análises aguardam'} envio. Tudo continua salvo neste aparelho.',
          ),
          findsOneWidget,
        );
      });
    }
    testWidgets('$name narrow phone supports large text and revealed rows', (
      tester,
    ) async {
      recordHaptics(tester);
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(app(theme, AsyncData(records)));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey<int>(1)),
        200,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .first,
      );
      final visibleRow = tester
          .getRect(find.byType(SwipeToDelete).first)
          .intersect(tester.getRect(find.byType(CustomScrollView)));
      await tester.dragFrom(visibleRow.center, const Offset(-80, 0));
      await tester.pumpAndSettle();
      expect(find.text('Excluir'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    for (final fails in [false, true]) {
      testWidgets(
        '$name semantic deletion ${fails ? 'recovers from failure' : 'persists after timeout'}',
        (tester) async {
          final semantics = tester.ensureSemantics();
          recordHaptics(tester);
          final repository = _DeleteRepository(fails);
          await tester.pumpWidget(
            app(theme, AsyncData(records), repository: repository),
          );
          await tester.pumpAndSettle();
          final node = tester.getSemantics(find.byType(SwipeToDelete).first);
          final action = CustomSemanticsAction.getIdentifier(
            const CustomSemanticsAction(label: 'Excluir'),
          );
          expect(
            node.getSemanticsData().customSemanticsActionIds,
            contains(action),
          );
          tester.binding.renderViews.single.owner!.semanticsOwner!
              .performAction(node.id, SemanticsAction.customAction, action);
          await tester.pumpAndSettle();
          expect(find.text('Desfazer'), findsOneWidget);
          expect(repository.deleteByIdCalls, isEmpty);
          semantics.dispose();
          await tester.pump();
          await tester.pump(const Duration(seconds: 6));
          await tester.pumpAndSettle();
          expect(repository.deleteByIdCalls, [1]);
          expect(find.byType(AnalysisTile), findsNWidgets(fails ? 3 : 2));
          if (fails) {
            expect(
              find.text('Não foi possível excluir a análise. Tente de novo.'),
              findsOneWidget,
            );
          }
        },
      );
    }
    testWidgets('$name swipe preserves thumbnail and undo restores order', (
      tester,
    ) async {
      recordHaptics(tester);
      final repository = FakeSoilRecordRepository();
      await tester.pumpWidget(
        app(theme, AsyncData(records), repository: repository),
      );
      await tester.pumpAndSettle();
      final image = find.descendant(
        of: find.byType(AnalysisTile).at(1),
        matching: find.byType(Image),
      );
      final before = tester.getRect(image);
      await tester.drag(
        find.byKey(const ValueKey('swipe-2')),
        const Offset(-80, 0),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getRect(image).left,
        greaterThanOrEqualTo(before.left - 12),
      );
      final revealed = tester.getRect(image);
      final swipe = tester.getRect(find.byKey(const ValueKey('swipe-2')));
      expect(revealed.width, before.width);
      expect(revealed.left, greaterThanOrEqualTo(swipe.left));
      expect(revealed.right, lessThanOrEqualTo(swipe.right));
      await tester.tap(find.text('Excluir'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AnalysisTile), findsNWidgets(2));
      expect(repository.deleteByIdCalls, isEmpty);
      await tester.tap(find.text('Desfazer'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<AnalysisTile>(find.byType(AnalysisTile))
            .map((tile) => tile.record.id),
        [1, 2, 3],
      );
      expect(repository.deleteByIdCalls, isEmpty);
    });
  }
}

class _DeleteRepository extends FakeSoilRecordRepository {
  _DeleteRepository(this.fails);
  final bool fails;
  @override
  Future<void> deleteById(int id) async {
    await super.deleteById(id);
    if (fails) throw StateError('forced delete failure');
  }
}
