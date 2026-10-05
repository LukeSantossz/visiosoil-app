import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/details/management_tips_section.dart';
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
    expect(find.text('[1]'), findsOneWidget);
    expect(find.text('Fontes'), findsOneWidget);
    expect(find.textContaining('consultivo'), findsOneWidget);
    expect(find.text('Atualizar dicas'), findsOneWidget);
    expect(find.textContaining('recomenda'), findsNothing);
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
    expect(find.text('Gerando dicas de manejo…'), findsOneWidget);

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
        matching: find.byIcon(Icons.info_outline),
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
}
