import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/features/details/details_screen.dart';
import 'package:visiosoil_app/core/services/connectivity_service.dart';
import 'package:visiosoil_app/core/services/research/research_service.dart';
import 'package:visiosoil_app/core/services/share_service.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';
import 'package:visiosoil_app/core/widgets/error_state.dart';
import 'package:visiosoil_app/core/widgets/visio_app_bar.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/connectivity_provider.dart';
import 'package:visiosoil_app/providers/management_tips_repository_provider.dart';
import 'package:visiosoil_app/providers/research_service_provider.dart';
import 'package:visiosoil_app/providers/share_service_provider.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';
import '../../support/fake_soil_record_repository.dart';
import '../../support/guidelines.dart';
import '../../support/management_tips_fakes.dart';
import '../../support/large_text.dart';

/// Records the include-location choice the share flow forwards to the service.
class _RecordingShareService extends ShareService {
  bool? calledIncludeLocation;

  @override
  Future<void> shareRecord(
    SoilRecord record, {
    bool includeLocation = false,
  }) async {
    calledIncludeLocation = includeLocation;
  }
}

SoilRecord _locatedRecord() => SoilRecord(
      id: 1,
      imagePath: 'x.png',
      latitude: -23.5,
      longitude: -46.6,
      address: 'São Paulo, SP',
      timestamp: '2026-06-26T12:00:00Z',
      textureClass: 'Argilosa',
      confidenceScore: 0.9,
    );

/// Applies label writes to the record details read, as the Drift repository
/// does, so a re-read shows them (SPEC 0149).
class _LabellingRepository extends FakeSoilRecordRepository {
  _LabellingRepository(this.current);

  SoilRecord current;

  @override
  Future<void> updateLabels(
    int id, {
    String? fieldName,
    String? sampleLabel,
  }) async {
    await super.updateLabels(
      id,
      fieldName: fieldName,
      sampleLabel: sampleLabel,
    );
    current =
        current.copyWith(fieldName: fieldName, sampleLabel: sampleLabel);
  }
}

SoilRecord _unlocatedRecord() => SoilRecord(
      id: 1,
      imagePath: 'x.png',
      timestamp: '2026-06-26T12:00:00Z',
      textureClass: 'Argilosa',
      confidenceScore: 0.9,
    );

Widget _detailsUnderTest({
  required ShareService share,
  required SoilRecord record,
  bool pushed = false,
  ThemeData? theme,
}) {
  return ProviderScope(
    overrides: [
      soilRecordByIdProvider.overrideWith((ref, id) async => record),
      shareServiceProvider.overrideWithValue(share),
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
    ],
    child: pushed
        ? MaterialApp(
            theme: theme,
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const DetailsScreen(recordId: 1),
                  ),
                ),
                child: const Text('open details'),
              ),
            ),
          )
        : MaterialApp(theme: theme, home: const DetailsScreen(recordId: 1)),
  );
}

