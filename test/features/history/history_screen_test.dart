import 'dart:async';

import 'package:flutter/material.dart';
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
  }) =>
      Stream.value([
        for (final record in records)
          if (textureClass == null || record.textureClass == textureClass)
            record,
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

void main() {
  // A synchronous AsyncError on the root stream reliably drives the chips into
  // the error branch (async stream errors do not settle under flutter_test).
  final rootError = soilRecordsStreamProvider.overrideWithValue(
    AsyncValue<List<SoilRecord>>.error(Exception('boom'), StackTrace.current),
  );
  final emptyGrid =
      filteredRecordsProvider.overrideWith((ref) => Stream.value(<SoilRecord>[]));

  testWidgets('filter error branch renders visible feedback and a retry',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [emptyGrid, rootError],
      child: const MaterialApp(home: HistoryScreen()),
    ));
    await tester.pump();

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

  testWidgets('retry invalidates the root records stream, not just the wrapper',
      (tester) async {
    final spy = _DisposeSpy();
    await tester.pumpWidget(ProviderScope(
      observers: [spy],
      overrides: [emptyGrid, rootError],
      child: const MaterialApp(home: HistoryScreen()),
    ));
    await tester.pump();

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
        soilRecordsStreamProvider.overrideWithValue(
          AsyncValue<List<SoilRecord>>.data([single]),
        ),
        filteredRecordsProvider
            .overrideWith((ref) => Stream.value(<SoilRecord>[single])),
        soilRecordRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(theme: theme, home: const HistoryScreen()),
    );
  }

  testWidgets('confirming delete of a selected record deletes it and notifies',
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
  });

  testWidgets('cancelling delete of a selected record deletes nothing',
      (tester) async {
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

    final label = 'Registro de ${single.formattedTimestampCompact}';
    final thumbnail = find.bySemanticsLabel(label);
    expect(thumbnail, findsOneWidget);
    expect(
      tester.getSemantics(thumbnail),
      matchesSemantics(
        label: label,
        isButton: true,
        hasTapAction: true,
        hasLongPressAction: true,
        hasFocusAction: true,
        isFocusable: true,
      ),
    );
    // The ink sits over the photograph, in the card's own stack.
    final card = find.ancestor(of: find.byType(Image), matching: find.byType(Stack));
    expect(
      find.descendant(of: card.first, matching: find.byType(InkWell)),
      findsOneWidget,
    );

    await tester.longPress(find.byType(Image));
    await tester.pumpAndSettle();
    expect(tester.getSemantics(thumbnail), isSemantics(isSelected: true));
    semantics.dispose();
  });

  // A card opens details, where the photograph is one tap further
  // (SPEC 0125).
  testWidgets('tap_opens_details', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        soilRecordsStreamProvider.overrideWithValue(
          AsyncValue<List<SoilRecord>>.data([record(7)]),
        ),
        filteredRecordsProvider
            .overrideWith((ref) => Stream.value(<SoilRecord>[record(7)])),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(routes: [
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
        ]),
      ),
    ));
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

      await tester.tap(find.widgetWithText(FilterChip, 'Argilosa'));
      await tester.pumpAndSettle();

      expect(haptics, [click]);
    });

    testWidgets('a tap that toggles a record', (tester) async {
      final haptics = recordHaptics(tester);
      await tester.pumpWidget(appWith(FakeSoilRecordRepository(), record(7)));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Selecionar registros'));
      await tester.pumpAndSettle();
      expect(haptics, isEmpty);

      await tester.tap(find.byType(Image));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Image));
      await tester.pumpAndSettle();

      expect(haptics, [click, click]);
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

  // Selection mode has an entry that is not a long press (SPEC 0122).
  group('selection without a long press', () {
    Future<void> enterByTheButton(WidgetTester tester) async {
      await tester.pumpWidget(appWith(FakeSoilRecordRepository(), record(7)));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Selecionar registros'));
      await tester.pumpAndSettle();
    }

    IconButton deleteButton(WidgetTester tester) => tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.delete_outline),
        );

    testWidgets('selection_has_non_gesture_entry', (tester) async {
      await enterByTheButton(tester);

      expect(find.text('Nenhum selecionado'), findsOneWidget);
      expect(find.byTooltip('Cancelar seleção'), findsOneWidget);
      expect(deleteButton(tester).onPressed, isNull);

      // A tap now selects the record instead of opening the preview, which
      // this harness has no route for.
      await tester.tap(find.byType(Image));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('1 selecionado'), findsOneWidget);
      expect(deleteButton(tester).onPressed, isNotNull);
    });

    testWidgets('selection_entry_needs_a_record', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          soilRecordsStreamProvider.overrideWithValue(
            const AsyncValue<List<SoilRecord>>.data(<SoilRecord>[]),
          ),
          emptyGrid,
        ],
        child: const MaterialApp(home: HistoryScreen()),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Nenhum registro'), findsOneWidget);
      expect(find.byTooltip('Selecionar registros'), findsNothing);
    });

    // The button follows what the grid shows: a stream that fails after
    // records keeps them in `value`, but the grid shows its error.
    testWidgets('selection_entry_follows_the_grid', (tester) async {
      final records = StreamController<List<SoilRecord>>();
      addTearDown(records.close);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          soilRecordsStreamProvider.overrideWithValue(
            AsyncValue<List<SoilRecord>>.data([record(7)]),
          ),
          filteredRecordsProvider.overrideWith((ref) => records.stream),
        ],
        child: const MaterialApp(home: HistoryScreen()),
      ));
      records.add([record(7)]);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Selecionar registros'), findsOneWidget);

      records.addError(Exception('boom'));
      await tester.pumpAndSettle();

      expect(find.text('Não foi possível carregar o histórico.'), findsOneWidget);
      expect(find.byTooltip('Selecionar registros'), findsNothing);
    });

    testWidgets('selection_entry_is_labelled', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(appWith(FakeSoilRecordRepository(), record(7)));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Selecionar registros'), findsOneWidget);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      semantics.dispose();
    });

    testWidgets('deselecting_the_last_record_ends_selection', (tester) async {
      await enterByTheButton(tester);

      await tester.tap(find.byType(Image));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Image));
      await tester.pumpAndSettle();

      expect(find.text('Histórico'), findsOneWidget);
      expect(find.byTooltip('Cancelar seleção'), findsNothing);
      expect(find.byTooltip('Selecionar registros'), findsOneWidget);
    });
  });

  // Past the first page, a button at the end of the grid adds the next one,
  // under the filters and across selection mode (SPEC 0145).
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
            soilRecordsStreamProvider
                .overrideWithValue(AsyncValue<List<SoilRecord>>.data(all)),
            soilRecordRepositoryProvider
                .overrideWithValue(_ListSoilRecordRepository(all)),
          ],
          child: const MaterialApp(home: HistoryScreen()),
        );

    int gridCount(WidgetTester tester) {
      final grid = tester.widget<SliverGrid>(find.byType(SliverGrid));
      return (grid.delegate as SliverChildBuilderDelegate).childCount!;
    }

    Future<void> tapShowMore(WidgetTester tester) async {
      await tester.scrollUntilVisible(
        find.text(showMore),
        3000,
        scrollable: find
            .byWidgetPredicate((widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down)
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(showMore));
      await tester.pumpAndSettle();
    }

    testWidgets('show_more_keeps_the_filters', (tester) async {
      await tester.pumpWidget(appWithAll());
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Argilosa'));
      await tester.pumpAndSettle();
      expect(gridCount(tester), 150);

      await tapShowMore(tester);

      expect(gridCount(tester), 200);
      expect(find.text(showMore), findsNothing);
      expect(
        tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'Argilosa'))
            .selected,
        isTrue,
      );
    });

    testWidgets('selection_keeps_the_shown_records', (tester) async {
      await tester.pumpWidget(appWithAll());
      await tester.pumpAndSettle();
      await tapShowMore(tester);
      expect(gridCount(tester), 300);

      await tester.tap(find.byTooltip('Selecionar registros'));
      await tester.pumpAndSettle();
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
    await tester.pumpWidget(ProviderScope(
      overrides: [emptyGrid, rootError],
      child: const MaterialApp(home: HistoryScreen()),
    ));
    await tester.pump();
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
