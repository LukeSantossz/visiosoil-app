import 'dart:async';
import 'package:visiosoil_app/providers/connectivity_provider.dart';
import 'package:visiosoil_app/core/services/connectivity_service.dart';
import 'package:visiosoil_app/core/widgets/analysis_tile.dart';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/features/history/history_screen.dart';
import 'package:visiosoil_app/core/widgets/collapse_on_correction.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';

import '../../support/fake_soil_record_repository.dart';
import '../../support/guidelines.dart';
import '../../support/haptics_recorder.dart';
import '../../support/large_text.dart';

/// A repository whose streams serve a fixed list, filtered by class the way
/// the database filters it.
final class _ListSoilRecordRepository extends FakeSoilRecordRepository {
  _ListSoilRecordRepository(this.records);

  final List<SoilRecord> records;

  @override
  Stream<List<SoilRecord>> watchAll() => Stream.value(records);

  @override
  Stream<List<SoilRecord>> watchFiltered({
    String? textureClass,
    String? searchTerm,
  }) => Stream.value([
    for (final record in records)
      if (textureClass == null || record.textureClass == textureClass) record,
  ]);
}

/// Guards the history texture-filter error state (#117): a provider failure must
/// surface visible feedback with a retry that actually re-reads the underlying
/// records stream, not silently collapse the chip bar.
final class _DisposeSpy extends ProviderObserver {
  final disposed = <Object?>[];

  @override
  void didDisposeProvider(ProviderObserverContext context) {
    disposed.add(context.provider);
  }
}

/// Opens the class chips, which the app bar's "Filtros" toggles (SPEC 0203).
Future<void> _openFilters(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Filtros'));
  await tester.pump();
}

/// Starts a selection with [tile] through its "Selecionar" semantics action,
/// the entry that is not a gesture (SPEC 0122, SPEC 0203).
Future<void> _selectBySemantics(WidgetTester tester, Finder tile) async {
  final handle = tester.ensureSemantics();
  final node = tester.getSemantics(tile);
  tester.binding.renderViews.single.owner!.semanticsOwner!.performAction(
    node.id,
    SemanticsAction.customAction,
    CustomSemanticsAction.getIdentifier(
      const CustomSemanticsAction(label: 'Selecionar'),
    ),
  );
  await tester.pumpAndSettle();
  handle.dispose();
}

