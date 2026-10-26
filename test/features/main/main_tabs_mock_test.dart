// The navigation bar, Home and the history follow PNG 08, 16, 25 and 27 as
// SPEC 0203 measures them.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:visiosoil_app/core/features/history/history_screen.dart';
import 'package:visiosoil_app/core/features/home/home_screen.dart';
import 'package:visiosoil_app/core/features/main/main_screen.dart';
import 'package:visiosoil_app/core/services/connectivity_service.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';
import 'package:visiosoil_app/core/widgets/analysis_tile.dart';
import 'package:visiosoil_app/core/widgets/segmented_control.dart';
import 'package:visiosoil_app/core/widgets/stat_cell.dart';
import 'package:visiosoil_app/core/widgets/status_pill.dart';
import 'package:visiosoil_app/core/widgets/visio_soil_logo.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/connectivity_provider.dart';
import 'package:visiosoil_app/providers/main_tab_index_provider.dart';
import 'package:visiosoil_app/providers/management_tips_repository_provider.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';

import '../../support/fake_soil_record_repository.dart';
import '../../support/management_tips_fakes.dart';

final _now = DateTime.now();

SoilRecord _record(int id, {String sync = 'synced', int minute = 0}) =>
    SoilRecord(
      id: id,
      imagePath: 'missing.png',
      timestamp: DateTime(
        _now.year,
        _now.month,
        _now.day,
        0,
        minute,
      ).toIso8601String(),
      textureClass: 'Argilosa',
      confidenceScore: 0.82,
      syncStatus: sync,
    );

final _records = [
  _record(1, minute: 2),
  _record(2, sync: 'pending', minute: 1),
];

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Widget home = const MainScreen(),
  ThemeData? theme,
  List<SoilRecord>? records,
}) async {
  final shown = records ?? _records;
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => home),
      GoRoute(
        path: '/details',
        builder: (_, state) => Text('DETAILS_STUB ${state.extra}'),
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
      soilRecordsStreamProvider.overrideWith((ref) => Stream.value(shown)),
      managementTipsRepositoryProvider.overrideWithValue(
        FakeManagementTipsRepository(),
      ),
      filteredRecordsProvider.overrideWith((ref) => Stream.value(shown)),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: theme ?? AppTheme.light,
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return container;
}

TextStyle _labelStyle(Set<WidgetState> states) =>
    AppTheme.light.navigationBarTheme.labelTextStyle!.resolve(states)!;

