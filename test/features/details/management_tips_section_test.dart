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
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/connectivity_provider.dart';
import 'package:visiosoil_app/providers/management_tips_repository_provider.dart';
import 'package:visiosoil_app/providers/research_service_provider.dart';
import '../../support/management_tips_fakes.dart';

Widget harness({
  required SoilRecord record,
  required FakeManagementTipsRepository repo,
  required ResearchService service,
  required ConnectivityStatus connectivity,
}) {
  return ProviderScope(
    overrides: [
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

void main() {
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
    // The card's source line names the cited source (SPEC 0198).
    expect(find.text('Embrapa Solos · Embrapa'), findsOneWidget);
    expect(find.text('Fontes'), findsOneWidget);
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
    await tester.tap(find.text('Gerar dicas'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(CollapseOnCorrection),
        matching: find.byType(ErrorState),
      ),
      findsOneWidget,
    );
  });

  testWidgets('empty cache online shows the generate button', (tester) async {
    await tester.pumpWidget(harness(
      record: tipsRecord(),
      repo: FakeManagementTipsRepository(),
      service: okService(),
      connectivity: ConnectivityStatus.online,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Sem dicas de manejo ainda'), findsOneWidget);
    expect(find.text('Gerar dicas'), findsOneWidget);
  });

  // Tips compose on the device from the corpus the app holds (ADR 0022), so
  // being offline changes nothing about them (SPEC 0090).
  group('offline', () {
    testWidgets('offline_empty_cache_offers_generate_tips', (tester) async {
      await tester.pumpWidget(harness(
        record: tipsRecord(),
        repo: FakeManagementTipsRepository(),
        service: okService(),
        connectivity: ConnectivityStatus.offline,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Gerar dicas'), findsOneWidget);
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

      await tester.tap(find.text('Gerar dicas'));
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

      await tester.tap(find.text('Gerar dicas'));
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
      find.text('Este registro foi salvo sem a classe de textura, e as dicas '
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
    await tester.pumpAndSettle();

    await tester.tap(find.text('Gerar dicas'));
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

    await tester.tap(find.text('Gerar dicas'));
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

  // The disclaimer's icon is meaningful, so it needs 3 : 1 on its banner, as
  // the confidence banner's already has (SPEC 0127).
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
      expect(icon.color, palette.onWarningContainer);
      expect(
        contrast(icon.color!, palette.warningContainer),
        greaterThanOrEqualTo(3),
      );

      await tester.pumpWidget(const SizedBox());
    }
  });

  // In high contrast the disclaimer's edge is its own text colour, solid and
  // 2 dp wide (SPEC 0135).
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
    expect(edge.color, AppPalette.lightHighContrast.onWarningContainer);
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

    Future<void> pumpTimeline(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = FakeManagementTipsRepository()..seed('rec-1', twoCategories());
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
      expect(find.text('Guia de solos · Embrapa +1'), findsOneWidget);
      expect(find.byIcon(LucideIcons.tractor), findsOneWidget);
      expect(find.byIcon(LucideIcons.droplets), findsOneWidget);
    });

    testWidgets('tips_header_counts_the_tips', (tester) async {
      await pumpTimeline(tester);
      expect(find.text('Média · 2 dicas'), findsOneWidget);
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

    Future<void> pumpPage(WidgetTester tester, {bool asPage = true}) async {
      await tester.binding.setSurfaceSize(const Size(390, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = FakeManagementTipsRepository()..seed('rec-1', twoGroups());
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
                record: tipsRecord().copyWith(
                  fieldName: 'Talhão 3',
                  sampleLabel: 'Amostra 2',
                ),
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
      expect(find.text('Talhão 3 · Amostra 2'), findsOneWidget);
      expect(find.text('2 dicas'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('tips-record-photo'))),
        const Size(56, 56),
      );
      expect(find.text('Dicas de manejo'), findsNothing);
    });

    testWidgets('disclaimer_comes_first', (tester) async {
      await pumpPage(tester);

      final banner = find.byKey(const Key('tips-disclaimer'));
      expect(
        tester.getTopLeft(banner).dy,
        lessThan(tester.getTopLeft(find.text('Preparo do solo')).dy),
      );
      final decoration =
          tester.widget<Container>(banner).decoration! as BoxDecoration;
      expect(decoration.border, isNull);
    });

    testWidgets('timeline_matches_the_mock', (tester) async {
      await pumpPage(tester);

      expect(tester.widget<Text>(find.text('Preparo do solo')).style?.fontSize,
          17);
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
        15,
      );
    });
  });
}
