import 'dart:async';

import 'package:flutter/material.dart';
import 'package:visiosoil_app/models/management_tips_result.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:visiosoil_app/core/features/details/management_tips_section.dart';
import 'package:visiosoil_app/core/widgets/collapse_on_correction.dart';
import 'package:visiosoil_app/core/widgets/error_state.dart';
import 'package:visiosoil_app/core/services/connectivity_service.dart';
import 'package:visiosoil_app/core/services/research/research_service.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';
import 'package:visiosoil_app/core/theme/soil_texture_colors.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/models/site_key.dart';
import 'package:visiosoil_app/core/services/region/site_resolver.dart';
import 'package:visiosoil_app/providers/site_resolver_provider.dart';
import 'package:visiosoil_app/providers/connectivity_provider.dart';
import 'package:visiosoil_app/providers/management_tips_repository_provider.dart';
import 'package:visiosoil_app/providers/research_service_provider.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import '../../support/management_tips_fakes.dart';

Widget harness({
  required SoilRecord record,
  required FakeManagementTipsRepository repo,
  required ResearchService service,
  required ConnectivityStatus connectivity,
  SiteResolver? resolver,
}) {
  return ProviderScope(
    overrides: [
      if (resolver != null) siteResolverProvider.overrideWithValue(resolver),
      managementTipsRepositoryProvider.overrideWithValue(repo),
      researchServiceProvider.overrideWithValue(service),
      connectivityServiceProvider
          .overrideWithValue(FakeConnectivityService(connectivity)),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: ManagementTipsSection(record: record)),
      ),
    ),
  );
}

FakeResearchService okService() =>
    FakeResearchService((_) async => ResearchSuccess(groundedTips()));

// Simulates a successful write whose subsequent cache read remains empty.
class NonRetainingTipsRepository extends FakeManagementTipsRepository {
  @override
  Future<void> upsert(String recordUuid, ManagementTipsResult result) async {
    upsertCount++;
  }
}

