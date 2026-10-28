import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/features/capture/widgets/texture_triangle.dart';
import 'package:visiosoil_app/core/features/details/details_screen.dart';
import 'package:visiosoil_app/core/features/details/management_tips_section.dart';
import 'package:visiosoil_app/core/features/details/widgets/info_section.dart';
import 'package:visiosoil_app/core/features/details/widgets/result_overview.dart';
import 'package:visiosoil_app/core/services/classification_report.dart';
import 'package:visiosoil_app/core/services/connectivity_service.dart';
import 'package:visiosoil_app/core/services/research/research_service.dart';
import 'package:visiosoil_app/core/constants/app_strings.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';
import 'package:visiosoil_app/core/widgets/confidence_bar.dart';
import 'package:visiosoil_app/core/widgets/visio_app_bar.dart';
import 'package:visiosoil_app/core/widgets/visio_icon_button.dart';
import 'package:visiosoil_app/core/features/details/widgets/result_tab_bar.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/connectivity_provider.dart';
import 'package:visiosoil_app/providers/management_tips_repository_provider.dart';
import 'package:visiosoil_app/providers/research_service_provider.dart';
import 'package:visiosoil_app/providers/just_saved_record_provider.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';
import '../../support/fake_soil_record_repository.dart';
import '../../support/guidelines.dart';
import '../../support/management_tips_fakes.dart';

// The saved record laid out as the v11 result screen (SPEC 0194).

SoilRecord _classified({
  String textureClass = 'Argilosa',
  double score = 0.82,
  String? address = 'Rio Verde, GO',
  double? latitude = -17.79,
  double? longitude = -50.92,
  String? fieldName,
  String? sampleLabel,
}) =>
    SoilRecord(
      id: 1,
      uuid: 'rec-1',
      imagePath: 'x.png',
      latitude: latitude,
      longitude: longitude,
      address: address,
      timestamp: '2026-10-22T10:42:00',
      textureClass: textureClass,
      confidenceScore: score,
      fieldName: fieldName,
      sampleLabel: sampleLabel,
    );

SoilRecord _unclassified(ClassificationFailureCause? cause) => SoilRecord(
      id: 1,
      uuid: 'rec-1',
      imagePath: 'x.png',
      timestamp: '2026-10-22T10:42:00',
      classificationFailure: cause,
    );

List<Override> _overrides(SoilRecord record) => [
      soilRecordByIdProvider.overrideWith((ref, id) async => record),
      managementTipsRepositoryProvider
          .overrideWithValue(FakeManagementTipsRepository()),
      researchServiceProvider.overrideWithValue(
        FakeResearchService(
          (_) async =>
              const ResearchFailure(ResearchFailureKind.upstreamUnavailable),
        ),
      ),
      connectivityServiceProvider
          .overrideWithValue(FakeConnectivityService(ConnectivityStatus.online)),
    ];

Future<void> _pump(
  WidgetTester tester,
  SoilRecord record, {
  ThemeData? theme,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(
    overrides: _overrides(record),
    child: MaterialApp(theme: theme, home: const DetailsScreen(recordId: 1)),
  ));
  await tester.pumpAndSettle();
}

Future<void> _selectTab(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(
    of: find.byType(ResultTabBar<ResultTab>),
    matching: find.text(label),
  ));
  await tester.pumpAndSettle();
}

// The page's own vertical scroll; the tab bar scrolls sideways.
final _page = find
    .byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    )
    .first;