void main() {
  testWidgets('navigation_bar_matches_the_mock', (tester) async {
    _phone(tester);
    await _pump(tester, home: const MainScreen());

    final palette = AppPalette.light;
    expect(
      AppTheme.light.navigationBarTheme.backgroundColor,
      palette.surfaceContainer,
    );
    final selected = _labelStyle({WidgetState.selected});
    final idle = _labelStyle({});
    expect(selected.color, palette.onSurface);
    expect(selected.fontWeight, FontWeight.w600);
    expect(idle.color, palette.onSurfaceVariant);
    expect(idle.fontSize, 12);
    expect(idle.letterSpacing, 0);

    final rule = tester.widget<DecoratedBox>(
      find.byKey(const Key('navigation-bar-rule')),
    );
    final border = (rule.decoration as BoxDecoration).border! as Border;
    expect(border.top.color, palette.divider);
    expect(border.top.width, 1);
  });

  testWidgets('home_header_is_the_title_alone', (tester) async {
    _phone(tester);
    await _pump(tester, home: const HomeScreen());

    expect(find.text('Início'), findsOneWidget);
    expect(find.byTooltip('Configurações'), findsNothing);
    expect(find.byType(VisioSoilLogo), findsNothing);
    expect(tester.getTopLeft(find.text('Início')).dx, 20);
  });

  for (final (name, theme, palette) in [
    ('light', AppTheme.light, AppPalette.light),
    ('dark', AppTheme.dark, AppPalette.dark),
    ('sun', AppTheme.sun, AppPalette.sun),
  ]) {
    testWidgets('home_page_is_surface_container ($name)', (tester) async {
      _phone(tester);
      await _pump(tester, home: const HomeScreen(), theme: theme);

      final scaffold = tester.widget<Scaffold>(
        find.descendant(
          of: find.byType(HomeScreen),
          matching: find.byType(Scaffold),
        ),
      );
      expect(
        scaffold.backgroundColor,
        palette.isSun ? palette.background : palette.surfaceContainer,
      );
    });
  }

  testWidgets('home_stats_match_the_mock', (tester) async {
    _phone(tester);
    await _pump(tester, home: const HomeScreen());

    final cells = find.byType(StatCell);
    expect(cells, findsNWidgets(3));
    for (var i = 0; i < 3; i++) {
      expect(tester.getSize(cells.at(i)).height, greaterThanOrEqualTo(120));
    }
    final icons = tester.widgetList<Icon>(
      find.descendant(of: cells, matching: find.byType(Icon)),
    );
    expect(icons.map((icon) => icon.icon), [
      LucideIcons.scan,
      LucideIcons.layers,
      LucideIcons.sprout,
    ]);
    expect(icons.every((icon) => icon.size == 18), isTrue);
    expect(tester.widgetList<StatCell>(cells).map((cell) => cell.value), [
      '2',
      '0/12',
      '82%',
    ]);
    final shadows = tester
        .widgetList<Container>(
          find.descendant(of: cells, matching: find.byType(Container)),
        )
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.boxShadow?.isNotEmpty ?? false);
    expect(shadows, isEmpty);
  });

  testWidgets('home_recent_rows_show_a_status_dot', (tester) async {
    // Wide enough that the test font's square glyphs keep the row on one
    // line, as Inter keeps it on a phone.
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(tester, home: const HomeScreen());
    await tester.scrollUntilVisible(
      find.byType(AnalysisTile).first,
      200,
      scrollable: find.byType(Scrollable).first,
    );

    final row = find.byType(AnalysisTile).first;
    expect(
      find.descendant(of: row, matching: find.byType(StatusPill)),
      findsNothing,
    );
    final sent = find.descendant(of: row, matching: find.text('Enviada'));
    expect(sent, findsOneWidget);
    expect(tester.widget<Text>(sent).style?.color, AppPalette.light.statusSent);
    expect(
      find.descendant(of: row, matching: find.byKey(const Key('status-dot'))),
      findsOneWidget,
    );
    // Rows every 64 dp, the rule included (PNG 08, SPEC 0210).
    expect(tester.getSize(row).height, 63);
    expect(
      tester.getSize(
        find.descendant(
          of: row,
          matching: find.byKey(const Key('analysis-thumbnail')),
        ),
      ),
      const Size(40, 40),
    );
  });

  testWidgets('history_app_bar_offers_search_and_filters', (tester) async {
    _phone(tester);
    await _pump(tester, home: const HistoryScreen());

    expect(find.byTooltip('Buscar'), findsOneWidget);
    expect(find.byTooltip('Filtros'), findsOneWidget);
    expect(find.byTooltip('Nova captura'), findsNothing);
    expect(find.byTooltip('Selecionar registros'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Todas'), findsNothing);

    await tester.tap(find.byTooltip('Buscar'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Todas'), findsNothing);

    await tester.tap(find.byTooltip('Filtros'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Todas'), findsOneWidget);
  });

  testWidgets('history_selection_has_a_semantics_action', (tester) async {
    _phone(tester);
    final semantics = tester.ensureSemantics();
    await _pump(tester, home: const HistoryScreen());

    final node = tester.getSemantics(find.byType(AnalysisTile).first);
    final action = CustomSemanticsAction.getIdentifier(
      const CustomSemanticsAction(label: 'Selecionar'),
    );
    expect(node.getSemanticsData().customSemanticsActionIds, contains(action));
    tester.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.customAction,
      action,
    );
    await tester.pump();
    expect(find.text('1 selecionado'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('segmented_control_is_40_dp_with_a_48_dp_target', (tester) async {
    _phone(tester);
    await _pump(tester, home: const HistoryScreen());

    final control = find.byType(SegmentedControl<bool>);
    expect(
      tester
          .getSize(
            find.descendant(
              of: control,
              matching: find.byKey(const Key('segmented-pill')),
            ),
          )
          .height,
      40,
    );
    final segment = find.descendant(
      of: control,
      matching: find.byKey(const Key('segment-0')),
    );
    expect(tester.getSize(segment).height, greaterThanOrEqualTo(48));
  });

  testWidgets('history_summary_is_one_strip', (tester) async {
    _phone(tester);
    await _pump(tester, home: const HistoryScreen());

    final strip = find.byKey(const Key('history-summary'));
    expect(strip, findsOneWidget);
    expect(
      find.descendant(of: strip, matching: find.byType(StatCell)),
      findsNothing,
    );
    expect(
      find.descendant(of: strip, matching: find.text('2')),
      findsNWidgets(2),
    );
    for (final text in ['análises', 'nesta semana', '0/12', 'classes']) {
      expect(
        find.descendant(of: strip, matching: find.text(text)),
        findsOneWidget,
      );
    }
  });

  testWidgets('history_rows_match_the_mock', (tester) async {
    // Wider than the phone: the test font's square glyphs would otherwise
    // need the room a pending row's pill leaves Inter, and stack it.
    tester.view.physicalSize = const Size(600, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(tester, home: const HistoryScreen());

    final sent = find.byType(AnalysisTile).first;
    expect(tester.getSize(sent).height, 72);
    expect(
      tester.getSize(
        find.descendant(
          of: sent,
          matching: find.byKey(const Key('analysis-thumbnail')),
        ),
      ),
      const Size(56, 56),
    );
    expect(
      find.descendant(
        of: sent,
        matching: find.byIcon(LucideIcons.chevronRight),
      ),
      findsOneWidget,
    );

    final pending = find.byType(AnalysisTile).at(1);
    final pill = find.descendant(
      of: pending,
      matching: find.byType(StatusPill),
    );
    expect(pill, findsOneWidget);
    final title = find.descendant(of: pending, matching: find.text('Argilosa'));
    expect(
      (tester.getCenter(pill).dy - tester.getCenter(title).dy).abs(),
      lessThan(16),
    );
    expect(
      tester.getTopRight(pill).dx,
      greaterThan(tester.getTopRight(title).dx),
    );
  });

  // SPEC 0205: the Dicas tab has its app bar, and back selects Início.
  testWidgets('tips_tab_has_an_app_bar', (tester) async {
    _phone(tester);
    final container = await _pump(tester, home: const MainScreen());
    container.read(mainTabIndexProvider.notifier).select(2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.widgetWithText(AppBar, 'Dicas de manejo'), findsOneWidget);
    await tester.tap(find.byTooltip('Voltar'));
    await tester.pump();
    expect(container.read(mainTabIndexProvider), 0);
  });

  // SPEC 0209: the Dicas tab's app bar ends in a filter.
  testWidgets('tips_tab_offers_a_filter', (tester) async {
    _phone(tester);
    final container = await _pump(tester, home: const MainScreen());
    container.read(mainTabIndexProvider.notifier).select(2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final filter = find.descendant(
      of: find.byType(AppBar),
      matching: find.byIcon(LucideIcons.slidersHorizontal),
    );
    expect(filter, findsOneWidget);
    await tester.tap(find.byTooltip('Filtrar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Filtrar dicas'), findsOneWidget);
  });

  // SPEC 0210: the page titles, and the empty history of PNG 17.
  testWidgets('page_titles_are_29_sp', (tester) async {
    _phone(tester);
    await _pump(tester, home: const HomeScreen());
    expect(tester.widget<Text>(find.text('Início')).style?.fontSize, 29);
  });

  testWidgets('empty_history_matches_the_mock', (tester) async {
    _phone(tester);
    final container = await _pump(tester, records: const []);
    container.read(mainTabIndexProvider.notifier).select(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final title = find.text('Nenhuma análise ainda');
    expect(tester.widget<Text>(title).style?.fontSize, 18);
    expect(
      find.ancestor(
        of: find.byIcon(LucideIcons.camera),
        matching: find.widgetWithText(ElevatedButton, 'Fazer primeira análise'),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.inventory_2_outlined), findsNothing);
  });
}