Future<void> rebuildTipsSection(WidgetTester tester) async {
  for (var rebuild = 0; rebuild < 3; rebuild++) {
    tester.element(find.byType(ManagementTipsSection)).markNeedsBuild();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('tips_appear_without_tapping_generate', (tester) async {
    final gate = Completer<ResearchResult>();
    final repo = FakeManagementTipsRepository();
    final service = FakeResearchService((_) => gate.future);
    await tester.pumpWidget(
      harness(
        record: tipsRecord(),
        repo: repo,
        service: service,
        connectivity: ConnectivityStatus.online,
        resolver: FakeSiteResolver(const SiteKey.unresolved()),
      ),
    );
    // Let the empty cache resolve and the scheduled generation start.
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(service.calls, 1);
    expect(find.text('Carregando dicas'), findsOneWidget);
    expect(repo.upsertCount, 0);

    gate.complete(ResearchSuccess(groundedTips()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Mantenha cobertura vegetal'), findsOneWidget);
    expect(repo.upsertCount, 1);
    expect(service.calls, 1);
  });

  testWidgets('auto_generation_restarts_for_a_new_record', (tester) async {
    final repo = FakeManagementTipsRepository();
    final service = okService();
    final resolver = FakeSiteResolver(const SiteKey.unresolved());
    Widget section(String uuid) => harness(
      record: tipsRecord(uuid: uuid),
      repo: repo,
      service: service,
      connectivity: ConnectivityStatus.online,
      resolver: resolver,
    );

    await tester.pumpWidget(section('rec-1'));
    await tester.pumpAndSettle();
    final originalState = tester.state(find.byType(ManagementTipsSection));
    expect(service.calls, 1);
    expect(await repo.getByRecordUuid('rec-2'), isNull);

    await tester.pumpWidget(section('rec-2'));
    await tester.pumpAndSettle();

    expect(tester.state(find.byType(ManagementTipsSection)), same(originalState));
    expect(service.calls, 2);
    expect(await repo.getByRecordUuid('rec-2'), isNotNull);
  });

  testWidgets('auto_generation_fires_once_after_failure', (tester) async {
    final repo = FakeManagementTipsRepository();
    final service = FakeResearchService(
      (_) async =>
          const ResearchFailure(ResearchFailureKind.upstreamUnavailable),
    );
    await tester.pumpWidget(
      harness(
        record: tipsRecord(),
        repo: repo,
        service: service,
        connectivity: ConnectivityStatus.online,
        resolver: FakeSiteResolver(const SiteKey.unresolved()),
      ),
    );
    await tester.pumpAndSettle();
    await rebuildTipsSection(tester);

    expect(service.calls, 1);
    expect(repo.upsertCount, 0);
    expect(
      find.textContaining('Não foi possível gerar as dicas agora'),
      findsOneWidget,
    );

    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    await rebuildTipsSection(tester);

    expect(service.calls, 2);
    expect(repo.upsertCount, 0);
  });

  testWidgets('auto_generation_fires_once_without_cached_result', (
    tester,
  ) async {
    final repo = NonRetainingTipsRepository();
    final service = okService();
    await tester.pumpWidget(
      harness(
        record: tipsRecord(),
        repo: repo,
        service: service,
        connectivity: ConnectivityStatus.online,
        resolver: FakeSiteResolver(const SiteKey.unresolved()),
      ),
    );
    // Bounded pumps also catch a generation loop without timing out settling.
    await rebuildTipsSection(tester);

    expect(service.calls, 1);
    expect(repo.upsertCount, 1);
    expect(await repo.getByRecordUuid('rec-1'), isNull);
    expect(find.text('Carregando dicas'), findsNothing);
    await rebuildTipsSection(tester);
    expect(service.calls, 1);
  });

  testWidgets('no_corpus_message_shows', (tester) async {
    final repo = FakeManagementTipsRepository();
    final service = FakeResearchService(
      (_) async => ResearchSuccess(noCorpusTips()),
    );
    await tester.pumpWidget(
      harness(
        record: tipsRecord(),
        repo: repo,
        service: service,
        connectivity: ConnectivityStatus.online,
        resolver: FakeSiteResolver(const SiteKey.unresolved()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'As dicas de manejo ainda não estão disponíveis nesta versão '
        'do app.',
      ),
      findsOneWidget,
    );
    expect(repo.upsertCount, 0);
    expect(await repo.getByRecordUuid('rec-1'), isNull);
    await rebuildTipsSection(tester);
    expect(service.calls, 1);
  });

  testWidgets('data state renders cards, chips, sources and disclaimer',
      (tester) async {
    final repo = FakeManagementTipsRepository()..seed('rec-1', groundedTips());
    await tester.pumpWidget(harness(
      record: tipsRecord(),
      repo: repo,
      service: okService(),
      connectivity: ConnectivityStatus.online,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Dicas de manejo'), findsOneWidget);
    expect(find.textContaining('Mantenha cobertura vegetal'), findsOneWidget);
    // The card numbers its cited source, and the sources open from a
    // button rather than a list (SPEC 0270).
    expect(
      find.descendant(
        of: find.byKey(const Key('tip-card')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(find.text('Embrapa Solos · Embrapa'), findsNothing);
    expect(find.text('Ver fontes (1 citada)'), findsOneWidget);
    expect(find.textContaining('consultivo'), findsOneWidget);
    expect(find.text('Atualizar dicas'), findsOneWidget);
    expect(find.textContaining('recomenda'), findsNothing);
  });

  testWidgets('tips_error_is_in_the_region', (tester) async {
    await tester.pumpWidget(harness(
      record: tipsRecord(),
      repo: FakeManagementTipsRepository(),
      service: FakeResearchService(
        (_) async => const ResearchFailure(ResearchFailureKind.network),
      ),
      connectivity: ConnectivityStatus.online,
    ));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(CollapseOnCorrection),
        matching: find.byType(ErrorState),
      ),
      findsOneWidget,
    );
  });

  testWidgets('empty cache online automatically shows tips', (tester) async {
    await tester.pumpWidget(harness(
      record: tipsRecord(),
      repo: FakeManagementTipsRepository(),
      service: okService(),
      connectivity: ConnectivityStatus.online,
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Mantenha cobertura vegetal'), findsOneWidget);
    expect(find.text('Atualizar dicas'), findsOneWidget);
  });

  // Tips compose on the device from the corpus the app holds (ADR 0022), so
  // being offline changes nothing about them (SPEC 0090).
  group('offline', () {
    testWidgets('offline_empty_cache_automatically_shows_tips', (tester) async {
      await tester.pumpWidget(harness(
        record: tipsRecord(),
        repo: FakeManagementTipsRepository(),
        service: okService(),
        connectivity: ConnectivityStatus.offline,
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Mantenha cobertura vegetal'), findsOneWidget);
      expect(find.text('Sem conexão'), findsNothing);
      expect(find.textContaining('Conecte-se'), findsNothing);
    });

    testWidgets('offline_generate_composes_tips', (tester) async {
      final service = okService();
      await tester.pumpWidget(harness(
        record: tipsRecord(),
        repo: FakeManagementTipsRepository(),
        service: service,
        connectivity: ConnectivityStatus.offline,
      ));
      await tester.pumpAndSettle();

      expect(service.calls, 1);
      expect(find.textContaining('Mantenha cobertura vegetal'), findsOneWidget);
    });

    testWidgets('offline_failed_generation_offers_retry', (tester) async {
      final service = FakeResearchService((_) async =>
          const ResearchFailure(ResearchFailureKind.upstreamUnavailable));
      await tester.pumpWidget(harness(
        record: tipsRecord(),
        repo: FakeManagementTipsRepository(),
        service: service,
        connectivity: ConnectivityStatus.offline,
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Não foi possível gerar as dicas agora'),
          findsOneWidget);

      await tester.tap(find.text('Tentar novamente'));
      await tester.pumpAndSettle();
      expect(service.calls, 2);
    });

    testWidgets('offline_cached_tips_offer_refresh', (tester) async {
      final service = okService();
      await tester.pumpWidget(harness(
        record: tipsRecord(),
        repo: FakeManagementTipsRepository()..seed('rec-1', groundedTips()),
        service: service,
        connectivity: ConnectivityStatus.offline,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Atualizar dicas'));
      await tester.pumpAndSettle();

      expect(service.calls, 1);
    });
  });

  testWidgets('unclassified record shows guidance and no button', (tester) async {
    await tester.pumpWidget(harness(
      record: tipsRecord(textureClass: null),
      repo: FakeManagementTipsRepository(),
      service: okService(),
      connectivity: ConnectivityStatus.online,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Solo não classificado'), findsOneWidget);
    expect(find.text('Gerar dicas'), findsNothing);
  });

  // No screen can classify a saved record, so the message says how to get
  // tips rather than asking for an action that does not exist (SPEC 0105).
  testWidgets('an_unclassified_record_says_how_to_get_tips', (tester) async {
    await tester.pumpWidget(harness(
      record: tipsRecord(textureClass: null),
      repo: FakeManagementTipsRepository(),
      service: okService(),
      connectivity: ConnectivityStatus.online,
    ));
    await tester.pumpAndSettle();

    expect(
      find.text('Esta análise foi salva sem a classe de textura, e as dicas '
          'dependem dela. Para obtê-las, capture a amostra de novo seguindo o '
          'passo a passo.'),
      findsOneWidget,
    );
    expect(find.textContaining('Classifique o solo deste registro'),
        findsNothing);
  });

  testWidgets('abstained result shows the abstained message and disclaimer',
      (tester) async {
    final repo = FakeManagementTipsRepository()
      ..seed('rec-1', ManagementTipsResultBuilder.abstained());
    await tester.pumpWidget(harness(
      record: tipsRecord(),
      repo: repo,
      service: okService(),
      connectivity: ConnectivityStatus.online,
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Não encontramos dicas de manejo'), findsOneWidget);
    expect(find.textContaining('consultiv'), findsOneWidget);
  });

  // An abstention's sources are what was read, not what supports a tip
  // (SPEC 0233).
  testWidgets('abstained_result_names_the_consulted_sources', (tester) async {
    final grounded = groundedTips();
    final repo = FakeManagementTipsRepository()
      ..seed(
        'rec-1',
        ManagementTipsResult(
          status: ManagementTipsStatus.abstained,
          tips: const [],
          sources: grounded.sources,
          disclaimer: grounded.disclaimer,
          model: grounded.model,
          retrievedAt: grounded.retrievedAt,
        ),
      );
    await tester.pumpWidget(harness(
      record: tipsRecord(),
      repo: repo,
      service: okService(),
      connectivity: ConnectivityStatus.online,
    ));
    await tester.pumpAndSettle();

    // The sources open from a sheet (SPEC 0270).
    expect(find.text('Ver fontes consultadas (1)'), findsOneWidget);
    await openSources(tester, 'Ver fontes consultadas (1)');
    expect(find.text('Fontes consultadas'), findsOneWidget);
    for (final source in grounded.sources) {
      expect(find.text(source.title), findsOneWidget);
    }
  });

  testWidgets('generation shows a loading indicator then the result',
      (tester) async {
    final gate = Completer<ResearchResult>();
    final service = FakeResearchService((_) => gate.future);
    await tester.pumpWidget(harness(
      record: tipsRecord(),
      repo: FakeManagementTipsRepository(),
      service: service,
      connectivity: ConnectivityStatus.online,
    ));
    // Generation starts on open; settling would wait on the pending service.
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.text('Carregando dicas'), findsOneWidget);

    gate.complete(ResearchSuccess(groundedTips()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Mantenha cobertura vegetal'), findsOneWidget);
  });

  testWidgets('first-generation failure shows a mapped message and retry',
      (tester) async {
    final service = FakeResearchService(
        (_) async => const ResearchFailure(ResearchFailureKind.upstreamUnavailable));
    await tester.pumpWidget(harness(
      record: tipsRecord(),
      repo: FakeManagementTipsRepository(),
      service: service,
      connectivity: ConnectivityStatus.online,
    ));
    await tester.pumpAndSettle();

    expect(
        find.textContaining('Não foi possível gerar as dicas agora'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);
  });

  testWidgets('a failed refresh keeps the cached tips and shows a snackbar',
      (tester) async {
    final repo = FakeManagementTipsRepository()..seed('rec-1', groundedTips());
    final service = FakeResearchService(
        (_) async => const ResearchFailure(ResearchFailureKind.upstreamUnavailable));
    await tester.pumpWidget(harness(
      record: tipsRecord(),
      repo: repo,
      service: service,
      connectivity: ConnectivityStatus.online,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Atualizar dicas'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Mantenha cobertura vegetal'), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('empty disclaimer falls back to the advisory disclaimer copy',
      (tester) async {
    final repo = FakeManagementTipsRepository()
      ..seed('rec-1', ManagementTipsResultBuilder.groundedWithoutDisclaimer());
    await tester.pumpWidget(harness(
      record: tipsRecord(),
      repo: repo,
      service: okService(),
      connectivity: ConnectivityStatus.online,
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Não substituem avaliação técnica presencial'),
        findsOneWidget);
  });

  // The disclaimer's icon is meaningful, so it needs 3 : 1 on what it sits
  // on (SPEC 0127); the banner has no fill, so that is the page (SPEC 0243).
  testWidgets('disclaimer_icon_reads_on_its_banner', (tester) async {
    double contrast(Color a, Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      final (hi, lo) = la > lb ? (la, lb) : (lb, la);
      return (hi + 0.05) / (lo + 0.05);
    }

    for (final (theme, palette) in [
      (AppTheme.light, AppPalette.light),
      (AppTheme.dark, AppPalette.dark),
      (AppTheme.lightHighContrast, AppPalette.lightHighContrast),
      (AppTheme.darkHighContrast, AppPalette.darkHighContrast),
      (AppTheme.sun, AppPalette.sun),
    ]) {
      final repo = FakeManagementTipsRepository()
        ..seed('rec-1', groundedTips());
      await tester.pumpWidget(ProviderScope(
        overrides: [
          managementTipsRepositoryProvider.overrideWithValue(repo),
          researchServiceProvider.overrideWithValue(okService()),
          connectivityServiceProvider.overrideWithValue(
              FakeConnectivityService(ConnectivityStatus.online)),
        ],
        child: MaterialApp(
          theme: theme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ManagementTipsSection(record: tipsRecord()),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final banner = find.ancestor(
        of: find.textContaining('consultivo'),
        matching: find.byType(Row),
      );
      final icon = tester.widget<Icon>(find.descendant(
        of: banner.first,
        matching: find.byIcon(LucideIcons.info),
      ));
      expect(icon.color, palette.warningText);
      expect(
        contrast(icon.color!, palette.background),
        greaterThanOrEqualTo(3),
      );

      await tester.pumpWidget(const SizedBox());
    }
  });

  // In high contrast the disclaimer's edge is a card's, solid and 2 dp wide
  // (SPEC 0135, SPEC 0243).
  testWidgets('hc_banner_edges_read: the tips disclaimer', (tester) async {
    final repo = FakeManagementTipsRepository()..seed('rec-1', groundedTips());
    await tester.pumpWidget(ProviderScope(
      overrides: [
        managementTipsRepositoryProvider.overrideWithValue(repo),
        researchServiceProvider.overrideWithValue(okService()),
        connectivityServiceProvider.overrideWithValue(
            FakeConnectivityService(ConnectivityStatus.online)),
      ],
      child: MaterialApp(
        theme: AppTheme.lightHighContrast,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ManagementTipsSection(record: tipsRecord()),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final banner = tester.widget<Container>(find
        .ancestor(
          of: find.textContaining('consultivo'),
          matching: find.byWidgetPredicate((w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).border != null),
        )
        .first);
    final edge = ((banner.decoration! as BoxDecoration).border! as Border).top;
    expect(edge.color, AppPalette.lightHighContrast.outline);
    expect(edge.width, 2);
  });

  // The v11 tips timeline (redesign §3.9, SPEC 0198).
  group('tips timeline', () {
    ManagementTipsResult twoCategories() => ManagementTipsResult(
          status: ManagementTipsStatus.grounded,
          tips: const [
            ManagementTip(
              text: 'Ajuste a lâmina de irrigação.',
              citations: [0, 1],
              category: TipCategory.water,
            ),
            ManagementTip(
              text: 'Evite tráfego com solo úmido.',
              citations: [0],
              category: TipCategory.preparation,
            ),
          ],
          sources: const [
            TipSource(title: 'Guia de solos', url: 'https://a', publisher: 'Embrapa'),
            TipSource(title: 'Manual de irrigação', url: 'https://b'),
          ],
          disclaimer: 'Conteudo consultivo.',
          model: 'corpus',
          retrievedAt: DateTime.utc(2026, 6, 26, 12),
        );

    Future<void> pumpTimeline(
      WidgetTester tester, {
      ManagementTipsResult? result,
    }) async {
      await tester.binding.setSurfaceSize(const Size(420, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = FakeManagementTipsRepository()
        ..seed('rec-1', result ?? twoCategories());
      await tester.pumpWidget(harness(
        record: tipsRecord(textureClass: 'Media'),
        repo: repo,
        service: okService(),
        connectivity: ConnectivityStatus.online,
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('tips_render_as_a_timeline_by_category', (tester) async {
      await pumpTimeline(tester);

      final preparation = tester.getTopLeft(find.text('Preparo do solo')).dy;
      final water = tester.getTopLeft(find.text('Água')).dy;
      expect(preparation, lessThan(water));
      expect(
        tester.getTopLeft(find.text('Evite tráfego com solo úmido.')).dy,
        lessThan(water),
      );
      // The water tip cites both sources, numbered as the sheet numbers
      // them (SPEC 0270).
      final waterCard = find.byKey(const Key('tip-card')).at(1);
      for (final number in ['1', '2']) {
        expect(
          find.descendant(of: waterCard, matching: find.text(number)),
          findsOneWidget,
        );
      }
      expect(find.byIcon(LucideIcons.tractor), findsOneWidget);
      expect(find.byIcon(LucideIcons.droplets), findsOneWidget);
    });

    testWidgets('tips_header_counts_the_tips', (tester) async {
      await pumpTimeline(tester);
      expect(find.text('Média · 2 dicas'), findsOneWidget);
    });

    // SPEC 0231: one tip reads in the singular.
    testWidgets('tips_header_counts_one_tip_in_the_singular', (tester) async {
      final two = twoCategories();
      await pumpTimeline(
        tester,
        result: ManagementTipsResult(
          status: two.status,
          tips: two.tips.take(1).toList(),
          sources: two.sources,
          disclaimer: two.disclaimer,
          model: two.model,
          retrievedAt: two.retrievedAt,
        ),
      );
      expect(find.text('Média · 1 dica'), findsOneWidget);
    });
  });

  // The Dicas tab as PNG 20 draws it (SPEC 0205).
  group('tips page', () {
    ManagementTipsResult twoGroups() => ManagementTipsResult(
          status: ManagementTipsStatus.grounded,
          tips: const [
            ManagementTip(
              text: 'Evite tráfego com solo úmido.',
              citations: [0],
              category: TipCategory.preparation,
            ),
            ManagementTip(
              text: 'Ajuste a lâmina de irrigação.',
              citations: [0],
              category: TipCategory.water,
            ),
          ],
          sources: const [TipSource(title: 'Guia de solos', url: 'https://a')],
          disclaimer: 'Conteudo consultivo.',
          model: 'corpus',
          retrievedAt: DateTime.utc(2026, 6, 26, 12),
        );

    Future<void> pumpPage(
      WidgetTester tester, {
      bool asPage = true,
      ManagementTipsResult? result,
      Set<TipCategory> hiddenCategories = const {},
      double width = 390,
      bool labelled = true,
    }) async {
      await tester.binding.setSurfaceSize(Size(width, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = FakeManagementTipsRepository()
        ..seed('rec-1', result ?? twoGroups());
      await tester.pumpWidget(ProviderScope(
        overrides: [
          managementTipsRepositoryProvider.overrideWithValue(repo),
          researchServiceProvider.overrideWithValue(okService()),
          connectivityServiceProvider.overrideWithValue(
              FakeConnectivityService(ConnectivityStatus.online)),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ManagementTipsSection(
                asPage: asPage,
                hiddenCategories: hiddenCategories,
                record: labelled
                    ? tipsRecord().copyWith(
                        fieldName: 'Talhão 3',
                        sampleLabel: 'Amostra 2',
                      )
                    : tipsRecord(),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('tips_page_heads_with_the_record', (tester) async {
      await pumpPage(tester);

      expect(find.text('Argilosa'), findsOneWidget);
      // SPEC 0220: the sample heads the page alone.
      expect(find.text('Amostra 2'), findsOneWidget);
      expect(find.textContaining('Talhão 3'), findsNothing);
      expect(find.text('2 dicas'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('tips-record-photo'))),
        const Size(56, 56),
      );
      expect(find.text('Dicas de manejo'), findsNothing);
    });

    // SPEC 0245: with no labels, the head shows the date as every screen
    // writes it.
    testWidgets('tips_head_shows_the_dotted_date', (tester) async {
      await pumpPage(tester, labelled: false);

      final record = tipsRecord();
      expect(find.text(record.formattedTimestampDotted), findsOneWidget);
      expect(find.text(record.formattedTimestampCompact), findsNothing);
    });

    testWidgets('tips_photo_placeholder_shows_the_class', (tester) async {
      await pumpPage(tester);

      // 'x.png' never loads, so the head shows its placeholder: the
      // history tile's, in the class's colour (SPEC 0242).
      final photo = find.byKey(const Key('tips-record-photo'));
      final clay = SoilTextureColors.forClass('Argilosa');
      final icon = tester.widget<Icon>(
        find.descendant(of: photo, matching: find.byType(Icon)),
      );
      expect(icon.icon, LucideIcons.mountain);
      expect(icon.color, clay);
      final ground = tester.widget<ColoredBox>(
        find.descendant(of: photo, matching: find.byType(ColoredBox)).first,
      );
      expect(ground.color, clay.withValues(alpha: 0.3));
    });

    testWidgets('disclaimer_comes_first', (tester) async {
      await pumpPage(tester);

      final banner = find.byKey(const Key('tips-disclaimer'));
      expect(
        tester.getTopLeft(banner).dy,
        lessThan(tester.getTopLeft(find.text('Preparo do solo')).dy),
      );
      // No fill and a card's hairline edge (SPEC 0243).
      final decoration =
          tester.widget<Container>(banner).decoration! as BoxDecoration;
      expect(decoration.color, isNull);
      final edge = (decoration.border! as Border).top;
      expect(edge.color, AppPalette.light.cardBorder);
      expect(edge.width, 1);
    });

    testWidgets('disclaimer_colours_only_its_icon', (tester) async {
      await pumpPage(tester);

      final banner = find.byKey(const Key('tips-disclaimer'));
      final icon = tester.widget<Icon>(
        find.descendant(of: banner, matching: find.byType(Icon)),
      );
      expect(icon.color, AppPalette.light.warningText);
      final text = tester.widget<Text>(
        find.descendant(of: banner, matching: find.text('Conteudo consultivo.')),
      );
      expect(text.style?.color, AppPalette.light.onSurfaceVariant);
    });

    testWidgets('timeline_matches_the_mock', (tester) async {
      await pumpPage(tester);

      expect(tester.widget<Text>(find.text('Preparo do solo')).style?.fontSize,
          16);
      BoxDecoration dot(int i) =>
          tester.widget<Container>(find.byKey(Key('tips-dot-$i'))).decoration!
              as BoxDecoration;
      expect(dot(0).color, AppPalette.light.primary);
      expect(dot(1).color, AppPalette.light.surface);
      expect((dot(1).border! as Border).top.color, AppPalette.light.outline);
    });

    testWidgets('tip_card_matches_the_mock', (tester) async {
      await pumpPage(tester);

      final card = tester.widget<Container>(
        find.byKey(const Key('tip-card')).first,
      );
      final decoration = card.decoration! as BoxDecoration;
      expect((decoration.border! as Border).top.color, AppPalette.light.divider);
      expect(decoration.borderRadius, BorderRadius.circular(16));
      expect(
        tester.getSize(find.byKey(const Key('tip-icon-tile')).first),
        const Size(40, 40),
      );
      expect(find.byIcon(LucideIcons.tractor), findsOneWidget);
      expect(find.byIcon(LucideIcons.droplets), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('Evite tráfego com solo úmido.')).style
            ?.fontSize,
        14,
      );
    });

    // SPEC 0209: phases, titles and the filter.
    ManagementTipsResult phased() => ManagementTipsResult(
          status: ManagementTipsStatus.grounded,
          tips: const [
            ManagementTip(
              title: 'Ajuste a lâmina de irrigação',
              text: 'Prefira turnos mais espaçados.',
              citations: [0],
              category: TipCategory.water,
              phase: TipPhase.sowing,
            ),
            ManagementTip(
              title: 'Evite tráfego com solo úmido',
              text: 'Entre com máquinas abaixo do ponto de friabilidade.',
              citations: [0],
              category: TipCategory.preparation,
              phase: TipPhase.beforePlanting,
            ),
            ManagementTip(
              title: 'Monitore o encharcamento',
              text: 'Observe as baixadas após chuvas fortes.',
              citations: [0],
              category: TipCategory.water,
              phase: TipPhase.cropCycle,
            ),
          ],
          sources: const [TipSource(title: 'Guia de solos', url: 'https://a')],
          disclaimer: 'Conteudo consultivo.',
          model: 'corpus',
          retrievedAt: DateTime.utc(2026, 6, 26, 12),
        );

    testWidgets('phases_group_the_timeline', (tester) async {
      // Wide enough for the test font to keep each title and its chip on
      // one line.
      await pumpPage(tester, result: phased(), width: 800);

      final before = tester.getTopLeft(find.text('Antes do plantio')).dy;
      final sowing = tester.getTopLeft(find.text('Semeadura')).dy;
      final cycle = tester.getTopLeft(find.text('Ciclo da cultura')).dy;
      expect(before, lessThan(sowing));
      expect(sowing, lessThan(cycle));
      expect(find.text('Preparo do solo'), findsNothing);

      final now = find.byKey(const Key('tips-phase-chip-0'));
      final next = find.byKey(const Key('tips-phase-chip-1'));
      expect(find.descendant(of: now, matching: find.text('Agora')), findsOneWidget);
      expect(
        find.descendant(of: next, matching: find.text('Próximo')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('tips-phase-chip-2')), findsNothing);
      expect(tester.getSize(now).height, 24);
      final nowBox = tester.widget<Container>(now).decoration! as BoxDecoration;
      final nextBox = tester.widget<Container>(next).decoration! as BoxDecoration;
      expect(nowBox.color, AppPalette.light.selected);
      expect(nextBox.color, AppPalette.light.surfaceContainer);
      final label = tester.widget<Text>(find.text('Agora'));
      expect(label.style?.fontSize, 12);
      expect(label.style?.color, AppPalette.light.primaryText);
      expect(
        tester.getTopLeft(now).dx -
            tester.getTopRight(find.text('Antes do plantio')).dx,
        8,
      );
    });

    testWidgets('categories_group_without_phases', (tester) async {
      await pumpPage(tester);

      expect(find.text('Preparo do solo'), findsOneWidget);
      expect(find.text('Agora'), findsNothing);
      expect(find.text('Próximo'), findsNothing);
    });

    testWidgets('titled_card_matches_the_mock', (tester) async {
      await pumpPage(tester, result: phased());

      final title = tester.widget<Text>(find.text('Evite tráfego com solo úmido'));
      expect(title.style?.fontSize, 15);
      expect(title.style?.fontWeight, FontWeight.w600);
      expect(title.style?.color, AppPalette.light.onSurface);
      final body = tester.widget<Text>(
        find.text('Entre com máquinas abaixo do ponto de friabilidade.'),
      );
      expect(body.style?.fontSize, 14);
      expect(body.style?.color, AppPalette.light.onSurfaceVariant);
      expect(
        tester
                .getTopLeft(
                  find.text('Entre com máquinas abaixo do ponto de friabilidade.'),
                )
                .dy -
            tester.getBottomLeft(find.text('Evite tráfego com solo úmido')).dy,
        0,
      );
    });

    testWidgets('filter_hides_a_category', (tester) async {
      await pumpPage(
        tester,
        result: phased(),
        hiddenCategories: const {TipCategory.water},
      );

      expect(find.text('Evite tráfego com solo úmido'), findsOneWidget);
      expect(find.text('Ajuste a lâmina de irrigação'), findsNothing);
      expect(find.text('Monitore o encharcamento'), findsNothing);
      expect(find.text('1 dica'), findsOneWidget);
    });

    // A filter hides tips, not the support they have (SPEC 0233).
    testWidgets('filter_hiding_every_tip_keeps_the_sources_heading',
        (tester) async {
      await pumpPage(
        tester,
        result: phased(),
        hiddenCategories: const {TipCategory.water, TipCategory.preparation},
      );

      expect(find.text('Nenhuma dica nas categorias escolhidas.'), findsOneWidget);
      // The button keeps counting the citations (SPEC 0270).
      expect(find.text('Ver fontes (1 citada)'), findsOneWidget);
      expect(find.textContaining('Ver fontes consultadas'), findsNothing);
    });

    testWidgets('tipless_result_names_the_consulted_sources', (tester) async {
      final grounded = phased();
      await pumpPage(
        tester,
        result: ManagementTipsResult(
          status: ManagementTipsStatus.insufficientEvidence,
          tips: const [],
          sources: grounded.sources,
          disclaimer: grounded.disclaimer,
          model: grounded.model,
          retrievedAt: grounded.retrievedAt,
        ),
      );

      expect(find.text('Ver fontes consultadas (1)'), findsOneWidget);
      expect(find.textContaining('citada'), findsNothing);
    });

    testWidgets('filter_sheet_toggles_a_category', (tester) async {
      Set<TipCategory>? chosen;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showTipsFilterSheet(
              context,
              present: const {TipCategory.preparation, TipCategory.water},
              hidden: const {},
              onChanged: (hidden) => chosen = hidden,
            ),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Filtrar dicas'), findsOneWidget);
      expect(find.text('Preparo do solo'), findsOneWidget);
      await tester.tap(find.text('Água'));
      await tester.pumpAndSettle();

      expect(chosen, {TipCategory.water});
    });
  
    // A tip without a category is not filed under "Outras práticas": the
    // sheet offers only categories the tips carry, and no switch hides an
    // uncategorised tip (SPEC 0209; review of #439).
    test('uncategorised_tips_are_not_filterable', () {
      const loose = ManagementTip(text: 'Sem categoria', citations: [0]);
      const water = ManagementTip(
        text: 'Água',
        citations: [0],
        category: TipCategory.water,
      );
      expect(filterableCategories(const [loose]), isEmpty);
      expect(filterableCategories(const [loose, water]), {TipCategory.water});
      expect(
        shownTips(const [loose, water], const {TipCategory.other}),
        const [loose, water],
      );
    });

    // SPEC 0270: numbered chips on the cards, the sources in a sheet.
    const sheetSources = [
      TipSource(
        title: 'Guia de solos',
        url: 'https://a.example/guia',
        publisher: 'Embrapa',
      ),
      TipSource(
        title: 'Manual de irrigação',
        url: 'https://b.example/manual',
        publisher: 'IAC',
      ),
      TipSource(title: 'Boletim de drenagem', url: 'https://c.example/boletim'),
    ];

    // The first tip is filed under Preparo, the others under Água, so the
    // first card on the page is the first tip.
    ManagementTipsResult citing(List<List<int>> citations) =>
        ManagementTipsResult(
          status: ManagementTipsStatus.grounded,
          tips: [
            for (var i = 0; i < citations.length; i++)
              ManagementTip(
                text: 'Dica ${i + 1}.',
                citations: citations[i],
                category:
                    i == 0 ? TipCategory.preparation : TipCategory.water,
              ),
          ],
          sources: sheetSources,
          disclaimer: 'Conteudo consultivo.',
          model: 'corpus',
          retrievedAt: DateTime.utc(2026, 6, 26, 12),
        );

    Finder inCard(int index, String text) => find.descendant(
          of: find.byKey(const Key('tip-card')).at(index),
          matching: find.text(text),
        );

    test('citation_numbers_follow_first_citation', () {
      final numbers = citationNumbers(const [
        ManagementTip(text: 'a', citations: [2, 0]),
        ManagementTip(text: 'b', citations: [0, 6, -1]),
        ManagementTip(text: 'c', citations: [5]),
      ], 6);

      expect(numbers, {2: 1, 0: 2, 5: 3});
    });

    testWidgets('tip_card_shows_citation_chips', (tester) async {
      await pumpPage(tester, result: citing([[1, 0], [0]]));

      expect(inCard(0, '1'), findsOneWidget);
      expect(inCard(0, '2'), findsOneWidget);
      expect(inCard(1, '2'), findsOneWidget);
      expect(inCard(1, '1'), findsNothing);
      expect(find.byIcon(LucideIcons.bookmark), findsNothing);
    });

    testWidgets('sources_are_not_stacked_on_the_page', (tester) async {
      await pumpPage(tester, result: citing([[1, 0], [0]]));

      for (final source in sheetSources) {
        expect(find.textContaining(source.title), findsNothing);
      }
      expect(find.text('Fontes'), findsNothing);
    });

    testWidgets('button_counts_the_cited_sources (one)', (tester) async {
      await pumpPage(tester, result: citing([[0]]));

      expect(find.text('Ver fontes (1 citada)'), findsOneWidget);
    });

    testWidgets('button_counts_the_cited_sources (two)', (tester) async {
      await pumpPage(tester, result: citing([[1, 0]]));

      expect(find.text('Ver fontes (2 citadas)'), findsOneWidget);
    });

    testWidgets('sheet_opens_on_the_cited_sources', (tester) async {
      await pumpPage(tester, result: citing([[1, 0], [0]]));
      await openSources(tester, 'Ver fontes (2 citadas)');

      expect(find.text('Fontes'), findsOneWidget);
      expect(find.text('Citadas (2)'), findsOneWidget);
      expect(find.text('Todas (3)'), findsOneWidget);
      expect(find.text('Manual de irrigação'), findsOneWidget);
      expect(find.text('Guia de solos'), findsOneWidget);
      expect(find.text('Boletim de drenagem'), findsNothing);
      // Numbered by first citation: the first tip cites source 1 first.
      double top(String text) => tester.getTopLeft(find.text(text)).dy;
      expect(top('Manual de irrigação'), lessThan(top('Guia de solos')));

      await tester.tap(find.byKey(const Key('segment-1')));
      await tester.pumpAndSettle();

      expect(find.text('Boletim de drenagem'), findsOneWidget);
      expect(top('Guia de solos'), lessThan(top('Boletim de drenagem')));
      expect(find.text('·'), findsOneWidget);
    });

    testWidgets('sheet_without_a_choice_hides_the_control', (tester) async {
      await pumpPage(tester, result: citing([[0, 1, 2]]));
      await openSources(tester, 'Ver fontes (3 citadas)');

      for (final source in sheetSources) {
        expect(find.text(source.title), findsOneWidget);
      }
      expect(find.textContaining('Citadas ('), findsNothing);
      expect(find.textContaining('Todas ('), findsNothing);
    });

    testWidgets('tipless_result_offers_the_consulted_sources', (tester) async {
      await pumpPage(
        tester,
        result: ManagementTipsResult(
          status: ManagementTipsStatus.abstained,
          tips: const [],
          sources: sheetSources.sublist(0, 2),
          disclaimer: 'Conteudo consultivo.',
          model: 'corpus',
          retrievedAt: DateTime.utc(2026, 6, 26, 12),
        ),
      );

      expect(find.text('Ver fontes consultadas (2)'), findsOneWidget);
      await openSources(tester, 'Ver fontes consultadas (2)');

      expect(find.text('Fontes consultadas'), findsOneWidget);
      expect(find.text('Guia de solos'), findsOneWidget);
      expect(find.text('Manual de irrigação'), findsOneWidget);
      expect(find.textContaining('Citadas ('), findsNothing);
    });

    testWidgets('filter_does_not_renumber_the_chips', (tester) async {
      await pumpPage(
        tester,
        result: citing([[1], [0]]),
        hiddenCategories: const {TipCategory.preparation},
      );

      expect(inCard(0, '2'), findsOneWidget);
      expect(inCard(0, '1'), findsNothing);
      expect(find.text('Ver fontes (2 citadas)'), findsOneWidget);
    });

    group('launch', () {
      late UrlLauncherPlatform original;
      late _RecordingUrlLauncher launcher;

      setUp(() {
        original = UrlLauncherPlatform.instance;
        launcher = _RecordingUrlLauncher();
        UrlLauncherPlatform.instance = launcher;
      });

      tearDown(() => UrlLauncherPlatform.instance = original);

      testWidgets('tapping_a_source_opens_it', (tester) async {
        await pumpPage(tester, result: citing([[1, 0], [0]]));
        await openSources(tester, 'Ver fontes (2 citadas)');
        await tester.tap(find.text('Manual de irrigação'));
        await tester.pumpAndSettle();

        expect(launcher.launches, [
          ('https://b.example/manual', PreferredLaunchMode.externalApplication),
        ]);
        expect(find.text('Não foi possível abrir a fonte.'), findsNothing);
      });

      testWidgets('a_failed_launch_is_said_in_the_sheet', (tester) async {
        launcher.result = false;
        await pumpPage(tester, result: citing([[1, 0], [0]]));
        await openSources(tester, 'Ver fontes (2 citadas)');
        await tester.tap(find.text('Manual de irrigação'));
        await tester.pumpAndSettle();

        expect(launcher.launches, hasLength(1));
        expect(find.text('Não foi possível abrir a fonte.'), findsOneWidget);
      });
    });
  });
}

/// Scrolls [label] into view, taps it, and lets the sheet settle.
Future<void> openSources(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

/// Records each launch, and answers with [result].
class _RecordingUrlLauncher extends UrlLauncherPlatform {
  final launches = <(String, PreferredLaunchMode)>[];
  bool result = true;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launches.add((url, options.mode));
    return result;
  }
}
