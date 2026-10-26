import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/features/capture/widgets/texture_triangle.dart';
import 'package:visiosoil_app/core/features/details/details_screen.dart';
import 'package:visiosoil_app/core/features/details/management_tips_section.dart';
import 'package:visiosoil_app/core/features/details/widgets/info_section.dart';
import 'package:visiosoil_app/core/services/classification_report.dart';
import 'package:visiosoil_app/core/services/connectivity_service.dart';
import 'package:visiosoil_app/core/services/research/research_service.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';
import 'package:visiosoil_app/core/widgets/confidence_bar.dart';
import 'package:visiosoil_app/core/widgets/segmented_control.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/connectivity_provider.dart';
import 'package:visiosoil_app/providers/management_tips_repository_provider.dart';
import 'package:visiosoil_app/providers/research_service_provider.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';
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
    of: find.byType(SegmentedControl<ResultTab>),
    matching: find.text(label),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('result_header_shows_class_and_confidence', (tester) async {
    await _pump(tester, _classified());

    expect(find.text('Resultado'), findsOneWidget);
    expect(find.text('22/10/2026 · 10:42'), findsOneWidget);
    expect(find.text('Classe textural'), findsOneWidget);
    expect(find.text('Argilosa'), findsOneWidget);
    expect(find.text('Confiança alta · 82%'), findsOneWidget);
    expect(find.byType(ConfidenceBar), findsOneWidget);
  });

  testWidgets('result_tabs_switch_content', (tester) async {
    await _pump(tester, _classified());

    expect(find.byType(SegmentedControl<ResultTab>), findsOneWidget);
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
    expect(find.bySemanticsLabel('Salvo'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('overview_shows_the_triangle_card', (tester) async {
    await _pump(tester, _classified());

    expect(find.text('No triângulo textural'), findsOneWidget);
    final triangle = tester.widget<TextureTriangle>(find.byType(TextureTriangle));
    expect(triangle.highlightClass, 'Argilosa');
    expect(triangle.mode, TextureTriangleMode.static);
    expect(find.text('A região Argilosa está destacada.'), findsOneWidget);
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
      expect(find.textContaining('Talhão 3 · A1'), findsOneWidget);
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
      final control = tester.widget<SegmentedControl<ResultTab>>(
        find.byType(SegmentedControl<ResultTab>),
      );
      expect(control.value, ResultTab.management);
    });

    testWidgets('Corrigir opens the labels dialog', (tester) async {
      await _pump(tester, _classified());

      await tester.tap(find.widgetWithText(OutlinedButton, 'Corrigir'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Talhão'), findsOneWidget);
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
        expect(find.byType(SegmentedControl<ResultTab>), findsNothing);
        expect(find.text('Corrigir'), findsNothing);
        expect(find.text('Dicas de manejo'), findsNothing);
        expect(find.text('Compartilhar'), findsOneWidget);
        expect(find.text('Excluir registro'), findsOneWidget);
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
}