void main() {
  // A synchronous AsyncError on the root stream reliably drives the chips into
  // the error branch (async stream errors do not settle under flutter_test).
  final rootError = soilRecordsStreamProvider.overrideWithValue(
    AsyncValue<List<SoilRecord>>.error(Exception('boom'), StackTrace.current),
  );
  final emptyGrid = filteredRecordsProvider.overrideWith(
    (ref) => Stream.value(<SoilRecord>[]),
  );

  // The app bar's "Buscar" and "Filtros" each open their own part of the
  // filter bar and close it again (SPEC 0203; review of #437).
  testWidgets('search_and_filter_actions_toggle_their_part', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectivityStatusProvider.overrideWithValue(
            const AsyncData(ConnectivityStatus.online),
          ),
          emptyGrid,
          rootError,
        ],
        child: const MaterialApp(home: HistoryScreen()),
      ),
    );
    await tester.pump();
    final search = find.byType(TextField);
    // The filters' part, here in its error state, which needs no records.
    final chips = find.text('Não foi possível carregar os filtros');
    expect(search, findsNothing);
    expect(chips, findsNothing);

    await tester.tap(find.byTooltip('Buscar'));
    await tester.pump();
    expect(search, findsOneWidget);
    expect(chips, findsNothing);

    await tester.tap(find.byTooltip('Buscar'));
    await tester.pump();
    expect(search, findsNothing);

    await _openFilters(tester);
    expect(chips, findsOneWidget);
    expect(search, findsNothing);

    await _openFilters(tester);
    expect(chips, findsNothing);
  });

  testWidgets('filter error branch renders visible feedback and a retry', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectivityStatusProvider.overrideWithValue(
            const AsyncData(ConnectivityStatus.online),
          ),
          emptyGrid,
          rootError,
        ],
        child: const MaterialApp(home: HistoryScreen()),
      ),
    );
    await tester.pump();
    await _openFilters(tester);

    expect(find.text('Não foi possível carregar os filtros'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(CollapseOnCorrection),
        matching: find.text('Não foi possível carregar os filtros'),
      ),
      findsOneWidget,
    );
    expect(find.text('Tentar novamente'), findsOneWidget);
  });

  testWidgets('retry invalidates the root records stream, not just the wrapper', (
    tester,
  ) async {
    final spy = _DisposeSpy();
    await tester.pumpWidget(
      ProviderScope(
        observers: [spy],
        overrides: [
          connectivityStatusProvider.overrideWithValue(
            const AsyncData(ConnectivityStatus.online),
          ),
          emptyGrid,
          rootError,
        ],
        child: const MaterialApp(home: HistoryScreen()),
      ),
    );
    await tester.pump();
    await _openFilters(tester);

    expect(find.text('Tentar novamente'), findsOneWidget);
    spy.disposed.clear();
    await tester.tap(find.text('Tentar novamente'));
    await tester.pump();

    // The retry must invalidate the root records stream so a transient failure
    // actually re-runs; invalidating only the derived wrapper would re-read the
    // same cached failed stream.
    expect(spy.disposed, contains(soilRecordsStreamProvider));
  });

  SoilRecord record(int id) => SoilRecord(
    id: id,
    imagePath: 'x.png',
    timestamp: '2026-06-26T12:00:00Z',
    textureClass: 'Argilosa',
    confidenceScore: 0.9,
  );

  Widget appWith(
    FakeSoilRecordRepository repository,
    SoilRecord single, {
    ThemeData? theme,
  }) {
    return ProviderScope(
      overrides: [
        connectivityStatusProvider.overrideWithValue(
          const AsyncData(ConnectivityStatus.online),
        ),
        soilRecordsStreamProvider.overrideWithValue(
          AsyncValue<List<SoilRecord>>.data([single]),
        ),
        filteredRecordsProvider.overrideWith(
          (ref) => Stream.value(<SoilRecord>[single]),
        ),
        soilRecordRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(theme: theme, home: const HistoryScreen()),
    );
  }

  testWidgets(
    'confirming delete of a selected record deletes it and notifies',
    (tester) async {
      final repository = FakeSoilRecordRepository();
      await tester.pumpWidget(appWith(repository, record(7)));
      await tester.pumpAndSettle();

      // Long-press the card to enter multi-select mode.
      await tester.longPress(find.byType(Image));
      await tester.pumpAndSettle();

      // Trigger the delete action, then confirm the shared dialog.
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Excluir'));
      await tester.pumpAndSettle();

      expect(repository.deleteByIdsCalls, [
        [7],
      ]);
      expect(find.text('1 registro excluído.'), findsOneWidget);
    },
  );

  testWidgets('cancelling delete of a selected record deletes nothing', (
    tester,
  ) async {
    final repository = FakeSoilRecordRepository();
    await tester.pumpWidget(appWith(repository, record(7)));
    await tester.pumpAndSettle();

    await tester.longPress(find.byType(Image));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(repository.deleteByIdsCalls, isEmpty);
    expect(find.text('1 registro excluído.'), findsNothing);
  });

  // SPEC 0118: selection-mode buttons are labelled, and a thumbnail is a
  // labelled button that reports its selection.
  testWidgets('icon_buttons_are_labelled', (tester) async {
    await tester.pumpWidget(appWith(FakeSoilRecordRepository(), record(7)));
    await tester.pumpAndSettle();

    await tester.longPress(find.byType(Image));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Cancelar seleção'), findsOneWidget);
    expect(find.byTooltip('Excluir selecionados'), findsOneWidget);
  });

  testWidgets('history_thumbnails_are_accessible', (tester) async {
    final semantics = tester.ensureSemantics();
    final single = record(7);
    await tester.pumpWidget(appWith(FakeSoilRecordRepository(), single));
    await tester.pumpAndSettle();

    final thumbnail = find.bySemanticsLabel(
      RegExp(single.formattedTimestampCompact),
    );
    expect(thumbnail, findsWidgets);
    expect(
      tester.getSemantics(find.byType(AnalysisTile)),
      isSemantics(isButton: true, hasTapAction: true),
    );

    await tester.longPress(find.byType(Image));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(
        find
            .byWidgetPredicate(
              (w) => w is Semantics && w.properties.selected == true,
            )
            .first,
      ),
      isSemantics(isSelected: true),
    );
    semantics.dispose();
  });

  // A card opens details, where the photograph is one tap further
  // (SPEC 0125).
  testWidgets('tap_opens_details', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectivityStatusProvider.overrideWithValue(
            const AsyncData(ConnectivityStatus.online),
          ),
          soilRecordsStreamProvider.overrideWithValue(
            AsyncValue<List<SoilRecord>>.data([record(7)]),
          ),
          filteredRecordsProvider.overrideWith(
            (ref) => Stream.value(<SoilRecord>[record(7)]),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(
            routes: [
              GoRoute(path: '/', builder: (_, _) => const HistoryScreen()),
              GoRoute(
                path: '/details',
                builder: (_, state) =>
                    Scaffold(body: Text('DETAILS_STUB ${state.extra}')),
              ),
              GoRoute(
                path: '/preview',
                builder: (_, state) =>
                    Scaffold(body: Text('PREVIEW_STUB ${state.extra}')),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Image));
    await tester.pumpAndSettle();

    expect(find.text('DETAILS_STUB 7'), findsOneWidget);
    expect(find.textContaining('PREVIEW_STUB'), findsNothing);
  });

  // A selection is confirmed by one selection click; a long press already
  // vibrates through the platform, so it gets nothing more (SPEC 0126).
  group('selection_clicks', () {
    const click = 'HapticFeedbackType.selectionClick';

    testWidgets('a filter chip', (tester) async {
      final haptics = recordHaptics(tester);
      await tester.pumpWidget(appWith(FakeSoilRecordRepository(), record(7)));
      await tester.pumpAndSettle();
      await _openFilters(tester);

      await tester.tap(find.widgetWithText(FilterChip, 'Argilosa'));
      await tester.pumpAndSettle();

      expect(haptics, [click]);
    });

    testWidgets('a tap that toggles a record', (tester) async {
      final haptics = recordHaptics(tester);
      await tester.pumpWidget(appWith(FakeSoilRecordRepository(), record(7)));
      await tester.pumpAndSettle();
      await _selectBySemantics(tester, find.byType(AnalysisTile));
      expect(haptics, isEmpty);

      await tester.tap(find.byType(Image));
      await tester.pumpAndSettle();

      expect(haptics, [click]);
    });

    testWidgets('long_press_vibrates_once', (tester) async {
      final haptics = recordHaptics(tester);
      await tester.pumpWidget(appWith(FakeSoilRecordRepository(), record(7)));
      await tester.pumpAndSettle();

      await tester.longPress(find.byType(Image));
      await tester.pumpAndSettle();

      expect(find.text('1 selecionado'), findsOneWidget);
      expect(haptics, ['vibrate']);
    });
  });

  // Selection mode has an entry that is not a long press (SPEC 0122): a
  // row's "Selecionar" semantics action, since PNG 16's app bar offers none
  // (SPEC 0203).
  group('selection without a long press', () {
    Future<void> enterBySemantics(WidgetTester tester) async {
      await tester.pumpWidget(appWith(FakeSoilRecordRepository(), record(7)));
      await tester.pumpAndSettle();
      await _selectBySemantics(tester, find.byType(AnalysisTile));
    }

    IconButton deleteButton(WidgetTester tester) => tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.delete_outline),
    );

    testWidgets('selection_has_non_gesture_entry', (tester) async {
      await enterBySemantics(tester);

      expect(find.text('1 selecionado'), findsOneWidget);
      expect(find.byTooltip('Cancelar seleção'), findsOneWidget);
      expect(deleteButton(tester).onPressed, isNotNull);
    });

    testWidgets('selection_entry_needs_a_record', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectivityStatusProvider.overrideWithValue(
              const AsyncData(ConnectivityStatus.online),
            ),
            soilRecordsStreamProvider.overrideWithValue(
              const AsyncValue<List<SoilRecord>>.data(<SoilRecord>[]),
            ),
            emptyGrid,
          ],
          child: const MaterialApp(home: HistoryScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nenhuma análise ainda'), findsOneWidget);
      expect(find.byType(AnalysisTile), findsNothing);
    });

    testWidgets('selection_mode_offers_no_second_entry', (tester) async {
      final handle = tester.ensureSemantics();
      await enterBySemantics(tester);

      final node = tester.getSemantics(find.byType(AnalysisTile));
      expect(
        node.getSemanticsData().customSemanticsActionIds,
        isNot(
          contains(
            CustomSemanticsAction.getIdentifier(
              const CustomSemanticsAction(label: 'Selecionar'),
            ),
          ),
        ),
      );
      handle.dispose();
    });

    testWidgets('deselecting_the_last_record_ends_selection', (tester) async {
      await enterBySemantics(tester);

      await tester.tap(find.byType(Image));
      await tester.pumpAndSettle();

      expect(find.text('Histórico'), findsOneWidget);
      expect(find.byTooltip('Cancelar seleção'), findsNothing);
      expect(find.byTooltip('Filtros'), findsOneWidget);
    });
  });

  // Past the first page, a button at the end of the grid adds the next one,
  // under the filters and across selection mode (SPEC 0145).
  // Two selected records open their comparison (SPEC 0150).
  group('compare', () {
    final records = [record(7), record(8), record(9)];

    Widget routedApp() => ProviderScope(
      overrides: [
        connectivityStatusProvider.overrideWithValue(
          const AsyncData(ConnectivityStatus.online),
        ),
        soilRecordsStreamProvider.overrideWithValue(
          AsyncValue<List<SoilRecord>>.data(records),
        ),
        filteredRecordsProvider.overrideWith((ref) => Stream.value(records)),
        soilRecordRepositoryProvider.overrideWithValue(
          FakeSoilRecordRepository(),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(
          routes: [
            GoRoute(path: '/', builder: (_, _) => const HistoryScreen()),
            GoRoute(
              path: '/compare',
              builder: (_, state) => Scaffold(
                appBar: AppBar(),
                body: Text('COMPARE_STUB ${state.extra}'),
              ),
            ),
          ],
        ),
      ),
    );

    IconButton compareButton(WidgetTester tester) => tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.compare_arrows),
    );

    // Tall enough for all three cards in the two-column grid.
    void useATallScreen(WidgetTester tester) {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    Finder card(int id) => find.byKey(ValueKey(id));

    Future<void> select(WidgetTester tester, int id) async {
      await tester.tap(card(id));
      await tester.pumpAndSettle();
    }

    testWidgets('compare_needs_exactly_two', (tester) async {
      useATallScreen(tester);
      await tester.pumpWidget(routedApp());
      await tester.pumpAndSettle();
      await _selectBySemantics(
        tester,
        find.descendant(of: card(7), matching: find.byType(AnalysisTile)),
      );

      expect(compareButton(tester).onPressed, isNull, reason: 'one');
      await select(tester, 8);
      expect(compareButton(tester).onPressed, isNotNull, reason: 'two');
      await select(tester, 9);
      expect(compareButton(tester).onPressed, isNull, reason: 'three');
    });

    testWidgets('compare_opens_with_the_two_ids', (tester) async {
      await tester.pumpWidget(routedApp());
      await tester.pumpAndSettle();
      await tester.longPress(card(7));
      await tester.pumpAndSettle();
      await select(tester, 8);

      await tester.tap(find.byTooltip('Comparar selecionados'));
      await tester.pumpAndSettle();
      expect(find.text('COMPARE_STUB [7, 8]'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('2 selecionados'), findsOneWidget);
      expect(compareButton(tester).onPressed, isNotNull);
    });

    testWidgets('compare_is_labelled', (tester) async {
      await tester.pumpWidget(routedApp());
      await tester.pumpAndSettle();
      await tester.longPress(card(7));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Comparar selecionados'), findsOneWidget);
    });
  });

  group('browsing past the first page', () {
    const showMore = 'Mostrar mais registros';
    // Ids count..1, newest first; even ids are Argilosa and odd ones Arenosa.
    final all = [
      for (var id = 400; id >= 1; id--)
        SoilRecord(
          id: id,
          imagePath: 'x.png',
          timestamp: '2026-06-26T12:00:00Z',
          textureClass: id.isEven ? 'Argilosa' : 'Arenosa',
          confidenceScore: 0.9,
        ),
    ];

    Widget appWithAll() => ProviderScope(
      overrides: [
        connectivityStatusProvider.overrideWithValue(
          const AsyncData(ConnectivityStatus.online),
        ),
        soilRecordsStreamProvider.overrideWithValue(
          AsyncValue<List<SoilRecord>>.data(all),
        ),
        soilRecordRepositoryProvider.overrideWithValue(
          _ListSoilRecordRepository(all),
        ),
      ],
      child: const MaterialApp(home: HistoryScreen()),
    );

    int gridCount(WidgetTester tester) {
      final grid = tester.widget<SliverList>(find.byType(SliverList));
      return (grid.delegate as SliverChildBuilderDelegate).childCount!;
    }

    Future<void> tapShowMore(WidgetTester tester) async {
      await tester.scrollUntilVisible(
        find.text(showMore),
        3000,
        scrollable: find
            .byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(showMore));
      await tester.pumpAndSettle();
    }

    testWidgets('show_more_keeps_the_filters', (tester) async {
      await tester.pumpWidget(appWithAll());
      await tester.pumpAndSettle();
      await _openFilters(tester);
      await tester.tap(find.widgetWithText(FilterChip, 'Argilosa'));
      await tester.pumpAndSettle();
      expect(gridCount(tester), 150);

      await tapShowMore(tester);

      expect(gridCount(tester), 200);
      expect(find.text(showMore), findsNothing);
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'Argilosa'))
            .selected,
        isTrue,
      );
    });

    testWidgets('selection_keeps_the_shown_records', (tester) async {
      await tester.pumpWidget(appWithAll());
      await tester.pumpAndSettle();
      await tapShowMore(tester);
      expect(gridCount(tester), 300);

      await _selectBySemantics(tester, find.byType(AnalysisTile).first);
      expect(gridCount(tester), 300);

      await tester.tap(find.byTooltip('Cancelar seleção'));
      await tester.pumpAndSettle();
      expect(gridCount(tester), 300);
    });
  });

  // At 200 % text on a phone, the grid, its empty state and the filter error
  // row still lay out (SPEC 0121).
  testWidgets('history_scales_to_200_percent', (tester) async {
    useLargeTextOnAPhone(tester);

    await tester.pumpWidget(appWith(FakeSoilRecordRepository(), record(7)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'grid');

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectivityStatusProvider.overrideWithValue(
            const AsyncData(ConnectivityStatus.online),
          ),
          emptyGrid,
          rootError,
        ],
        child: const MaterialApp(home: HistoryScreen()),
      ),
    );
    await tester.pump();
    await _openFilters(tester);
    expect(find.text('Tentar novamente'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'empty, filter error');
  });

  // A record, and selection mode, each pass Flutter's four accessibility
  // guidelines (SPEC 0133).
  for (final (name, theme) in appThemes) {
    testWidgets('screens_meet_guidelines in the $name theme', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        appWith(FakeSoilRecordRepository(), record(7), theme: theme),
      );
      await tester.pumpAndSettle();
      await expectMeetsGuidelines(tester);

      await tester.longPress(find.byType(Image));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Excluir selecionados'), findsOneWidget);
      await expectMeetsGuidelines(tester);
      semantics.dispose();
    });
  }
}
