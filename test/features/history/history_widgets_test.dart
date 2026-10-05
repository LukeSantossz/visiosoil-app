// Direct render tests for the history screen's extracted widgets (#120):
// HistoryFilterBar (search field + texture chips) and HistoryGrid (results grid
// and empty state). Complements the flow coverage in history_screen_test.dart.
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
    Widget gridWith(List<SoilRecord> records) => ProviderScope(
          overrides: [
            filteredRecordsProvider.overrideWith((ref) => Stream.value(records)),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: HistoryGrid(
                maxRecords: 150,
                selectedIds: const <int>{},
                isSelectionMode: false,
                onTap: (_) {},
                onLongPress: (_) {},
              ),
            ),
          ),
        );

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

    // The grid stops at maxRecords; past it, it says so (SPEC 0128).
    const notice = 'Mostrando os 150 registros mais recentes. Use a busca ou '
        'os filtros para encontrar os mais antigos.';
    List<SoilRecord> records(int count) =>
        [for (var id = count; id >= 1; id--) record(id: id)];
    int gridCount(WidgetTester tester) {
      final grid = tester.widget<GridView>(find.byType(GridView));
      return (grid.childrenDelegate as SliverChildBuilderDelegate).childCount!;
    }

    testWidgets('cap_is_disclosed', (tester) async {
      await tester.pumpWidget(gridWith(records(151)));
      await tester.pumpAndSettle();

      expect(gridCount(tester), 150);
      expect(find.text(notice), findsOneWidget);
    });

    testWidgets('no_notice_under_the_cap', (tester) async {
      await tester.pumpWidget(gridWith(records(150)));
      await tester.pumpAndSettle();

      expect(gridCount(tester), 150);
      expect(find.text(notice), findsNothing);
    });
  });
}