void main() {
  testWidgets('tips section sits between the info section and the actions',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(ProviderScope(
      overrides: [
        soilRecordByIdProvider.overrideWith((ref, id) async => tipsRecord()),
        managementTipsRepositoryProvider
            .overrideWithValue(FakeManagementTipsRepository()),
        researchServiceProvider.overrideWithValue(
          FakeResearchService(
            (_) async => const ResearchFailure(ResearchFailureKind.upstreamUnavailable),
          ),
        ),
        connectivityServiceProvider
            .overrideWithValue(FakeConnectivityService(ConnectivityStatus.online)),
      ],
      child: const MaterialApp(home: DetailsScreen(recordId: 1)),
    ));
    await tester.pumpAndSettle();

    final infoDy = tester.getTopLeft(find.text('Localização')).dy;
    final tipsDy = tester.getTopLeft(find.text('Dicas de manejo')).dy;
    final actionsDy = tester.getTopLeft(find.text('Compartilhar')).dy;

    expect(infoDy < tipsDy, isTrue);
    expect(tipsDy < actionsDy, isTrue);
  });

  testWidgets('sharing a located record omits location by default',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final share = _RecordingShareService();

    await tester.pumpWidget(
      _detailsUnderTest(share: share, record: _locatedRecord()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Compartilhar'));
    await tester.pumpAndSettle();

    // The opt-in dialog appears; its default action shares without location.
    expect(find.text('Compartilhar sem localização'), findsOneWidget);
    await tester.tap(find.text('Compartilhar sem localização'));
    await tester.pumpAndSettle();

    expect(share.calledIncludeLocation, isFalse);
  });

  testWidgets('choosing to include location forwards the opt-in',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final share = _RecordingShareService();

    await tester.pumpWidget(
      _detailsUnderTest(share: share, record: _locatedRecord()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Compartilhar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Incluir localização'));
    await tester.pumpAndSettle();

    expect(share.calledIncludeLocation, isTrue);
  });

  testWidgets('a record with no location shares without a dialog',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final share = _RecordingShareService();

    await tester.pumpWidget(
      _detailsUnderTest(share: share, record: _unlocatedRecord()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Compartilhar'));
    await tester.pumpAndSettle();

    expect(find.text('Incluir localização?'), findsNothing);
    expect(share.calledIncludeLocation, isFalse);
  });

  testWidgets(
      'confirming delete removes the record, shows a snackbar, and returns home',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repository = FakeSoilRecordRepository();
    final router = GoRouter(
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
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        soilRecordByIdProvider.overrideWith((ref, id) async => _locatedRecord()),
        soilRecordRepositoryProvider.overrideWithValue(repository),
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
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    // Open the shared destructive dialog from the delete action, then confirm.
    await tester.tap(find.text('Excluir registro'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir'));
    await tester.pump(); // run the delete + snackbar before navigation settles

    expect(repository.deleteByIdCalls, [1]);
    expect(find.text('Registro excluído.'), findsOneWidget);

    await tester.pumpAndSettle();

    // The post-action navigates back to the home route.
    expect(find.text('HOME_STUB'), findsOneWidget);
  });

  testWidgets('cancelling delete keeps the record and does not navigate',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repository = FakeSoilRecordRepository();
    final router = GoRouter(
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
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        soilRecordByIdProvider.overrideWith((ref, id) async => _locatedRecord()),
        soilRecordRepositoryProvider.overrideWithValue(repository),
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
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Excluir registro'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(repository.deleteByIdCalls, isEmpty);
    expect(find.text('HOME_STUB'), findsNothing);
  });

  testWidgets('a load error shows a retry action, not the not-found view',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        soilRecordByIdProvider
            .overrideWith((ref, id) async => throw Exception('boom')),
      ],
      child: const MaterialApp(home: DetailsScreen(recordId: 1)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Tentar novamente'), findsOneWidget);
    expect(find.text('Registro não encontrado'), findsNothing);
  });

  testWidgets('a null record shows the not-found view with no retry',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        soilRecordByIdProvider.overrideWith((ref, id) async => null),
      ],
      child: const MaterialApp(home: DetailsScreen(recordId: 1)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Registro não encontrado'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsNothing);
  });

  // A missing record is the shared error state under the shared bar
  // (SPEC 0124).
  testWidgets('one_error_presentation: details not found', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        soilRecordByIdProvider.overrideWith((ref, id) async => null),
      ],
      child: const MaterialApp(home: DetailsScreen(recordId: 1)),
    ));
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(ErrorState, 'Registro não encontrado'),
      findsOneWidget,
    );
    expect(find.byType(VisioAppBar), findsOneWidget);
  });

  testWidgets('retry re-fetches and renders the record', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // A flag flipped before the retry tap, not a call counter: the provider's
    // creator can run more than once during the initial settle, so the failure
    // must depend on state we control, not on the invocation count.
    var fail = true;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        soilRecordByIdProvider.overrideWith((ref, id) async {
          if (fail) throw Exception('boom');
          return _locatedRecord();
        }),
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
      ],
      child: const MaterialApp(home: DetailsScreen(recordId: 1)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Tentar novamente'), findsOneWidget);

    fail = false;
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();

    expect(find.text('Tentar novamente'), findsNothing);
    expect(find.text('Compartilhar'), findsOneWidget);
  });

  // ADR 0017's protocol puts a white sheet at the top of every photograph, so
  // the header's controls cannot take the theme's text colour (SPEC 0107).
  testWidgets('the_details_header_reads_over_any_photo', (tester) async {
    tester.view.padding = const FakeViewPadding(top: 72);
    addTearDown(tester.view.resetPadding);
    final statusBar = 72 / tester.view.devicePixelRatio;

    for (final theme in [AppTheme.light, AppTheme.dark]) {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          soilRecordByIdProvider
              .overrideWith((ref, id) async => _unlocatedRecord()),
          managementTipsRepositoryProvider
              .overrideWithValue(FakeManagementTipsRepository()),
          researchServiceProvider.overrideWithValue(
            FakeResearchService(
              (_) async => const ResearchFailure(
                ResearchFailureKind.upstreamUnavailable,
              ),
            ),
          ),
          connectivityServiceProvider.overrideWithValue(
            FakeConnectivityService(ConnectivityStatus.online),
          ),
        ],
        child: MaterialApp(
          theme: theme,
          home: const Scaffold(body: Text('HOST')),
        ),
      ));
      // Pushed, as the app reaches it, so the header has a back button.
      Navigator.of(tester.element(find.text('HOST'))).push(
        MaterialPageRoute<void>(
          builder: (_) => const DetailsScreen(recordId: 1),
        ),
      );
      await tester.pumpAndSettle();
      final reason = '${theme.brightness}';

      final back = tester.widget<IconButton>(find.ancestor(
        of: find.byIcon(Icons.arrow_back),
        matching: find.byType(IconButton),
      ));
      expect(back.style?.backgroundColor?.resolve({}), Colors.black45,
          reason: reason);
      expect(back.color, Colors.white, reason: reason);

      final photo = find.descendant(
        of: find.byType(FlexibleSpaceBar),
        matching: find.byType(Image),
      );
      expect(tester.getRect(photo).top, greaterThanOrEqualTo(statusBar),
          reason: reason);

      await tester.pumpWidget(const SizedBox());
    }
  });

  // Android 12 to 14 now draw edge to edge, as 15+ already did, so the page
  // scrolls under a 48 dp three-button bar. Its last action must still end
  // above that bar (SPEC 0109).
  testWidgets('the_last_action_clears_the_navigation_bar', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 2.625;
    tester.view.padding = const FakeViewPadding(top: 63, bottom: 126);
    tester.view.viewPadding = const FakeViewPadding(top: 63, bottom: 126);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _detailsUnderTest(share: _RecordingShareService(), record: _locatedRecord()),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -5000));
    await tester.pumpAndSettle();

    final delete = find.ancestor(
      of: find.text('Excluir registro'),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    );
    expect(delete, findsOneWidget);
    const screenHeight = 1920 / 2.625;
    const navigationBar = 126 / 2.625;
    expect(
      tester.getRect(delete).bottom,
      lessThanOrEqualTo(screenHeight - navigationBar),
    );
  });

  // SPEC 0118: the back button reads "Voltar", and Delete keeps 24 dp from
  // Share.
  testWidgets('icon_buttons_are_labelled', (tester) async {
    await tester.pumpWidget(_detailsUnderTest(
      share: _RecordingShareService(),
      record: _locatedRecord(),
      pushed: true,
    ));
    await tester.tap(find.text('open details'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Voltar'), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing);
  });

  testWidgets('destructive_separated', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _detailsUnderTest(share: _RecordingShareService(), record: _locatedRecord()),
    );
    await tester.pumpAndSettle();

    final share = find.ancestor(
      of: find.text('Compartilhar'),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    );
    final delete = find.ancestor(
      of: find.text('Excluir registro'),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    );
    expect(
      tester.getRect(delete).top - tester.getRect(share).bottom,
      greaterThanOrEqualTo(24),
    );
  });

  // At 200 % text on a phone, every part of details still lays out
  // (SPEC 0121).
  testWidgets('details_scales_to_200_percent', (tester) async {
    useLargeTextOnAPhone(tester);

    await tester.pumpWidget(_detailsUnderTest(
      share: _RecordingShareService(),
      record: _locatedRecord(),
    ));
    await tester.pumpAndSettle();
    await scrollToTheEnd(tester);

    expect(tester.takeException(), isNull);
  });

  // The photograph at the top is a labelled way into the full-screen viewer
  // (SPEC 0125).
  testWidgets('hero_opens_viewer', (tester) async {
    final semantics = tester.ensureSemantics();
    final router = GoRouter(
      initialLocation: '/details',
      routes: [
        GoRoute(
          path: '/details',
          builder: (_, _) => const DetailsScreen(recordId: 1),
        ),
        GoRoute(
          path: '/preview',
          builder: (_, state) =>
              Scaffold(body: Text('PREVIEW_STUB ${state.extra}')),
        ),
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        soilRecordByIdProvider.overrideWith((ref, id) async => _locatedRecord()),
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
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    final hero = find.bySemanticsLabel('Ampliar foto');
    expect(hero, findsOneWidget);
    expect(
      tester.getSemantics(hero),
      isSemantics(isButton: true, hasTapAction: true),
    );

    await tester.tap(hero);
    await tester.pumpAndSettle();

    expect(find.text('PREVIEW_STUB 1'), findsOneWidget);
    semantics.dispose();
  });

  // From a record, the app bar starts the next capture, and back from it
  // returns to the same record (SPEC 0146).
  testWidgets('new_capture_from_details', (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => context.push('/details', extra: 1),
              child: const Text('open details'),
            ),
          ),
        ),
        GoRoute(
          path: '/details',
          builder: (_, _) => const DetailsScreen(recordId: 1),
        ),
        GoRoute(
          path: '/capture',
          builder: (_, _) => Scaffold(
            appBar: AppBar(),
            body: const Text('CAPTURE_STUB'),
          ),
        ),
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        soilRecordByIdProvider.overrideWith((ref, id) async => _locatedRecord()),
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
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.tap(find.text('open details'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Nova captura'));
    await tester.pumpAndSettle();
    expect(find.text('CAPTURE_STUB'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('CAPTURE_STUB'), findsNothing);
    expect(find.byType(DetailsScreen), findsOneWidget);
    expect(find.text('São Paulo, SP'), findsOneWidget);
    expect(find.byTooltip('Voltar'), findsOneWidget);
  });

  testWidgets('new_capture_is_labelled', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_detailsUnderTest(
      share: _RecordingShareService(),
      record: _locatedRecord(),
      pushed: true,
    ));
    await tester.tap(find.text('open details'));
    await tester.pumpAndSettle();

    final action = find.ancestor(
      of: find.byTooltip('Nova captura'),
      matching: find.byType(IconButton),
    );
    expect(action, findsOneWidget);
    expect(
      tester.getSemantics(action),
      isSemantics(tooltip: 'Nova captura', isButton: true, hasTapAction: true),
    );
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    semantics.dispose();
  });

  // SPEC 0149: the labels are edited from the identification tile.
  group('editing_labels_saves_them', () {
    late _LabellingRepository repo;

    Future<void> openDialog(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      repo = _LabellingRepository(
        _locatedRecord().copyWith(fieldName: 'Talhão 3', sampleLabel: 'A1'),
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [
          soilRecordRepositoryProvider.overrideWithValue(repo),
          soilRecordByIdProvider.overrideWith((ref, id) async => repo.current),
          managementTipsRepositoryProvider
              .overrideWithValue(FakeManagementTipsRepository()),
          researchServiceProvider.overrideWithValue(
            FakeResearchService(
              (_) async => const ResearchFailure(
                ResearchFailureKind.upstreamUnavailable,
              ),
            ),
          ),
          connectivityServiceProvider.overrideWithValue(
            FakeConnectivityService(ConnectivityStatus.online),
          ),
        ],
        child: const MaterialApp(home: DetailsScreen(recordId: 1)),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Editar'));
      await tester.pumpAndSettle();
    }

    Finder field(String label) => find.widgetWithText(TextField, label);

    testWidgets('the dialog opens with the current labels', (tester) async {
      await openDialog(tester);

      expect(
        tester.widget<TextField>(field('Talhão')).controller!.text,
        'Talhão 3',
      );
      expect(
        tester.widget<TextField>(field('Amostra')).controller!.text,
        'A1',
      );
    });

    testWidgets('saving writes the fields and shows them', (tester) async {
      await openDialog(tester);

      await tester.enterText(field('Talhão'), 'Talhão 4');
      await tester.enterText(field('Amostra'), ' B2 ');
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      expect(repo.updateLabelsCalls, hasLength(1));
      final call = repo.updateLabelsCalls.single;
      expect(call.id, 1);
      expect(call.fieldName, 'Talhão 4');
      expect(call.sampleLabel, ' B2 ');
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Talhão: Talhão 4\nAmostra:  B2 '), findsOneWidget);
    });

    testWidgets('cancelling writes nothing', (tester) async {
      await openDialog(tester);

      await tester.enterText(field('Talhão'), 'Talhão 4');
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(repo.updateLabelsCalls, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Talhão: Talhão 3\nAmostra: A1'), findsOneWidget);
    });

    testWidgets('a failed write says so', (tester) async {
      await openDialog(tester);
      repo.throwOnUpdateLabels = true;

      await tester.enterText(field('Talhão'), 'Talhão 4');
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      expect(
        find.text('Não foi possível salvar a identificação.'),
        findsOneWidget,
      );
    });
  });

  // The top of details, and its actions, each pass Flutter's four
  // accessibility guidelines (SPEC 0133).
  for (final (name, theme) in appThemes) {
    testWidgets('screens_meet_guidelines in the $name theme', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_detailsUnderTest(
        share: _RecordingShareService(),
        record: _locatedRecord(),
        pushed: true,
        theme: theme,
      ));
      await tester.tap(find.text('open details'));
      await tester.pumpAndSettle();
      await expectMeetsGuidelines(tester);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(find.text('Excluir registro').hitTestable(), findsOneWidget);
      await expectMeetsGuidelines(tester);
      semantics.dispose();
    });
  }
}
