// Direct render tests for the history screen's extracted widgets (#120):
// HistoryFilterBar (search field + texture chips) and HistoryGrid (results grid
// and empty state). Complements the flow coverage in history_screen_test.dart.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/history/widgets/history_filter_bar.dart';
import 'package:visiosoil_app/core/features/history/widgets/history_grid.dart';
import 'package:visiosoil_app/core/theme/app_motion.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';

import '../../support/guidelines.dart';
import '../../support/large_text.dart';

Future<void> pumpFilterBar(WidgetTester tester) async {
  final container = ProviderContainer(
    overrides: [
      soilRecordsStreamProvider.overrideWithValue(
        AsyncValue<List<SoilRecord>>.data([record()]),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: HistoryFilterBar(
          searchController: TextEditingController(),
          onSearchChanged: (_) {},
          onClearSearch: () {},
          onSelectTexture: (value) => container
              .read(selectedTextureFilterProvider.notifier)
              .select(value),
        ),
      ),
    ),
  ));
  await tester.pump();
}

void expectChipTransition(
  WidgetTester tester,
  String label, {
  required Color color,
  required Color border,
  required FontWeight weight,
}) {
  final style = DefaultTextStyle.of(tester.element(find.text(label))).style;
  expect(style.color, color);
  expect(style.fontWeight, weight);
  final box = tester.widget<Container>(find.ancestor(
    of: find.widgetWithText(FilterChip, label),
    matching: find.byWidgetPredicate(
      (widget) => widget is Container && widget.foregroundDecoration != null,
    ),
  ));
  final decoration = box.foregroundDecoration! as BoxDecoration;
  expect(decoration.border!.top.color, border);
  expect(
    tester.widget<FilterChip>(find.widgetWithText(FilterChip, label)).side,
    BorderSide.none,
  );
}

Finder materialOf(String label) => find.descendant(
      of: find.widgetWithText(FilterChip, label),
      matching: find.byType(PhysicalShape),
    );

double channelDistance(Color color, Color end) =>
    (color.r - end.r).abs() + (color.g - end.g).abs() + (color.b - end.b).abs();

SoilRecord record({int id = 1, String textureClass = 'Argilosa'}) => SoilRecord(
      id: id,
      imagePath: 'x.png',
      timestamp: '2026-06-26T12:00:00Z',
      textureClass: textureClass,
      confidenceScore: 0.9,
    );