void main() {
  testWidgets('result_header_shows_class_and_confidence', (tester) async {
    await _pump(tester, _classified());

    expect(find.text('Resultado'), findsOneWidget);
    expect(find.text('22/10/2026 · 10:42'), findsOneWidget);
    expect(find.text('Classe textural (triângulo USDA)'), findsOneWidget);
    expect(find.text('Argilosa'), findsOneWidget);
    expect(find.text('Confiança alta'), findsOneWidget);
    expect(find.text('82%'), findsOneWidget);
    expect(find.byType(SegmentedConfidenceBar), findsOneWidget);
  });

  // PNG 14 as SPEC 0202 measures it.
  testWidgets('header_matches_the_mock', (tester) async {
    await _pump(tester, _classified());

    // No colour dot beside the class, and no icon in the badge.
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).shape == BoxShape.circle &&
            w.constraints?.maxWidth == 14,
      ),
      findsNothing,
    );
    final badge = find.ancestor(
      of: find.text('Confiança alta'),
      matching: find.byType(Container),
    );
    expect(
      find.descendant(of: badge.first, matching: find.byType(Icon)),
      findsNothing,
    );
    // Five segments, four filled at 0.82, and the percent right of the bar.
    final palette = AppPalette.light;
    final segments = [
      for (var i = 0; i < 5; i++)
        tester.widget<Container>(find.byKey(ValueKey('confidence-segment-$i'))),
    ];
    final filled = segments
        .where((c) => (c.decoration! as BoxDecoration).color == palette.primary)
        .length;
    expect(filled, 4);
    expect(
      tester.getTopLeft(find.text('82%')).dx,
      greaterThan(
        tester.getTopRight(find.byKey(const ValueKey('confidence-segment-4'))).dx,
      ),
    );
  });

  testWidgets('tabs_are_underlined', (tester) async {
    await _pump(tester, _classified());
    Offset indicator() =>
        tester.getCenter(find.byKey(const ValueKey('result-tab-indicator')));
    final overview = tester.getCenter(find.text('Visão geral'));
    expect(indicator().dx, closeTo(overview.dx, 1));
    expect(find.byKey(const ValueKey('result-tab-indicator')), findsOneWidget);

    await _selectTab(tester, 'Manejo');
    expect(
      indicator().dx,
      closeTo(tester.getCenter(find.text('Manejo')).dx, 1),
    );
    // The labels share one row.
    expect(
      tester.getCenter(find.text('Visão geral')).dy,
      tester.getCenter(find.text('Detalhes')).dy,
    );
  });

  // The selected tab is announced as such (review of #436).
  testWidgets('tabs_announce_their_selection', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, _classified());
    void expectSelected(String label, bool selected) => expect(
      tester.getSemantics(find.text(label)),
      isSemantics(isSelected: selected, isButton: true),
      reason: label,
    );

    expectSelected('Visão geral', true);
    expectSelected('Manejo', false);
    await _selectTab(tester, 'Manejo');
    expectSelected('Visão geral', false);
    expectSelected('Manejo', true);
    semantics.dispose();
  });

  // Modo Sol's targets are 56 dp (review of #436).
  testWidgets('sun_tabs_are_56_dp', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: _overrides(_classified()),
      child: MaterialApp(
        theme: AppTheme.sun,
        home: const DetailsScreen(recordId: 1),
      ),
    ));
    await tester.pumpAndSettle();

    final tab = find.ancestor(
      of: find.text('Manejo'),
      matching: find.byType(InkWell),
    );
    expect(tester.getSize(tab.first).height, greaterThanOrEqualTo(56));
  });

  // At 360 dp or less the footer stacks rather than shrinking its labels
  // (review of #436).
  for (final width in [320.0, 360.0]) {
    testWidgets('footer_stacks_at_${width.toInt()}_dp', (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: _overrides(_classified()),
        child: MaterialApp(
          theme: AppTheme.light,
          home: const DetailsScreen(recordId: 1),
        ),
      ));
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(find.text('Dicas de manejo')).dy,
        greaterThan(tester.getBottomLeft(find.text('Corrigir')).dy),
      );
    });
  }

  testWidgets('footer_fits_one_line', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: _overrides(_classified()),
      child: MaterialApp(
        theme: AppTheme.light,
        home: const DetailsScreen(recordId: 1),
      ),
    ));
    await tester.pumpAndSettle();

    // One line each, scaled down rather than wrapped, side by side.
    for (final label in ['Corrigir', 'Dicas de manejo']) {
      expect(tester.widget<Text>(find.text(label)).maxLines, 1, reason: label);
    }
    final correct = tester.getRect(find.text('Corrigir'));
    final tips = tester.getRect(find.text('Dicas de manejo'));
    expect(correct.center.dy, closeTo(tips.center.dy, 1));
    expect(tips.left, greaterThan(correct.right));
  });

  testWidgets('app_bar_shares', (tester) async {
    await _pump(tester, _classified());
    expect(find.byTooltip('Compartilhar'), findsOneWidget);
    expect(find.byTooltip('Nova captura'), findsNothing);
  });

  testWidgets('lattice_only_outside_sun', (tester) async {
    await _pump(tester, _classified());
    expect(find.byKey(const ValueKey('result-lattice')), findsOneWidget);
    // A fresh tree: the themes' button styles cannot be interpolated.
    await tester.pumpWidget(const SizedBox());
    await _pump(tester, _classified(), theme: AppTheme.sun);
    expect(find.byKey(const ValueKey('result-lattice')), findsNothing);
  });

  testWidgets('result_tabs_switch_content', (tester) async {
    await _pump(tester, _classified());

    expect(find.byType(ResultTabBar<ResultTab>), findsOneWidget);
    expect(
      find.text('O modelo estima a classe textural pela foto. A confiança '
          'indica o quanto ele está seguro dessa classe.'),
      findsOneWidget,
    );
    expect(find.text('Sobre a classe'), findsOneWidget);
    expect(find.text('Amostra'), findsOneWidget);
    expect(
      find.text('Estimativa por imagem. Para laudo, confirme com análise '
          'granulométrica em laboratório.'),
      findsOneWidget,
    );
    expect(find.byType(ManagementTipsSection), findsNothing);
    expect(find.byType(InfoSection), findsNothing);

    await _selectTab(tester, 'Manejo');
    expect(find.byType(ManagementTipsSection), findsOneWidget);
    expect(find.text('Sobre a classe'), findsNothing);

    await _selectTab(tester, 'Detalhes');
    expect(find.byType(InfoSection), findsOneWidget);
    expect(find.bySemanticsLabel('Ampliar foto'), findsOneWidget);
    expect(find.text('Compartilhar'), findsOneWidget);
    expect(find.text('Excluir registro'), findsOneWidget);
    expect(find.byType(ManagementTipsSection), findsNothing);
  });

  // A tab change keeps each tab's state, so tips generating in Manejo still
  // land when the user returns to it (Codex review on #427).
  testWidgets('tabs_keep_their_state_across_changes', (tester) async {
    await _pump(tester, _classified());
    await _selectTab(tester, 'Manejo');
    final tips = tester.state(find.byType(ManagementTipsSection));

    await _selectTab(tester, 'Detalhes');
    expect(find.byType(ManagementTipsSection), findsNothing);
    await _selectTab(tester, 'Manejo');

    expect(tester.state(find.byType(ManagementTipsSection)), same(tips));
  });

  testWidgets('details_shows_a_filled_saved_bookmark', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, _classified());

    expect(find.byIcon(Icons.bookmark), findsOneWidget);
    // Filled, and a way to remove the record from the saved ones
    // (SPEC 0197).
    expect(find.byTooltip('Remover dos salvos'), findsOneWidget);
    semantics.dispose();
  });

  // Opening a saved record announces nothing on its own (SPEC 0196).
  testWidgets('a_saved_result_is_not_a_live_region', (tester) async {
    await _pump(tester, _classified());

    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.liveRegion == true,
      ),
      findsNothing,
    );
  });

  testWidgets('overview_shows_the_triangle_card', (tester) async {
    await _pump(tester, _classified());

    expect(find.text('No triângulo textural'), findsOneWidget);
    final triangle = tester.widget<TextureTriangle>(find.byType(TextureTriangle));
    expect(triangle.highlightClass, 'Argilosa');
    expect(triangle.mode, TextureTriangleMode.static);
    expect(find.text('A região Argilosa está destacada.'), findsOneWidget);
  });

  group('footer_moves_inline_on_a_short_or_large_text_screen', () {
    Finder inScroll(String text) => find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.text(text),
        );

    testWidgets('a tall screen at 1.0x keeps it fixed', (tester) async {
      await _pump(tester, _classified());
      expect(find.text('Corrigir'), findsOneWidget);
      expect(inScroll('Corrigir'), findsNothing);
    });

    testWidgets('1.3x text moves it into the scroll view', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pump(tester, _classified());
      await tester.scrollUntilVisible(find.text('Corrigir'), 300, scrollable: _page);
      expect(inScroll('Corrigir'), findsOneWidget);
    });

    testWidgets('a 568 dp tall screen moves it into the scroll view',
        (tester) async {
      tester.view.physicalSize = const Size(360, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: _overrides(_classified()),
        child: const MaterialApp(home: DetailsScreen(recordId: 1)),
      ));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Corrigir'), 300, scrollable: _page);
      expect(inScroll('Corrigir'), findsOneWidget);
    });
  });

  group('saved_bookmark_pops_after_a_capture_save', () {
    Future<ProviderContainer> pumpWithJustSaved(
      WidgetTester tester,
      int? justSaved,
    ) async {
      await tester.binding.setSurfaceSize(const Size(420, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final container = ProviderContainer(overrides: _overrides(_classified()));
      addTearDown(container.dispose);
      if (justSaved != null) {
        container.read(justSavedRecordProvider.notifier).mark(justSaved);
      }
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DetailsScreen(recordId: 1)),
      ));
      return container;
    }

    double scale(WidgetTester tester) => tester
        .widget<ScaleTransition>(find.byKey(const ValueKey('saved-bookmark')))
        .scale
        .value;

    testWidgets('the saved record pops', (tester) async {
      final container = await pumpWithJustSaved(tester, 1);
      await tester.pump();
      await tester.pump();
      var peak = 1.0;
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        if (scale(tester) > peak) peak = scale(tester);
      }
      expect(peak, greaterThan(1.2));
      await tester.pumpAndSettle();
      expect(scale(tester), 1.0);
      expect(container.read(justSavedRecordProvider), isNull);
    });

    testWidgets('another record does not pop', (tester) async {
      await pumpWithJustSaved(tester, 7);
      await tester.pumpAndSettle();
      expect(scale(tester), 1.0);
    });
  });

  testWidgets('filled_bookmark_removes_from_saved', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = FakeSoilRecordRepository();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ..._overrides(_classified()),
        soilRecordRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/details',
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const Scaffold(body: Text('HOME_STUB')),
            ),
            GoRoute(
              path: '/details',
              builder: (_, _) => const DetailsScreen(recordId: 1),
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Remover dos salvos'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Excluir'));
    await tester.pump();

    expect(repository.deleteByIdCalls, [1]);
    await tester.pumpAndSettle();
    expect(find.text('HOME_STUB'), findsOneWidget);
  });

  testWidgets('photo_flies_from_the_details_tab', (tester) async {
    await _pump(tester, _classified());
    await _selectTab(tester, 'Detalhes');
    expect(
      find.byWidgetPredicate(
        (w) => w is Hero && w.tag == recordPhotoHeroTag(1),
      ),
      findsOneWidget,
    );
  });

  group('about_class_copy_per_model_class', () {
    for (final (textureClass, fragment) in [
      ('Arenosa', 'menos de 15% de argila'),
      ('Media', 'menos de 35% de argila'),
      ('Argilosa', 'entre 35% e 60% de argila'),
      ('Muito Argilosa', 'mais de 60% de argila'),
    ]) {
      testWidgets(textureClass, (tester) async {
        await _pump(tester, _classified(textureClass: textureClass));

        expect(find.text('Sobre a classe'), findsOneWidget);
        expect(find.text('Referência geral'), findsOneWidget);
        expect(find.textContaining(fragment), findsOneWidget);
        expect(
          find.text('Faixa típica da classe, não medição desta amostra.'),
          findsOneWidget,
        );
      });
    }

    testWidgets('an unknown class has no card', (tester) async {
      await _pump(tester, _classified(textureClass: 'Siltosa'));

      expect(find.text('Sobre a classe'), findsNothing);
      expect(find.text('Amostra'), findsOneWidget);
    });
  });

  group('sample_card_joins_location_and_labels', () {
    testWidgets('a located, labelled record', (tester) async {
      await _pump(
        tester,
        _classified(fieldName: 'Talhão 3', sampleLabel: 'A1'),
      );

      expect(find.textContaining('Rio Verde, GO'), findsOneWidget);
      expect(find.textContaining('-17.790000, -50.920000'), findsOneWidget);
      // SPEC 0220: the sample shows alone; the field label no longer shows.
      expect(find.textContaining('A1'), findsOneWidget);
      expect(find.textContaining('Talhão 3'), findsNothing);
    });

    testWidgets('a record with no location', (tester) async {
      await _pump(
        tester,
        _classified(address: null, latitude: null, longitude: null),
      );

      expect(find.text('Sem localização registrada'), findsOneWidget);
    });
  });

  group('tips_footer_selects_manejo', () {
    testWidgets('Dicas de manejo selects the tab', (tester) async {
      await _pump(tester, _classified());

      await tester.tap(find.widgetWithText(ElevatedButton, 'Dicas de manejo'));
      await tester.pumpAndSettle();

      expect(find.byType(ManagementTipsSection), findsOneWidget);
      final control = tester.widget<ResultTabBar<ResultTab>>(
        find.byType(ResultTabBar<ResultTab>),
      );
      expect(control.value, ResultTab.management);
    });

    testWidgets('Corrigir opens the correction dialog', (tester) async {
      await _pump(tester, _classified());

      await tester.tap(find.widgetWithText(OutlinedButton, 'Corrigir'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Corrigir classificação'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Talhão'), findsNothing);
    });

    testWidgets('the footer stacks from a 1.3x text scale', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pump(tester, _classified());

      final correct =
          tester.getRect(find.widgetWithText(OutlinedButton, 'Corrigir'));
      final tips = tester
          .getRect(find.widgetWithText(ElevatedButton, 'Dicas de manejo'));
      expect(tips.top, greaterThanOrEqualTo(correct.bottom));
    });
  });

  group('unclassified_record_shows_error_block', () {
    for (final (name, cause, message) in [
      (
        'with a cause',
        ClassificationFailureCause.sheetCropped,
        'Folha cortada no quadro · tire outra foto',
      ),
      (
        'without a cause',
        null,
        'Não foi possível analisar esta foto. Fotografe a amostra de novo, '
            'seguindo as dicas de captura.',
      ),
    ]) {
      testWidgets(name, (tester) async {
        await _pump(tester, _unclassified(cause));

        expect(find.text('Não deu para classificar'), findsOneWidget);
        expect(find.text(message), findsOneWidget);
        expect(find.text('Fotografar de novo'), findsOneWidget);
        expect(find.text('Ver dicas de captura'), findsOneWidget);
        expect(find.byType(ResultTabBar<ResultTab>), findsNothing);
        expect(find.text('Corrigir'), findsNothing);
        expect(find.text('Dicas de manejo'), findsNothing);
        // Only the block (PNG 15, SPEC 0202): no photograph, and the record
        // is shared from the app bar.
        expect(find.bySemanticsLabel('Ampliar foto'), findsNothing);
        expect(find.byTooltip('Compartilhar'), findsOneWidget);
        expect(find.text('Excluir registro'), findsNothing);
      });
    }

    for (final (action, route) in [
      ('Fotografar de novo', '/capture'),
      ('Ver dicas de captura', '/capture-guide'),
    ]) {
      testWidgets('$action opens $route', (tester) async {
        await tester.binding.setSurfaceSize(const Size(420, 1600));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final router = GoRouter(
          initialLocation: '/details',
          routes: [
            GoRoute(
              path: '/details',
              builder: (_, _) => const DetailsScreen(recordId: 1),
            ),
            for (final path in ['/capture', '/capture-guide'])
              GoRoute(
                path: path,
                builder: (_, _) => Scaffold(body: Text('STUB $path')),
              ),
          ],
        );
        await tester.pumpWidget(ProviderScope(
          overrides: _overrides(
            _unclassified(ClassificationFailureCause.sheetNotFound),
          ),
          child: MaterialApp.router(routerConfig: router),
        ));
        await tester.pumpAndSettle();

        await tester.tap(find.text(action));
        await tester.pumpAndSettle();

        expect(find.text('STUB $route'), findsOneWidget);
      });
    }
  });

  testWidgets('entrance_respects_reduced_motion', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: _overrides(_classified()),
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const DetailsScreen(recordId: 1),
      ),
    ));
    // The record future resolves, then the entrance runs.
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    // One more frame completes what ends at 150 ms.
    await tester.pump(const Duration(milliseconds: 16));

    // Nothing left to draw: every entrance animation has ended.
    expect(tester.binding.hasScheduledFrame, isFalse);
    final opacities = tester
        .widgetList<FadeTransition>(find.byKey(const ValueKey('result-rise')))
        .map((fade) => fade.opacity.value);
    expect(opacities, isNotEmpty);
    expect(opacities, everyElement(1.0));
  });

  // A 320 dp phone stacks the side-by-side pieces (redesign v11 §10); 380 dp
  // keeps them side by side up to the largest scale before 1.3x stacks them.
  for (final (name, theme) in [('light', AppTheme.light), ('Sun', AppTheme.sun)]) {
    for (final (width, scale) in [(320.0, 1.0), (320.0, 1.29), (380.0, 1.29)]) {
      testWidgets('result_fits_a_320dp_phone in $name at $width dp, $scale',
          (tester) async {
        tester.view.physicalSize = Size(width, 640);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(ProviderScope(
          overrides: _overrides(
            _classified(textureClass: 'Muito Argilosa', score: 0.6),
          ),
          child: MaterialApp(
            theme: theme,
            home: const DetailsScreen(recordId: 1),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'Visão geral');

        for (final tab in ['Manejo', 'Detalhes']) {
          await tester.ensureVisible(find.text(tab));
          await tester.pumpAndSettle();
          await tester.tap(find.text(tab));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: tab);
        }
      });
    }
  }

  // The result, its Manejo tab and its error block each pass the four
  // guidelines, and Sun's 56 dp targets (SPEC 0133, SPEC 0182).
  for (final (name, theme) in [...appThemes, ('Sun', AppTheme.sun)]) {
    testWidgets('the result meets the guidelines in $name', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, _classified(), theme: theme);
      await expectMeetsGuidelines(tester);
      await _selectTab(tester, 'Manejo');
      await expectMeetsGuidelines(tester);

      await _pump(
        tester,
        _unclassified(ClassificationFailureCause.sheetNotFound),
        theme: theme,
      );
      await expectMeetsGuidelines(tester);
      if (name == 'Sun') {
        await expectLater(tester, meetsGuideline(sunTapTargetGuideline));
      }
      semantics.dispose();
    });
  }

  testWidgets('a classified record without a score shows no confidence',
      (tester) async {
    await _pump(
      tester,
      SoilRecord(
        id: 1,
        uuid: 'rec-1',
        imagePath: 'x.png',
        timestamp: '2026-10-22T10:42:00',
        textureClass: 'Argilosa',
      ),
    );

    expect(find.text('Argilosa'), findsOneWidget);
    expect(find.byType(ConfidenceBar), findsNothing);
    expect(find.textContaining('não está seguro'), findsNothing);
  });

  // SPEC 0210: the confidence row and the tabs as PNG 14 measures them.
  testWidgets('confidence_row_matches_the_mock', (tester) async {
    await _pump(tester, _classified(), theme: AppTheme.light);

    final badge = find.text(AppStrings.confidenceHigh);
    final row = find.byType(SegmentedConfidenceBar);
    expect(
      tester.getSize(find.ancestor(of: badge, matching: find.byType(Container)).first).width,
      lessThan(420 / 2),
    );
    final empty = tester.widget<Container>(
      find.byKey(const ValueKey('confidence-segment-4')),
    );
    expect(
      (empty.decoration! as BoxDecoration).color,
      AppPalette.light.divider,
    );
    expect(row, findsOneWidget);
    expect(tester.widget<Text>(find.text('82%')).style?.fontSize, 14);
  });

  testWidgets('tab_indicator_sits_on_the_rule', (tester) async {
    await _pump(tester, _classified(), theme: AppTheme.light);

    expect(
      tester.getBottomLeft(find.byKey(const ValueKey('result-tab-indicator'))).dy,
      tester.getBottomLeft(find.byKey(const ValueKey('result-tab-rule'))).dy,
    );
  });

  // SPEC 0212: the bar's actions, the overview's triangle, and the result in
  // Modo Sol as PNG 26 measures it.
  testWidgets('bar_actions_are_4_dp_apart', (tester) async {
    await _pump(tester, _classified(), theme: AppTheme.light);

    // Two 48 dp targets 4 dp apart: their centres 52 dp apart.
    expect(
      tester.getCenter(find.byTooltip('Compartilhar')).dx -
          tester.getCenter(find.byTooltip(AppStrings.resultRemoveSaved)).dx,
      52,
    );
  });

  testWidgets('sun_leading_slot_is_64_dp', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.sun,
      home: Scaffold(
        appBar: VisioAppBar(
          title: 'Resultado',
          leading: VisioIconButton(
            label: 'Voltar',
            icon: Icons.arrow_back,
            onPressed: () {},
          ),
        ),
      ),
    ));

    expect(tester.getCenter(find.byTooltip('Voltar')).dx, 32);
    expect(tester.getTopLeft(find.text('Resultado')).dx, 68);
  });

  testWidgets('sun_header_matches_the_mock', (tester) async {
    await _pump(tester, _classified(), theme: AppTheme.sun);
    final sun = AppPalette.sun;

    final date = tester.widget<Text>(find.text('22/10/2026 · 10:42')).style!;
    expect(date.fontSize, 12.5);
    expect(date.fontWeight, FontWeight.w500);
    expect(
      tester.widget<Text>(find.text(AppStrings.confidenceHigh)).style?.color,
      sun.onSurface,
    );
    final first = find.byKey(const ValueKey('confidence-segment-0'));
    final second = find.byKey(const ValueKey('confidence-segment-1'));
    expect(tester.getSize(first).height, 10);
    expect(tester.getTopLeft(second).dx - tester.getTopRight(first).dx, 2);
    final empty = tester
        .widget<Container>(find.byKey(const ValueKey('confidence-segment-4')))
        .decoration! as BoxDecoration;
    expect(empty.color, sun.surface);
    expect(empty.border!.top.color, sun.onSurface);
    expect(empty.border!.top.width, 1);
    expect(tester.widget<Text>(find.text('82%')).style?.fontSize, 15);
  });

  testWidgets('sun_tabs_keep_their_place', (tester) async {
    await _pump(tester, _classified(), theme: AppTheme.sun);

    // PNG 26: the rule's bottom 74.5 dp under the segments' bottom.
    final rule = find.byKey(const ValueKey('result-tab-rule'));
    expect(
      tester.getBottomLeft(rule).dy -
          tester
              .getBottomLeft(find.byKey(const ValueKey('confidence-segment-0')))
              .dy,
      closeTo(74.5, 1),
    );
    final label = find.descendant(
      of: find.byType(ResultTabBar<ResultTab>),
      matching: find.text('Visão geral'),
    );
    final style = tester.widget<Text>(label).style!;
    expect(style.fontSize, 15.5);
    expect(style.color, AppPalette.sun.onSurface);
    expect(
      tester.getBottomLeft(find.byKey(const ValueKey('result-tab-indicator'))).dy,
      tester.getBottomLeft(rule).dy,
    );
  });

  testWidgets('overview_triangle_sits_3_5_dp_higher', (tester) async {
    await _pump(tester, _classified(), theme: AppTheme.light);

    final heading = find.text(AppStrings.resultTriangleTitle);
    final triangle = find.descendant(
      of: find.byType(ResultOverview),
      matching: find.byType(TextureTriangle),
    );
    expect(
      tester.getTopLeft(triangle).dy - tester.getBottomLeft(heading).dy,
      12 - 3.5,
    );
  });
}
