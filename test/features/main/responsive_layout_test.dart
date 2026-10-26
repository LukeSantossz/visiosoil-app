// The layout adapts to the screen (redesign v11 §10, SPEC 0200): a rail from
// 600 dp, content capped at 560 dp, the history as master-detail from 840 dp,
// the result's overview in two columns, and the main tabs on a small phone.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/constants/app_strings.dart';
import 'package:visiosoil_app/core/features/details/widgets/result_overview.dart';
import 'package:visiosoil_app/core/features/history/history_screen.dart';
import 'package:visiosoil_app/core/features/home/home_screen.dart';
import 'package:visiosoil_app/core/features/main/main_screen.dart';
import 'package:visiosoil_app/core/services/connectivity_service.dart';
import 'package:visiosoil_app/core/widgets/analysis_tile.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/connectivity_provider.dart';
import 'package:visiosoil_app/providers/main_tab_index_provider.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';

import '../../support/fake_soil_record_repository.dart';

const _placeholder = 'Selecione uma análise para ver os detalhes.';

final _records = [
  for (final (id, textureClass) in [(1, 'Argilosa'), (2, 'Arenosa')])
    SoilRecord(
      id: id,
      imagePath: 'missing.png',
      timestamp: '2026-06-26T12:0$id:00Z',
      textureClass: textureClass,
      confidenceScore: 0.82,
    ),
];

void _useSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

// The History tab's spinner keeps `pumpAndSettle` from settling.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<StreamController<List<SoilRecord>>> _pump(
  WidgetTester tester, {
  required Widget home,
  int tab = 0,
}) async {
  final filtered = StreamController<List<SoilRecord>>.broadcast();
  addTearDown(filtered.close);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => home),
      GoRoute(
        path: '/details',
        builder: (_, state) =>
            Scaffold(body: Text('DETAILS_STUB ${state.extra}')),
      ),
    ],
  );
  final container = ProviderContainer(
    overrides: [
      soilRecordRepositoryProvider.overrideWithValue(
        FakeSoilRecordRepository(),
      ),
      connectivityStatusProvider.overrideWith(
        (ref) => Stream.value(ConnectivityStatus.online),
      ),
      soilRecordsStreamProvider.overrideWith((ref) => Stream.value(_records)),
      filteredRecordsProvider.overrideWith(
        (ref) async* {
          yield _records;
          yield* filtered.stream;
        },
      ),
      soilRecordByIdProvider.overrideWith(
        (ref, id) async => _records.where((r) => r.id == id).firstOrNull,
      ),
    ],
  );
  addTearDown(container.dispose);
  container.read(mainTabIndexProvider.notifier).select(tab);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await _settle(tester);
  return filtered;
}

void main() {
  testWidgets('rail_from_600dp', (tester) async {
    _useSize(tester, const Size(599, 900));
    await _pump(tester, home: const MainScreen());
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);

    _useSize(tester, const Size(600, 900));
    await _settle(tester);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsOneWidget);
    for (final label in ['Início', 'Histórico', 'Dicas', 'Perfil']) {
      expect(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.text(label),
        ),
        findsOneWidget,
      );
    }

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Histórico'),
      ),
    );
    await _settle(tester);
    final history = find.byType(HistoryScreen);
    expect(
      find.ancestor(of: history, matching: find.byType(Offstage)).evaluate()
          .map((e) => (e.widget as Offstage).offstage),
      everyElement(isFalse),
    );
  });

  testWidgets('home_content_is_capped_at_560', (tester) async {
    _useSize(tester, const Size(1024, 900));
    await _pump(tester, home: const HomeScreen());

    final column = find
        .descendant(
          of: find.byType(HomeScreen),
          matching: find.byKey(const Key('homeContent')),
        )
        .first;
    final rect = tester.getRect(column);
    expect(rect.width, lessThanOrEqualTo(560));
    expect(rect.center.dx, closeTo(512, 1));
  });

  group('history', () {
    testWidgets('history_is_master_detail_from_840', (tester) async {
      _useSize(tester, const Size(1024, 900));
      await _pump(tester, home: const HistoryScreen());

      expect(find.text(_placeholder), findsOneWidget);

      await tester.tap(find.widgetWithText(AnalysisTile, 'Arenosa'));
      await _settle(tester);

      expect(find.textContaining('DETAILS_STUB'), findsNothing);
      expect(find.text(_placeholder), findsNothing);
      expect(find.text(AppStrings.resultTitle), findsOneWidget);
      // The list stays beside the record.
      expect(find.text('Argilosa'), findsWidgets);
    });

    testWidgets('history_toggle_fits_the_list_pane', (tester) async {
      _useSize(tester, const Size(1024, 900));
      await _pump(tester, home: const HistoryScreen());

      expect(tester.getRect(find.text('Coleção')).right, lessThan(360));
    });

    testWidgets('history_pushes_below_840', (tester) async {
      _useSize(tester, const Size(600, 900));
      await _pump(tester, home: const HistoryScreen());

      expect(find.text(_placeholder), findsNothing);
      await tester.tap(find.widgetWithText(AnalysisTile, 'Arenosa'));
      await _settle(tester);

      expect(find.text('DETAILS_STUB 2'), findsOneWidget);
    });

    testWidgets('history_clears_a_vanished_selection', (tester) async {
      _useSize(tester, const Size(1024, 900));
      final filtered = await _pump(tester, home: const HistoryScreen());
      await tester.tap(find.widgetWithText(AnalysisTile, 'Arenosa'));
      await _settle(tester);
      expect(find.text(_placeholder), findsNothing);

      filtered.add([_records.first]);
      await _settle(tester);

      expect(find.text(_placeholder), findsOneWidget);
    });
  });

  testWidgets('result_overview_has_two_columns_from_600', (tester) async {
    Future<(Rect, Rect)> cards(double width) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: width,
                child: ResultOverview(record: _records.first),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (
        tester.getRect(find.text(AppStrings.resultTriangleTitle)),
        tester.getRect(find.text(AppStrings.resultAboutClassTitle)),
      );
    }

    _useSize(tester, const Size(1024, 2000));
    final (triangle, about) = await cards(600);
    expect(about.left, greaterThan(triangle.right));

    final (narrowTriangle, narrowAbout) = await cards(400);
    expect(narrowAbout.top, greaterThan(narrowTriangle.bottom));
  });

  testWidgets('main_tabs_fit_a_small_phone', (tester) async {
    _useSize(tester, const Size(320, 568));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    for (var tab = 0; tab < 4; tab++) {
      await tester.pumpWidget(const SizedBox());
      await _pump(tester, home: const MainScreen(), tab: tab);
      expect(tester.takeException(), isNull, reason: 'tab $tab');
    }
  });
}