void main() {
  group('HistoryFilterBar', () {
    testWidgets('renders the search field and a chip per available class',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          soilRecordsStreamProvider.overrideWithValue(
            AsyncValue<List<SoilRecord>>.data([record()]),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: HistoryFilterBar(
              searchController: TextEditingController(),
              onSearchChanged: (_) {},
              onClearSearch: () {},
              onSelectTexture: (_) {},
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Todas'), findsOneWidget);
      expect(find.text('Argilosa'), findsOneWidget);
    });

    testWidgets('tapping a class chip forwards it to onSelectTexture',
        (tester) async {
      String? selected;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          soilRecordsStreamProvider.overrideWithValue(
            AsyncValue<List<SoilRecord>>.data([record()]),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: HistoryFilterBar(
              searchController: TextEditingController(),
              onSearchChanged: (_) {},
              onClearSearch: () {},
              onSelectTexture: (value) => selected = value,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Argilosa'));
      expect(selected, 'Argilosa');
    });

    // SPEC 0137: the label and the border move over 140 ms.
    testWidgets('chip_colour_and_border_transition', (tester) async {
      await pumpFilterBar(tester);
      final context = tester.element(find.byType(HistoryFilterBar));
      final scheme = Theme.of(context).colorScheme;
      final primary = AppPalette.of(context).primary;
      final t = AppMotion.standard.transform(0.5);

      await tester.tap(find.text('Argilosa'));
      await tester.pump();
      await tester.pump(AppMotion.fast ~/ 2);

      expectChipTransition(
        tester,
        'Argilosa',
        color: Color.lerp(scheme.onSurface, primary, t)!,
        border: Color.lerp(scheme.outline, primary, t)!,
        weight: FontWeight.lerp(FontWeight.normal, FontWeight.w600, t)!,
      );
      expectChipTransition(
        tester,
        'Todas',
        color: Color.lerp(primary, scheme.onSurface, t)!,
        border: Color.lerp(primary, scheme.outline, t)!,
        weight: FontWeight.lerp(FontWeight.w600, FontWeight.normal, t)!,
      );

      await tester.pump(AppMotion.fast ~/ 2);

      expectChipTransition(
        tester,
        'Argilosa',
        color: primary,
        border: primary,
        weight: FontWeight.w600,
      );
      expectChipTransition(
        tester,
        'Todas',
        color: scheme.onSurface,
        border: scheme.outline,
        weight: FontWeight.normal,
      );

      expect(tester.getSize(materialOf('Todas')), tester.getSize(find.ancestor(
            of: find.widgetWithText(FilterChip, 'Todas'),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Container && widget.foregroundDecoration != null,
            ),
          )));
    });

    testWidgets('chip_padding_still_selects', (tester) async {
      await pumpFilterBar(tester);
      final rect = tester.getRect(materialOf('Argilosa'));

      await tester.tapAt(rect.topCenter - const Offset(0, 1));
      await tester.pump();

      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'Argilosa'))
            .selected,
        isTrue,
      );
    });

    testWidgets('chip_transition_respects_reduced_motion', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpFilterBar(tester);
      final context = tester.element(find.byType(HistoryFilterBar));
      final scheme = Theme.of(context).colorScheme;
      final primary = AppPalette.of(context).primary;

      await tester.tap(find.text('Argilosa'));
      await tester.pump();

      expectChipTransition(
        tester,
        'Argilosa',
        color: primary,
        border: primary,
        weight: FontWeight.w600,
      );
      expectChipTransition(
        tester,
        'Todas',
        color: scheme.onSurface,
        border: scheme.outline,
        weight: FontWeight.normal,
      );
    });

    testWidgets('chip_starts_on_its_selection', (tester) async {
      await pumpFilterBar(tester);
      final context = tester.element(find.byType(HistoryFilterBar));
      final scheme = Theme.of(context).colorScheme;
      final primary = AppPalette.of(context).primary;

      expectChipTransition(
        tester,
        'Todas',
        color: primary,
        border: primary,
        weight: FontWeight.w600,
      );
      expectChipTransition(
        tester,
        'Argilosa',
        color: scheme.onSurface,
        border: scheme.outline,
        weight: FontWeight.normal,
      );
    });

    testWidgets('chip_retargets_mid_transition', (tester) async {
      await pumpFilterBar(tester);
      final context = tester.element(find.byType(HistoryFilterBar));
      final scheme = Theme.of(context).colorScheme;
      final primary = AppPalette.of(context).primary;

      await tester.tap(find.widgetWithText(FilterChip, 'Argilosa'));
      await tester.pump();
      await tester.pump(AppMotion.fast ~/ 2);

      final beforeStyle =
          DefaultTextStyle.of(tester.element(find.text('Argilosa'))).style;
      final beforeBorder = (tester
              .widget<Container>(find.ancestor(
                of: find.widgetWithText(FilterChip, 'Argilosa'),
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is Container && widget.foregroundDecoration != null,
                ),
              ))
              .foregroundDecoration! as BoxDecoration)
          .border!
          .top
          .color;

      await tester.tap(find.widgetWithText(FilterChip, 'Todas'));
      await tester.pump();
      await tester.pump(AppMotion.fast ~/ 2);

      final afterStyle =
          DefaultTextStyle.of(tester.element(find.text('Argilosa'))).style;
      final afterBorder = (tester
              .widget<Container>(find.ancestor(
                of: find.widgetWithText(FilterChip, 'Argilosa'),
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is Container && widget.foregroundDecoration != null,
                ),
              ))
              .foregroundDecoration! as BoxDecoration)
          .border!
          .top
          .color;
      expect(
        channelDistance(afterStyle.color!, scheme.onSurface),
        lessThan(channelDistance(beforeStyle.color!, scheme.onSurface)),
      );
      expect(
        channelDistance(afterBorder, scheme.outline),
        lessThan(channelDistance(beforeBorder, scheme.outline)),
      );
      expect(
        afterStyle.fontWeight!.value,
        lessThan(beforeStyle.fontWeight!.value),
      );

      await tester.pump(AppMotion.fast ~/ 2);

      expectChipTransition(
        tester,
        'Argilosa',
        color: scheme.onSurface,
        border: scheme.outline,
        weight: FontWeight.normal,
      );
      expectChipTransition(
        tester,
        'Todas',
        color: primary,
        border: primary,
        weight: FontWeight.w600,
      );
    });
  });

  // SPEC 0118: the search's clear button is labelled.
  testWidgets('icon_buttons_are_labelled', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        soilRecordsStreamProvider.overrideWithValue(
          AsyncValue<List<SoilRecord>>.data([record()]),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: HistoryFilterBar(
            searchController: TextEditingController(text: 'fazenda'),
            onSearchChanged: (_) {},
            onClearSearch: () {},
            onSelectTexture: (_) {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    // The clear button shows once a term is set.
    ProviderScope.containerOf(tester.element(find.byType(HistoryFilterBar)))
        .read(searchTermProvider.notifier)
        .update('fazenda');
    await tester.pumpAndSettle();

    expect(find.byTooltip('Limpar busca'), findsOneWidget);
  });

  group('HistoryGrid', () {
    Widget gridOn(
      Stream<List<SoilRecord>> Function() stream, {
      ThemeData? theme,
    }) =>
        ProviderScope(
          overrides: [
            filteredRecordsProvider.overrideWith((ref) => stream()),
          ],
          child: MaterialApp(
            theme: theme,
            home: Scaffold(
              body: HistoryGrid(
                pageSize: 150,
                selectedIds: const <int>{},
                isSelectionMode: false,
                onTap: (_) {},
                onLongPress: (_) {},
              ),
            ),
          ),
        );
    Widget gridWith(List<SoilRecord> records, {ThemeData? theme}) =>
        gridOn(() => Stream.value(records), theme: theme);

    testWidgets('renders a thumbnail card per record', (tester) async {
      await tester.pumpWidget(gridWith([record(id: 1), record(id: 2)]));
      await tester.pumpAndSettle();

      expect(find.byType(Image), findsNWidgets(2));
    });

    testWidgets('shows the empty history state when there are no records',
        (tester) async {
      await tester.pumpWidget(gridWith(const <SoilRecord>[]));
      await tester.pumpAndSettle();

      expect(find.text('Nenhum registro'), findsOneWidget);
    });

    // The grid shows a page at a time and says how much of the total it
    // shows (SPEC 0128); a button at its end adds the next page (SPEC 0145).
    const showMore = 'Mostrar mais registros';
    List<SoilRecord> records(int count) =>
        [for (var id = count; id >= 1; id--) record(id: id)];
    SliverChildBuilderDelegate delegate(WidgetTester tester) =>
        tester.widget<SliverGrid>(find.byType(SliverGrid)).delegate
            as SliverChildBuilderDelegate;
    // The thumbnails shown, which is also the count the scroll view announces
    // to a screen reader, as the GridView it replaced did.
    int gridCount(WidgetTester tester) {
      final count = delegate(tester).childCount!;
      expect(
        tester
            .widget<CustomScrollView>(find.byType(CustomScrollView))
            .semanticChildCount,
        count,
      );
      return count;
    }
    // The ids the grid shows, in its order, read from each card's key.
    List<int> shownIds(WidgetTester tester) {
      final context = tester.element(find.byType(SliverGrid));
      return [
        for (var index = 0; index < gridCount(tester); index++)
          (delegate(tester).builder(context, index)!.key! as ValueKey<int>)
              .value,
      ];
    }

    Future<void> tapShowMore(WidgetTester tester) async {
      await tester.scrollUntilVisible(find.text(showMore), 3000);
      await tester.pumpAndSettle();
      await tester.tap(find.text(showMore));
      await tester.pumpAndSettle();
    }

    testWidgets('cap_is_disclosed', (tester) async {
      await tester.pumpWidget(gridWith(records(151)));
      await tester.pumpAndSettle();

      expect(gridCount(tester), 150);
      expect(
        find.text('Mostrando os 150 registros mais recentes de 151.'),
        findsOneWidget,
      );

      await tapShowMore(tester);
      expect(find.textContaining('Mostrando os'), findsNothing);
    });

    testWidgets('show_more_reveals_the_next_records', (tester) async {
      await tester.pumpWidget(gridWith(records(400)));
      await tester.pumpAndSettle();
      expect(shownIds(tester), [for (var id = 400; id > 250; id--) id]);

      await tapShowMore(tester);
      expect(shownIds(tester), [for (var id = 400; id > 100; id--) id]);
      expect(
        find.text('Mostrando os 300 registros mais recentes de 400.'),
        findsOneWidget,
      );

      await tapShowMore(tester);
      expect(shownIds(tester), [for (var id = 400; id > 0; id--) id]);
      expect(find.text(showMore), findsNothing);
      expect(find.textContaining('Mostrando os'), findsNothing);
    });

    testWidgets('count_survives_a_filter_change', (tester) async {
      final stream = StreamController<List<SoilRecord>>();
      addTearDown(stream.close);
      await tester.pumpWidget(gridOn(() => stream.stream));
      stream.add(records(400));
      await tester.pumpAndSettle();
      await tapShowMore(tester);
      expect(gridCount(tester), 300);

      // A filter or a term rebuilds the grid; the count it reached stays.
      final container =
          ProviderScope.containerOf(tester.element(find.byType(HistoryGrid)));
      container.read(selectedTextureFilterProvider.notifier).select('Argilosa');
      container.read(searchTermProvider.notifier).update('fazenda');
      await tester.pumpAndSettle();
      expect(gridCount(tester), 300);

      stream.add(records(250));
      await tester.pumpAndSettle();

      expect(gridCount(tester), 250);
      expect(find.text(showMore), findsNothing);
      expect(find.textContaining('Mostrando os'), findsNothing);
    });

    testWidgets('no_button_when_all_are_shown', (tester) async {
      for (final count in [150, 3]) {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(gridWith(records(count)));
        await tester.pumpAndSettle();
        await scrollToTheEnd(tester);

        expect(gridCount(tester), count);
        expect(find.text(showMore), findsNothing, reason: '$count records');
        expect(find.textContaining('Mostrando os'), findsNothing);
      }
    });

    for (final (name, theme) in appThemes) {
      testWidgets('show_more_meets_guidelines in the $name theme',
          (tester) async {
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(gridWith(records(151), theme: theme));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text(showMore), 3000);

        expect(
          tester.getSemantics(find.bySemanticsLabel(showMore)),
          isSemantics(isButton: true, hasTapAction: true),
        );
        await expectMeetsGuidelines(tester);
        semantics.dispose();
      });
    }

    testWidgets('show_more_scales_to_200_percent', (tester) async {
      useLargeTextOnAPhone(tester);
      await tester.pumpWidget(gridWith(records(151), theme: AppTheme.light));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text(showMore), 3000);

      expect(tester.takeException(), isNull);
      await tapShowMore(tester);
      expect(gridCount(tester), 151);
    });

    testWidgets('hc_selection_is_a_border', (tester) async {
      Future<void> pump(ThemeData theme, {required bool selected}) {
        return tester.pumpWidget(ProviderScope(
          overrides: [
            filteredRecordsProvider.overrideWith(
              (ref) => Stream.value([record(id: 7)]),
            ),
          ],
          child: MaterialApp(
            theme: theme,
            home: Scaffold(
              body: HistoryGrid(
                pageSize: 150,
                selectedIds: selected ? {7} : const <int>{},
                isSelectionMode: true,
                onTap: (_) {},
                onLongPress: (_) {},
              ),
            ),
          ),
        ));
      }

      BoxDecoration? wash(Color color) {
        for (final box in tester.widgetList<DecoratedBox>(find.byType(DecoratedBox))) {
          final decoration = box.decoration;
          if (decoration is BoxDecoration && decoration.color == color) {
            return decoration;
          }
        }
        return null;
      }

      await pump(AppTheme.lightHighContrast, selected: true);
      await tester.pumpAndSettle();
      final selectedHc = wash(Colors.transparent);
      expect(selectedHc, isNotNull);
      expect(selectedHc!.border?.top.color, AppPalette.light.primary);
      expect(selectedHc.border?.top.width, AppPalette.lightHighContrast.edgeWidth);

      await tester.pumpWidget(const SizedBox());
      await pump(AppTheme.lightHighContrast, selected: false);
      await tester.pumpAndSettle();
      final openMark = tester.widget<Container>(find.byWidgetPredicate((widget) {
        final decoration = widget is Container ? widget.decoration : null;
        return decoration is BoxDecoration && decoration.shape == BoxShape.circle;
      }));
      expect(
        (openMark.decoration! as BoxDecoration).color,
        AppPalette.lightHighContrast.surface,
      );

      await tester.pumpWidget(const SizedBox());
      await pump(AppTheme.light, selected: true);
      await tester.pumpAndSettle();
      expect(
        wash(AppPalette.light.primary.withValues(alpha: 0.3)),
        isNotNull,
      );
    });

    testWidgets('no_notice_under_the_cap', (tester) async {
      await tester.pumpWidget(gridWith(records(150)));
      await tester.pumpAndSettle();

      expect(gridCount(tester), 150);
      expect(find.textContaining('Mostrando os'), findsNothing);
    });
  });
}
